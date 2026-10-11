// SPDX-License-Identifier: 0BSD
#include "containers.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cstring>
namespace terraforest {
using namespace godot;
void NativeContainerStore::_bind_methods() {
    ClassDB::bind_method(D_METHOD("drag_slots","id","player","source_chest","target_chest","from","to","count","player_revision","store_revision"),&NativeContainerStore::drag_slots);
    ClassDB::bind_method(D_METHOD("configure","prototype","max_containers"),&NativeContainerStore::configure);
    ClassDB::bind_method(D_METHOD("snapshot","id"),&NativeContainerStore::snapshot);
    ClassDB::bind_method(D_METHOD("get_ids"),&NativeContainerStore::get_ids);
    ClassDB::bind_method(D_METHOD("has_contents","id"),&NativeContainerStore::has_contents);
    ClassDB::bind_method(D_METHOD("deposit","id","player","slot","count","player_revision","store_revision"),&NativeContainerStore::deposit);
    ClassDB::bind_method(D_METHOD("withdraw","id","player","slot","count","player_revision","store_revision"),&NativeContainerStore::withdraw);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeContainerStore::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeContainerStore::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","bytes"),&NativeContainerStore::restore_storage_snapshot);
}
Ref<NativePlayerInventory> NativeContainerStore::empty_inventory() const {
    Ref<NativePlayerInventory> out;out.instantiate();out->catalog_owner=schema;return out;
}
bool NativeContainerStore::configure(const Ref<NativePlayerInventory> &prototype,int64_t max_containers) {
    if(schema.is_valid()||prototype.is_null()||prototype->catalog().empty()||max_containers<1||max_containers>65536)return false;
    schema.instantiate();schema->limits=prototype->catalog();capacity=max_containers;return true;
}
Dictionary NativeContainerStore::snapshot(int64_t id) const {
    Dictionary out;out["ok"]=false;if(schema.is_null()||id<=0)return out;
    auto found=contents.find(id);out=(found==contents.end()?schema:found->second)->snapshot();
    out["ok"]=true;out["store_revision"]=found==contents.end()?revision:found->second->revision;return out;
}
PackedInt64Array NativeContainerStore::get_ids() const {
    PackedInt64Array out;out.resize(contents.size());int at=0;for(const auto &entry:contents)out.set(at++,entry.first);return out;
}
Dictionary NativeContainerStore::move(int64_t id,const Ref<NativePlayerInventory> &player,int64_t slot,int64_t count,int64_t player_revision,int64_t store_revision,bool depositing) {
    Dictionary out;out["ok"]=false;out["reason"]="invalid_container";
    if(schema.is_null()||player.is_null()||id<=0)return out;
    auto found=contents.find(id);
    if(store_revision!=(found==contents.end()?revision:found->second->revision)){out["reason"]="stale_container_view";return out;}
    if(!depositing&&found==contents.end()){out["reason"]="empty_container";return out;}
    if(found==contents.end()&&int64_t(contents.size())>=capacity){out["reason"]="container_capacity";return out;}
    Ref<NativePlayerInventory> box=found==contents.end()?empty_inventory():found->second;
    out=depositing?player->transfer_to(box,slot,count,player_revision,box->revision):box->transfer_to(player,slot,count,box->revision,player_revision);
    if(!bool(out["ok"]))return out;
    bool nonempty=false;for(const auto &item:box->slots)nonempty=nonempty||item.count>0;
    ++revision;box->revision=revision;
    if(nonempty)contents[id]=box;else contents.erase(id);
    out["store_revision"]=revision;out["player_revision"]=player->revision;return out;
}
Dictionary NativeContainerStore::drag_slots(int64_t id,const Ref<NativePlayerInventory> &player,bool source_chest,bool target_chest,int64_t from,int64_t to,int64_t count,int64_t player_revision,int64_t store_revision) {
    Dictionary out;out["ok"]=false;out["reason"]="invalid_drag";
    if(schema.is_null()||player.is_null()||id<=0||from<0||from>=32||to<0||to>=32||count<=0)return out;
    auto found=contents.find(id);
    if(player->revision!=player_revision||store_revision!=(found==contents.end()?revision:found->second->revision)){out["reason"]="stale_revision";return out;}
    if(source_chest&&found==contents.end())return out;
    if(target_chest&&found==contents.end()&&int64_t(contents.size())>=capacity){out["reason"]="container_capacity";return out;}
    auto box=found==contents.end()?empty_inventory():found->second;
    auto source=source_chest?box:player;auto target=target_chest?box:player;
    if(source==target) {
        out=source->transfer(from,to,count,source->revision);
        if(!bool(out["ok"]))return out;
    } else {
        auto a=source->slots[from],b=target->slots[to];
        if(!a.item||count>a.count)return out;
        auto limit=target->catalog().find(a.item);
        if(limit==target->catalog().end()){out["reason"]="invalid_item";return out;}
        if(b.item&&b.item!=a.item) {
            auto back=source->catalog().find(b.item);
            if(count!=a.count||a.count>limit->second||back==source->catalog().end()||b.count>back->second){out["reason"]="partial_swap";return out;}
            std::swap(a,b);
        } else {
            if(count>limit->second-b.count){out["reason"]="stack_full";return out;}
            b.item=a.item;b.count+=count;a.count-=count;if(!a.count)a.item=0;
        }
        // No callbacks between either commit. Invalid targets preserve both sides.
        source->slots[from]=a;target->slots[to]=b;++source->revision;++target->revision;
    }
    if(source_chest||target_chest) {
        bool nonempty=false;for(const auto &item:box->slots)nonempty=nonempty||item.count>0;
        ++revision;box->revision=revision;
        if(nonempty)contents[id]=box;else contents.erase(id);
    }
    out["ok"]=true;out["reason"]="";return out;
}
PackedByteArray NativeContainerStore::capture_storage_snapshot() const {
    if(schema.is_null())return {};
    PackedByteArray out;out.resize(16+contents.size()*272);
    std::memcpy(out.ptrw(),"TFCS\1\0\0\0",8);out.encode_u64(8,contents.size());
    int64_t at=16;for(const auto &entry:contents) {
        out.encode_u64(at,entry.first);auto bytes=entry.second->capture_storage_snapshot();
        std::memcpy(out.ptrw()+at+8,bytes.ptr(),264);at+=272;
    }
    return out;
}
bool NativeContainerStore::validate_snapshot(const PackedByteArray &bytes) const {
    if(schema.is_null()||bytes.size()<16||std::memcmp(bytes.ptr(),"TFCS\1\0\0\0",8))return false;
    uint64_t count=bytes.decode_u64(8),last=0;
    if(count>uint64_t(capacity)||uint64_t(bytes.size())!=16+count*272)return false;
    for(uint64_t i=0;i<count;++i) {
        int64_t at=16+i*272;uint64_t id=bytes.decode_u64(at);
        if(id<=last||id>uint64_t(INT64_MAX))return false;last=id;
        auto inventory=bytes.slice(at+8,at+272);if(!schema->validate_snapshot(inventory))return false;
        bool nonempty=false;for(int slot=0;slot<32;++slot)nonempty=nonempty||inventory.decode_u32(12+slot*8)>0;
        if(!nonempty)return false;
    }
    return true;
}
bool NativeContainerStore::restore_storage_snapshot(const PackedByteArray &bytes) {
    if(!validate_snapshot(bytes))return false;
    decltype(contents) staged;uint64_t count=bytes.decode_u64(8);int64_t next_revision=revision+1;
    for(uint64_t i=0;i<count;++i) {
        int64_t at=16+i*272;auto inventory=empty_inventory();
        inventory->restore_storage_snapshot(bytes.slice(at+8,at+272));inventory->revision=++next_revision;staged.emplace(bytes.decode_u64(at),inventory);
    }
    contents=std::move(staged);revision=next_revision;return true;
}
}
