// SPDX-License-Identifier: 0BSD
#include "inventory.hpp"
#include <algorithm>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
namespace terraforest {
using namespace godot;
void NativePlayerInventory::_bind_methods() {
    ClassDB::bind_method(D_METHOD("exchange_bucket","slot","pour","revision","litres"),&NativePlayerInventory::exchange_bucket,DEFVAL(1));
    ClassDB::bind_method(D_METHOD("register_durable","item","maximum"),&NativePlayerInventory::register_durable);
    ClassDB::bind_method(D_METHOD("wear_tool","slot","amount","expected_revision"),&NativePlayerInventory::wear_tool);
    ClassDB::bind_method(D_METHOD("register_item","item","limit"),&NativePlayerInventory::register_item);
    ClassDB::bind_method(D_METHOD("snapshot"),&NativePlayerInventory::snapshot);
    ClassDB::bind_method(D_METHOD("grant","item","count","expected_revision"),&NativePlayerInventory::grant);
    ClassDB::bind_method(D_METHOD("grant_items","items","expected_revision"),&NativePlayerInventory::grant_items);
    ClassDB::bind_method(D_METHOD("can_receive","items","expected_revision"),&NativePlayerInventory::can_receive);
    ClassDB::bind_method(D_METHOD("exchange_items","costs","outputs","expected_revision"),&NativePlayerInventory::exchange_items);
    ClassDB::bind_method(D_METHOD("consume","slot","count","expected_revision"),&NativePlayerInventory::consume);
    ClassDB::bind_method(D_METHOD("consume_items","costs","expected_revision"),&NativePlayerInventory::consume_items);
    ClassDB::bind_method(D_METHOD("can_afford","costs","expected_revision"),&NativePlayerInventory::can_afford);
    ClassDB::bind_method(D_METHOD("transfer","from","to","count","expected_revision"),&NativePlayerInventory::transfer);
    ClassDB::bind_method(D_METHOD("transfer_to","destination","slot","count","expected_source_revision","expected_destination_revision"),&NativePlayerInventory::transfer_to);
    ClassDB::bind_method(D_METHOD("restore","snapshot","expected_revision"),&NativePlayerInventory::restore);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativePlayerInventory::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativePlayerInventory::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativePlayerInventory::restore_storage_snapshot);
}
Dictionary NativePlayerInventory::result(bool ok,const char *reason) const {
    Dictionary out;out["ok"]=ok;out["reason"]=reason;out["revision"]=revision;return out;
}
int64_t NativePlayerInventory::max_durability(int64_t item) const {
    auto found=durable_catalog().find(item);return found==durable_catalog().end()?0:found->second;
}
bool NativePlayerInventory::register_durable(int64_t item,int64_t maximum) {
    if(catalog_owner.is_valid()||revision||!limits.count(item)||limits.at(item)!=1||maximum<1||maximum>1000000)return false;
    durability[item]=maximum;return true;
}
Dictionary NativePlayerInventory::wear_tool(int64_t slot,int64_t amount,int64_t expected) {
    if(expected!=revision)return result(false,"stale_revision");
    if(slot<0||slot>=32||amount<1||amount>1000000||!max_durability(slots[slot].item))return result(false,"invalid_tool");
    auto &s=slots[slot];s.wear+=amount;bool broken=s.wear>=max_durability(s.item);
    if(broken)s={};++revision;auto out=result(true,"");out["broken"]=broken;return out;
}
bool NativePlayerInventory::register_item(int64_t item,int64_t limit) {
    if(catalog_owner.is_valid()||revision||item<=0||item>INT32_MAX||limit<1||limit>1000000||catalog().size()>=256||catalog().count(item))return false;
    limits[item]=limit;return true;
}
Dictionary NativePlayerInventory::snapshot() const {
    Dictionary out;out["schema"]=1;out["revision"]=revision;Array rows;
    for(auto s:slots){Dictionary row;row["item"]=s.item;row["count"]=s.count;row["wear"]=s.wear;row["durability"]=max_durability(s.item)-s.wear;row["max_durability"]=max_durability(s.item);rows.push_back(row);}
    out["slots"]=rows;return out;
}
Dictionary NativePlayerInventory::grant(int64_t item,int64_t count,int64_t expected) {
    if(expected!=revision)return result(false,"stale_revision");
    auto found=catalog().find(item);
    if(found==catalog().end()||count<=0)return result(false,"invalid_item_or_count");
    int64_t capacity=0;
    for(auto s:slots)if(!s.item||s.item==item)capacity+=found->second-s.count;
    if(count>capacity)return result(false,"full");
    // Fill existing stacks first, then empty slots. Preflight makes this atomic.
    for(int pass=0;pass<2&&count;pass++)for(auto &s:slots) {
        if((pass==0&&s.item!=item)||(pass==1&&s.item))continue;
        int64_t amount=std::min(count,found->second-s.count);
        if(amount){s.item=item;s.count+=amount;count-=amount;}
    }
    ++revision;return result(true,"");
}
Dictionary NativePlayerInventory::consume(int64_t slot,int64_t count,int64_t expected) {
    if(expected!=revision)return result(false,"stale_revision");
    if(slot<0||slot>=32||count<=0||count>slots[slot].count)return result(false,"invalid_count_or_slot");
    auto &s=slots[slot];s.count-=count;if(!s.count)s={};
    ++revision;return result(true,"");
}
Dictionary NativePlayerInventory::apply_grants(const PackedInt64Array &items,int64_t expected,bool commit) {
    if(expected!=revision)return result(false,"stale_revision");
    if(items.is_empty()||items.size()>64||items.size()%2)return result(false,"invalid_items");
    auto candidate=slots;
    for(int64_t i=0;i<items.size();i+=2){
        const int64_t item=items[i];int64_t count=items[i+1];
        auto found=catalog().find(item);
        if(found==catalog().end()||count<=0||count>32000000)return result(false,"invalid_item_or_count");
        // Stage at most 32 rows over 32 slots. Duplicate rows see the prior
        // staged result, without summing untrusted counts or allocating stacks.
        for(int pass=0;pass<2&&count;++pass)for(auto &slot:candidate){
            if((pass==0&&slot.item!=item)||(pass==1&&slot.item))continue;
            const int64_t amount=std::min(count,found->second-slot.count);
            if(amount){slot.item=item;slot.count+=amount;count-=amount;}
        }
        if(count){auto out=result(false,"full");out["item"]=item;out["missing_capacity"]=count;return out;}
    }
    if(commit){slots=candidate;++revision;}
    return result(true,"");
}
Dictionary NativePlayerInventory::grant_items(const PackedInt64Array &items,int64_t expected) { return apply_grants(items,expected,true); }
Dictionary NativePlayerInventory::can_receive(const PackedInt64Array &items,int64_t expected) { return apply_grants(items,expected,false); }
Dictionary NativePlayerInventory::exchange_items(const PackedInt64Array &costs,const PackedInt64Array &outputs,int64_t expected) {
    // These mutators are main-thread only and emit no callbacks. Retain the
    // bounded original state until both operations succeed; freed input slots
    // are available to outputs. Never expose intermediate revisions to callers.
    const auto original=slots;const int64_t original_revision=revision;
    Dictionary consumed=apply_costs(costs,expected,true);
    if(!bool(consumed["ok"]))return consumed;
    Dictionary granted=apply_grants(outputs,revision,true);
    if(!bool(granted["ok"])){
        slots=original;revision=original_revision;granted["revision"]=revision;return granted;
    }
    revision=original_revision+1;return result(true,"");
}
Dictionary NativePlayerInventory::apply_costs(const PackedInt64Array &costs,int64_t expected,bool commit) {
    if(expected!=revision)return result(false,"stale_revision");
    if(costs.is_empty()||costs.size()>64||costs.size()%2)return result(false,"invalid_costs");
    // At most 32 item/count pairs and 32 slots; stage all deductions before
    // publishing. Duplicate item rows consume cumulatively without overflow.
    auto candidate=slots;
    for(int64_t i=0;i<costs.size();i+=2){
        const int64_t item=costs[i];int64_t remaining=costs[i+1];
        if(catalog().find(item)==catalog().end()||remaining<=0||remaining>32000000)return result(false,"invalid_item_or_count");
        for(auto &slot:candidate){
            if(slot.item!=item)continue;
            const int64_t amount=std::min(remaining,slot.count);
            remaining-=amount;slot.count-=amount;if(!slot.count)slot={};
            if(!remaining)break;
        }
        if(remaining){auto out=result(false,"insufficient_items");out["item"]=item;out["missing"]=remaining;return out;}
    }
    if(commit){slots=candidate;++revision;}
    return result(true,"");
}
Dictionary NativePlayerInventory::consume_items(const PackedInt64Array &costs,int64_t expected) { return apply_costs(costs,expected,true); }
Dictionary NativePlayerInventory::can_afford(const PackedInt64Array &costs,int64_t expected) { return apply_costs(costs,expected,false); }
Dictionary NativePlayerInventory::transfer(int64_t from,int64_t to,int64_t count,int64_t expected) {
    if(expected!=revision)return result(false,"stale_revision");
    if(from<0||from>=32||to<0||to>=32||from==to||count<=0||count>slots[from].count)return result(false,"invalid_transfer");
    auto &a=slots[from];auto &b=slots[to];
    if(b.item&&(b.item!=a.item||max_durability(a.item))){
        if(count!=a.count)return result(false,"partial_swap");
        std::swap(a,b);
    }else{
        if(count>catalog().at(a.item)-b.count)return result(false,"stack_full");
        b.item=a.item;b.wear=a.wear;b.count+=count;a.count-=count;if(!a.count)a={};
    }
    ++revision;return result(true,"");
}
Dictionary NativePlayerInventory::transfer_to(const Ref<NativePlayerInventory> &destination,int64_t slot,int64_t count,int64_t expected_source,int64_t expected_destination) {
    // Main-thread authority operation. No signals/callbacks between the two
    // commits. Preflight rejects stale views and capacity/catalog mismatches;
    // failures preserve both contents AND revisions. Source reads are O(1),
    // destination grant visits at most 32 fixed slots (no world-size scan).
    auto *target=destination.ptr();
    if(!target||target==this)return result(false,"invalid_destination");
    if(expected_source!=revision||expected_destination!=target->revision)return result(false,"stale_revision");
    if(slot<0||slot>=32||count<=0||count>slots[slot].count)return result(false,"invalid_count_or_slot");
    const int64_t item=slots[slot].item;
    if(max_durability(item)!=target->max_durability(item))return result(false,"durability_schema_mismatch");
    int target_slot=-1;
    if(max_durability(item))for(int i=0;i<32;++i)if(!target->slots[i].item){target_slot=i;break;}
    Dictionary granted=target->grant(item,count,expected_destination);
    if(!bool(granted["ok"])) {
        Dictionary failed=result(false,"destination_rejected");failed["detail"]=granted["reason"];return failed;
    }
    if(target_slot>=0)target->slots[target_slot].wear=slots[slot].wear;
    auto &source=slots[slot];source.count-=count;if(!source.count)source={};
    ++revision;
    Dictionary completed=result(true,"");completed["destination_revision"]=target->revision;
    completed["item"]=item;completed["count"]=count;return completed;
}
Dictionary NativePlayerInventory::restore(const Dictionary &data,int64_t expected) {
    if(expected!=revision)return result(false,"stale_revision");
    Variant schema=data.get("schema",Variant()),raw=data.get("slots",Variant());
    if(schema.get_type()!=Variant::INT||int64_t(schema)!=1||raw.get_type()!=Variant::ARRAY)return result(false,"invalid_snapshot");
    Array rows=raw;if(rows.size()!=32)return result(false,"invalid_snapshot");
    std::array<Stack,32> candidate{};
    for(int i=0;i<32;i++) {
        if(rows[i].get_type()!=Variant::DICTIONARY)return result(false,"invalid_snapshot");
        Dictionary row=rows[i];Variant item=row.get("item",Variant()),count=row.get("count",Variant());
        if(item.get_type()!=Variant::INT||count.get_type()!=Variant::INT)return result(false,"invalid_snapshot");
        int64_t id=item,n=count;
        if((id==0&&n!=0)||(id!=0&&(catalog().find(id)==catalog().end()||n<=0||n>catalog().at(id))))return result(false,"invalid_snapshot");
        Variant wear=row.get("wear",int64_t(0));
        if(wear.get_type()!=Variant::INT)return result(false,"invalid_wear");
        int64_t w=wear;
        if(w<0||(w>0&&(!max_durability(id)||w>=max_durability(id))))return result(false,"invalid_wear");
        candidate[i]={id,n,w};
    }
    slots=candidate;++revision;return result(true,"");
}
namespace {
uint32_t read_u32(const uint8_t *p) {
    return uint32_t(p[0])|(uint32_t(p[1])<<8)|(uint32_t(p[2])<<16)|(uint32_t(p[3])<<24);
}
void write_u32(uint8_t *p,uint32_t n) {
    for(int b=0;b<4;++b)p[b]=uint8_t(n>>(8*b));
}
}
PackedByteArray NativePlayerInventory::capture_storage_snapshot() const {
    PackedByteArray data;data.resize(392);data.encode_u32(0,0x32564654);data.encode_u32(4,32);
    for(int i=0;i<32;++i){data.encode_u32(8+i*12,slots[i].item);data.encode_u32(12+i*12,slots[i].count);data.encode_u32(16+i*12,slots[i].wear);}return data;
}
bool NativePlayerInventory::validate_snapshot(const PackedByteArray &data) const {
    const bool old=data.size()==264;const int stride=old?8:12;
    if((!old&&data.size()!=392)||data.decode_u32(0)!=(old?0x31564654:0x32564654)||data.decode_u32(4)!=32)return false;
    for(int i=0;i<32;++i){
        auto id=data.decode_u32(8+i*stride),n=data.decode_u32(12+i*stride),w=old?0:data.decode_u32(16+i*stride);
        auto found=catalog().find(id);
        if(id==0 ? n!=0 : found==catalog().end()||n==0||n>found->second)return false;
        if(w&&(!max_durability(id)||w>=max_durability(id)))return false;
    }return true;
}
bool NativePlayerInventory::restore_storage_snapshot(const PackedByteArray &data) {
    if(!validate_snapshot(data))return false;const bool old=data.size()==264;const int stride=old?8:12;
    for(int i=0;i<32;++i)slots[i]={data.decode_u32(8+i*stride),data.decode_u32(12+i*stride),old?0:data.decode_u32(16+i*stride)};
    ++revision;return true;
}
}

namespace terraforest {
bool NativePlayerInventory::exchange_bucket(int64_t slot,bool pour,int64_t expected,int64_t litres){
    if(expected!=revision||slot<0||slot>=32||litres<1||litres>10)return false;
    auto &s=slots[slot];if(s.count!=1||s.item<401||s.item>411||(pour?s.item==401:s.item==411))return false;
    const int64_t next=s.item+(pour?-litres:litres);if(next<401||next>411||!catalog().count(next))return false;s.item=next;++revision;return true;
}
}
