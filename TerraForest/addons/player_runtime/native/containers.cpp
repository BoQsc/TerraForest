// SPDX-License-Identifier: 0BSD
#include "containers.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cstring>
namespace terraforest {
using namespace godot;
void NativeContainerStore::_bind_methods() {
    ClassDB::bind_method(D_METHOD("seed_contents","id","items"),&NativeContainerStore::seed_contents);
    ClassDB::bind_method(D_METHOD("drag_slots","id","player","source_chest","target_chest","from","to","count","player_revision","store_revision"),&NativeContainerStore::drag_slots);
    ClassDB::bind_method(D_METHOD("configure","prototype","max_containers","slots","pick_item"),&NativeContainerStore::configure,DEFVAL(32),DEFVAL(0));
    ClassDB::bind_method(D_METHOD("seed_lock","id","maximum","seed"),&NativeContainerStore::seed_lock);
    ClassDB::bind_method(D_METHOD("is_locked","id"),&NativeContainerStore::is_locked);
    ClassDB::bind_method(D_METHOD("requires_protection","id"),&NativeContainerStore::requires_protection);
    ClassDB::bind_method(D_METHOD("lock_state","id"),&NativeContainerStore::lock_state);
    ClassDB::bind_method(D_METHOD("attempt_unlock","id","player","player_revision","store_revision"),&NativeContainerStore::attempt_unlock);
    ClassDB::bind_method(D_METHOD("damage_lock","id","damage","store_revision"),&NativeContainerStore::damage_lock);
    ClassDB::bind_method(D_METHOD("snapshot","id"),&NativeContainerStore::snapshot);
    ClassDB::bind_method(D_METHOD("get_ids"),&NativeContainerStore::get_ids);
    ClassDB::bind_method(D_METHOD("has_contents","id"),&NativeContainerStore::has_contents);
    ClassDB::bind_method(D_METHOD("deposit","id","player","slot","count","player_revision","store_revision"),&NativeContainerStore::deposit);
    ClassDB::bind_method(D_METHOD("withdraw","id","player","slot","count","player_revision","store_revision"),&NativeContainerStore::withdraw);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeContainerStore::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("container_patch_state"),&NativeContainerStore::container_patch_state);
    ClassDB::bind_method(D_METHOD("capture_container_patch","ids","expected_revision","expected_owner"),&NativeContainerStore::capture_container_patch);
    ClassDB::bind_method(D_METHOD("validate_container_patch","bytes"),&NativeContainerStore::validate_container_patch);
    ClassDB::bind_method(D_METHOD("restore_container_patch","bytes","expected_revision","expected_owner"),&NativeContainerStore::restore_container_patch);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeContainerStore::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","bytes"),&NativeContainerStore::restore_storage_snapshot);
}
Ref<NativePlayerInventory> NativeContainerStore::empty_inventory() const {
    Ref<NativePlayerInventory> out;out.instantiate();out->catalog_owner=schema;out->slot_limit=slot_count;return out;
}
Ref<NativePlayerInventory> NativeContainerStore::staged_inventory(const PackedByteArray &bytes,int64_t next_revision) const {
    auto value=empty_inventory();if(value.is_null()||!value->restore_storage_snapshot(bytes))return {};
    value->slot_limit=visible_slots(value);value->revision=next_revision;return value;
}
int NativeContainerStore::visible_slots(const Ref<NativePlayerInventory> &inventory) const{
    int count=slot_count;for(int index=slot_count;index<32;index++)if(inventory->slots[index].count)count=index+1;return count;
}
bool NativeContainerStore::initialize_contents(int64_t id,const PackedInt64Array &items){
    if(schema.is_null()||id<=0||contents.count(id)||(!is_locked(id)&&int64_t(contents.size())+lock_only_count>=capacity))return false;
    auto box=empty_inventory();Dictionary granted=box->grant_items(items,0);
    if(!bool(granted["ok"]))return false;
    if(is_locked(id))--lock_only_count;
    contents[id]=box;touch(id);return true;
}
bool NativeContainerStore::configure(const Ref<NativePlayerInventory> &prototype,int64_t max_containers,int64_t slots,int64_t pick_item) {
    if(schema.is_valid()||prototype.is_null()||prototype->catalog().empty()||max_containers<1||max_containers>65536||slots<1||slots>32||pick_item<0||(pick_item>0&&(!supports_locks()||!prototype->has_item(pick_item))))return false;
    schema.instantiate();schema->limits=prototype->catalog();schema->durability=prototype->durable_catalog();capacity=max_containers;slot_count=int(slots);schema->slot_limit=slot_count;lockpick_item=pick_item;return true;
}
int64_t NativeContainerStore::view_revision(int64_t id) const {
    auto inventory=contents.find(id);auto lock=locks.find(id);
    if(inventory==contents.end()&&lock==locks.end())return revision;
    return std::max(inventory==contents.end()?int64_t(0):inventory->second->revision,lock==locks.end()?int64_t(0):lock->second.revision);
}
void NativeContainerStore::touch(int64_t id){
    ++revision;auto inventory=contents.find(id);auto lock=locks.find(id);
    if(inventory!=contents.end())inventory->second->revision=revision;
    if(lock!=locks.end())lock->second.revision=revision;
}
bool NativeContainerStore::seed_lock(int64_t id,int64_t maximum,int64_t seed){
    if(schema.is_null()||lockpick_item==0||id<=0||maximum<1||maximum>1000000||seed<0||locks.count(id)||(!has_contents(id)&&int64_t(contents.size())+lock_only_count>=capacity))return false;
    uint64_t random=uint64_t(seed)^uint64_t(id)*0x9e3779b97f4a7c15ULL;
    random=(random^(random>>30))*0xbf58476d1ce4e5b9ULL;random=(random^(random>>27))*0x94d049bb133111ebULL;random^=random>>31;
    if(!has_contents(id))++lock_only_count;
    locks[id]={uint32_t(maximum),uint32_t(maximum),random?random:1,0};touch(id);return true;
}
Dictionary NativeContainerStore::lock_state(int64_t id) const {
    Dictionary result;result["ok"]=schema.is_valid()&&id>0;result["locked"]=false;result["remaining"]=0;result["maximum"]=0;result["store_revision"]=view_revision(id);
    auto found=locks.find(id);if(found!=locks.end()){result["locked"]=true;result["remaining"]=found->second.remaining;result["maximum"]=found->second.maximum;}
    return result;
}
Dictionary NativeContainerStore::attempt_unlock(int64_t id,const Ref<NativePlayerInventory> &player,int64_t player_revision,int64_t store_revision){
    Dictionary result;result["ok"]=false;result["opened"]=false;result["broken_pick"]=false;result["reason"]="invalid_lock";
    auto found=locks.find(id);if(found==locks.end()||player.is_null()||lockpick_item==0)return result;
    if(player->revision!=player_revision||view_revision(id)!=store_revision){result["reason"]="stale_revision";return result;}
    PackedInt64Array cost;cost.append(lockpick_item);cost.append(1);
    if(!bool(player->can_afford(cost,player_revision)["ok"])){result["reason"]="missing_lockpick";return result;}
    uint64_t random=found->second.random_state;random^=random>>12;random^=random<<25;random^=random>>27;
    const bool broken=(random*2685821657736338717ULL)%10==0;
    if(broken&&!bool(player->consume_items(cost,player_revision)["ok"])){result["reason"]="inventory_changed";return result;}
    if(broken)found->second.random_state=random;else {if(!has_contents(id))--lock_only_count;locks.erase(found);}
    touch(id);result["ok"]=true;result["opened"]=!broken;result["broken_pick"]=broken;result["reason"]=broken?"lockpick_broke":"";result["store_revision"]=view_revision(id);return result;
}
Dictionary NativeContainerStore::damage_lock(int64_t id,int64_t damage,int64_t store_revision){
    Dictionary result;result["ok"]=false;result["opened"]=false;result["reason"]="invalid_lock";
    auto found=locks.find(id);if(found==locks.end()||damage<=0||damage>1000000)return result;
    if(view_revision(id)!=store_revision){result["reason"]="stale_revision";return result;}
    const uint32_t applied=uint32_t(std::min(damage,int64_t(found->second.remaining)));
    found->second.remaining-=applied;result["remaining"]=found->second.remaining;result["maximum"]=found->second.maximum;result["applied"]=applied;
    const bool opened=found->second.remaining==0;if(opened){if(!has_contents(id))--lock_only_count;locks.erase(found);}
    touch(id);result["ok"]=true;result["opened"]=opened;result["reason"]="";result["store_revision"]=view_revision(id);return result;
}
Dictionary NativeContainerStore::snapshot(int64_t id) const {
    Dictionary out;out["ok"]=false;if(schema.is_null()||id<=0)return out;
    auto found=contents.find(id);out=(found==contents.end()?schema:found->second)->snapshot();
    out["ok"]=true;out["store_revision"]=view_revision(id);out["locked"]=is_locked(id);return out;
}
PackedInt64Array NativeContainerStore::get_ids() const {
    PackedInt64Array out;out.resize(contents.size()+locks.size());int at=0;auto inventory=contents.begin();auto lock=locks.begin();
    while(inventory!=contents.end()||lock!=locks.end()){
        const int64_t id=lock==locks.end()?inventory->first:(inventory==contents.end()?lock->first:std::min(inventory->first,lock->first));
        out.set(at++,id);if(inventory!=contents.end()&&inventory->first==id)++inventory;if(lock!=locks.end()&&lock->first==id)++lock;
    }
    out.resize(at);return out;
}
Dictionary NativeContainerStore::move(int64_t id,const Ref<NativePlayerInventory> &player,int64_t slot,int64_t count,int64_t player_revision,int64_t store_revision,bool depositing) {
    Dictionary out;out["ok"]=false;out["reason"]="invalid_container";
    if(schema.is_null()||player.is_null()||id<=0)return out;
    if(is_locked(id)){out["reason"]="container_locked";return out;}
    auto found=contents.find(id);
    if(store_revision!=(found==contents.end()?revision:found->second->revision)){out["reason"]="stale_container_view";return out;}
    if(!depositing&&found==contents.end()){out["reason"]="empty_container";return out;}
    if(found==contents.end()&&int64_t(contents.size())+lock_only_count>=capacity){out["reason"]="container_capacity";return out;}
    Ref<NativePlayerInventory> box=found==contents.end()?empty_inventory():found->second;
    box->slot_limit=visible_slots(box);
    out=depositing?player->transfer_to(box,slot,count,player_revision,box->revision):box->transfer_to(player,slot,count,box->revision,player_revision);
    if(!bool(out["ok"]))return out;
    box->slot_limit=visible_slots(box);
    bool nonempty=false;for(const auto &item:box->slots)nonempty=nonempty||item.count>0;
    ++revision;box->revision=revision;
    if(nonempty)contents[id]=box;else contents.erase(id);
    out["store_revision"]=revision;out["player_revision"]=player->revision;return out;
}
Dictionary NativeContainerStore::drag_slots(int64_t id,const Ref<NativePlayerInventory> &player,bool source_chest,bool target_chest,int64_t from,int64_t to,int64_t count,int64_t player_revision,int64_t store_revision) {
    Dictionary out;out["ok"]=false;out["reason"]="invalid_drag";
    if(schema.is_null()||player.is_null()||id<=0||from<0||from>=32||to<0||to>=32||count<=0)return out;
    if((source_chest||target_chest)&&is_locked(id)){out["reason"]="container_locked";return out;}
    auto found=contents.find(id);
    if(player->revision!=player_revision||store_revision!=view_revision(id)){out["reason"]="stale_revision";return out;}
    if(source_chest&&found==contents.end())return out;
    if(target_chest&&found==contents.end()&&int64_t(contents.size())+lock_only_count>=capacity){out["reason"]="container_capacity";return out;}
    auto box=found==contents.end()?empty_inventory():found->second;
    box->slot_limit=visible_slots(box);
    if((source_chest&&from>=box->slot_limit)||(target_chest&&to>=box->slot_limit)){out["reason"]="container_capacity";return out;}
    auto source=source_chest?box:player;auto target=target_chest?box:player;
    if(source==target) {
        out=source->transfer(from,to,count,source->revision);
        if(!bool(out["ok"]))return out;
    } else {
        auto a=source->slots[from],b=target->slots[to];
        if(!a.item||count>a.count)return out;
        auto limit=target->catalog().find(a.item);
        if(limit==target->catalog().end()){out["reason"]="invalid_item";return out;}
        if(source->max_durability(a.item)!=target->max_durability(a.item)){out["reason"]="durability_schema_mismatch";return out;}
        if(b.item&&source->max_durability(b.item)!=target->max_durability(b.item)){out["reason"]="durability_schema_mismatch";return out;}
        if(b.item&&(b.item!=a.item||source->max_durability(a.item)||NativePlayerInventory::water_container(a.item))) {
            auto back=source->catalog().find(b.item);
            if(count!=a.count||a.count>limit->second||back==source->catalog().end()||b.count>back->second){out["reason"]="partial_swap";return out;}
            std::swap(a,b);
        } else {
            if(count>limit->second-b.count){out["reason"]="stack_full";return out;}
            b.item=a.item;b.wear=a.wear;b.water_ml=a.water_ml;b.count+=count;a.count-=count;if(!a.count)a={};
        }
        // No callbacks between either commit. Invalid targets preserve both sides.
        source->slots[from]=a;target->slots[to]=b;++source->revision;++target->revision;
    }
    if(source_chest||target_chest) {
        box->slot_limit=visible_slots(box);
        bool nonempty=false;for(const auto &item:box->slots)nonempty=nonempty||item.count>0;
        ++revision;box->revision=revision;
        if(nonempty)contents[id]=box;else contents.erase(id);
    }
    out["ok"]=true;out["reason"]="";return out;
}
PackedByteArray NativeContainerStore::capture_storage_snapshot() const {
    if(schema.is_null())return {};
    const int header=locks.empty()?16:24;
    PackedByteArray out;out.resize(header+contents.size()*528+locks.size()*24);
    std::memcpy(out.ptrw(),locks.empty()?"TFCS\3\0\0\0":"TFCS\4\0\0\0",8);out.encode_u64(8,contents.size());if(!locks.empty())out.encode_u64(16,locks.size());
    int64_t at=header;for(const auto &entry:contents) {
        out.encode_u64(at,entry.first);auto bytes=entry.second->capture_storage_snapshot();
        std::memcpy(out.ptrw()+at+8,bytes.ptr(),520);at+=528;
    }
    for(const auto &entry:locks){out.encode_u64(at,entry.first);out.encode_u32(at+8,entry.second.remaining);out.encode_u32(at+12,entry.second.maximum);out.encode_u64(at+16,entry.second.random_state);at+=24;}
    return out;
}
bool NativeContainerStore::validate_snapshot(const PackedByteArray &bytes) const {
    if(schema.is_null()||bytes.size()<16||(std::memcmp(bytes.ptr(),"TFCS\1\0\0\0",8)&&std::memcmp(bytes.ptr(),"TFCS\2\0\0\0",8)&&std::memcmp(bytes.ptr(),"TFCS\3\0\0\0",8)&&std::memcmp(bytes.ptr(),"TFCS\4\0\0\0",8)))return false;
    const int header=bytes[4]==4?24:16;if(bytes.size()<header)return false;
    const uint64_t lock_count=bytes[4]==4?bytes.decode_u64(16):0;
    if(lock_count>uint64_t(capacity)||(bytes[4]==4&&(lock_count==0||lockpick_item==0)))return false;
    const int stride=bytes[4]==1?272:(bytes[4]==2?400:528);
    uint64_t count=bytes.decode_u64(8),last=0;
    if(count>uint64_t(capacity)||uint64_t(bytes.size())!=header+count*stride+lock_count*24)return false;
    for(uint64_t i=0;i<count;++i) {
        int64_t at=header+i*stride;uint64_t id=bytes.decode_u64(at);
        if(id<=last||id>uint64_t(INT64_MAX))return false;last=id;
        auto inventory=bytes.slice(at+8,at+stride);if(!schema->validate_snapshot(inventory))return false;
        bool nonempty=false;for(int slot=0;slot<32;++slot)nonempty=nonempty||inventory.decode_u32(12+slot*(stride==272?8:(stride==400?12:16)))>0;
        if(!nonempty)return false;
    }
    last=0;uint64_t content_index=0,identities=count;
    for(uint64_t index=0;index<lock_count;++index){
        const int64_t at=header+count*stride+index*24;const uint64_t id=bytes.decode_u64(at);
        const uint32_t remaining=bytes.decode_u32(at+8),maximum=bytes.decode_u32(at+12);
        if(id<=last||id>uint64_t(INT64_MAX)||remaining==0||remaining>maximum||maximum>1000000||bytes.decode_u64(at+16)==0)return false;last=id;
        while(content_index<count&&bytes.decode_u64(header+content_index*stride)<id)++content_index;
        if(content_index==count||bytes.decode_u64(header+content_index*stride)!=id)++identities;
        if(identities>uint64_t(capacity))return false;
    }
    return true;
}
bool NativeContainerStore::restore_storage_snapshot(const PackedByteArray &bytes) {
    if(!NativeContainerStore::validate_snapshot(bytes))return false;
    const int stride=bytes[4]==1?272:(bytes[4]==2?400:528);
    const int header=bytes[4]==4?24:16;const uint64_t lock_count=bytes[4]==4?bytes.decode_u64(16):0;
    decltype(contents) staged;uint64_t count=bytes.decode_u64(8);int64_t next_revision=revision+1;
    for(uint64_t i=0;i<count;++i) {
        int64_t at=header+i*stride;auto inventory=empty_inventory();
        inventory->restore_storage_snapshot(bytes.slice(at+8,at+stride));inventory->slot_limit=visible_slots(inventory);inventory->revision=++next_revision;staged.emplace(bytes.decode_u64(at),inventory);
    }
    decltype(locks) staged_locks;
    for(uint64_t index=0;index<lock_count;++index){const int64_t at=header+count*stride+index*24;staged_locks[bytes.decode_u64(at)]={uint32_t(bytes.decode_u32(at+8)),uint32_t(bytes.decode_u32(at+12)),uint64_t(bytes.decode_u64(at+16)),++next_revision};}
    lock_only_count=0;for(const auto &entry:staged_locks)if(!staged.count(entry.first))++lock_only_count;
    contents=std::move(staged);locks=std::move(staged_locks);revision=next_revision;return true;
}
}
