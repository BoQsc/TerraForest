// SPDX-License-Identifier: 0BSD
#include "inventory.hpp"
#include <algorithm>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
namespace terraforest {
using namespace godot;
void NativePlayerInventory::_bind_methods() {
    ClassDB::bind_method(D_METHOD("register_item","item","limit"),&NativePlayerInventory::register_item);
    ClassDB::bind_method(D_METHOD("snapshot"),&NativePlayerInventory::snapshot);
    ClassDB::bind_method(D_METHOD("grant","item","count","expected_revision"),&NativePlayerInventory::grant);
    ClassDB::bind_method(D_METHOD("consume","slot","count","expected_revision"),&NativePlayerInventory::consume);
    ClassDB::bind_method(D_METHOD("consume_items","costs","expected_revision"),&NativePlayerInventory::consume_items);
    ClassDB::bind_method(D_METHOD("can_afford","costs","expected_revision"),&NativePlayerInventory::can_afford);
    ClassDB::bind_method(D_METHOD("transfer","from","to","count","expected_revision"),&NativePlayerInventory::transfer);
    ClassDB::bind_method(D_METHOD("restore","snapshot","expected_revision"),&NativePlayerInventory::restore);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativePlayerInventory::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativePlayerInventory::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativePlayerInventory::restore_storage_snapshot);
}
Dictionary NativePlayerInventory::result(bool ok,const char *reason) const {
    Dictionary out;out["ok"]=ok;out["reason"]=reason;out["revision"]=revision;return out;
}
bool NativePlayerInventory::register_item(int64_t item,int64_t limit) {
    if(revision||item<=0||item>INT32_MAX||limit<1||limit>1000000||limits.size()>=256||limits.count(item))return false;
    limits[item]=limit;return true;
}
Dictionary NativePlayerInventory::snapshot() const {
    Dictionary out;out["schema"]=1;out["revision"]=revision;Array rows;
    for(auto s:slots){Dictionary row;row["item"]=s.item;row["count"]=s.count;rows.push_back(row);}
    out["slots"]=rows;return out;
}
Dictionary NativePlayerInventory::grant(int64_t item,int64_t count,int64_t expected) {
    if(expected!=revision)return result(false,"stale_revision");
    auto found=limits.find(item);
    if(found==limits.end()||count<=0)return result(false,"invalid_item_or_count");
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
    auto &s=slots[slot];s.count-=count;if(!s.count)s.item=0;
    ++revision;return result(true,"");
}
Dictionary NativePlayerInventory::apply_costs(const PackedInt64Array &costs,int64_t expected,bool commit) {
    if(expected!=revision)return result(false,"stale_revision");
    if(costs.is_empty()||costs.size()>64||costs.size()%2)return result(false,"invalid_costs");
    // At most 32 item/count pairs and 32 slots; stage all deductions before
    // publishing. Duplicate item rows consume cumulatively without overflow.
    auto candidate=slots;
    for(int64_t i=0;i<costs.size();i+=2){
        const int64_t item=costs[i];int64_t remaining=costs[i+1];
        if(limits.find(item)==limits.end()||remaining<=0||remaining>32000000)return result(false,"invalid_item_or_count");
        for(auto &slot:candidate){
            if(slot.item!=item)continue;
            const int64_t amount=std::min(remaining,slot.count);
            remaining-=amount;slot.count-=amount;if(!slot.count)slot.item=0;
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
    if(b.item&&b.item!=a.item){
        if(count!=a.count)return result(false,"partial_swap");
        std::swap(a,b);
    }else{
        if(count>limits.at(a.item)-b.count)return result(false,"stack_full");
        b.item=a.item;b.count+=count;a.count-=count;if(!a.count)a.item=0;
    }
    ++revision;return result(true,"");
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
        if((id==0&&n!=0)||(id!=0&&(limits.find(id)==limits.end()||n<=0||n>limits.at(id))))return result(false,"invalid_snapshot");
        candidate[i]={id,n};
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
    PackedByteArray data;data.resize(264);auto *p=data.ptrw();
    write_u32(p,0x31564654);write_u32(p+4,32); // TFV1, fixed slot count.
    for(int i=0;i<32;++i){write_u32(p+8+i*8,uint32_t(slots[i].item));write_u32(p+12+i*8,uint32_t(slots[i].count));}
    return data;
}
bool NativePlayerInventory::validate_snapshot(const PackedByteArray &data) const {
    // Worker-safe after catalog registration: never inspect mutable slots/revision.
    if(data.size()!=264)return false;
    const auto *p=data.ptr();
    if(read_u32(p)!=0x31564654||read_u32(p+4)!=32)return false;
    for(int i=0;i<32;++i){
        auto id=read_u32(p+8+i*8),n=read_u32(p+12+i*8);
        auto found=limits.find(id);
        if(id==0 ? n!=0 : found==limits.end()||n==0||n>found->second)return false;
    }
    return true;
}
bool NativePlayerInventory::restore_storage_snapshot(const PackedByteArray &data) {
    if(!validate_snapshot(data))return false;
    const auto *p=data.ptr();
    for(int i=0;i<32;++i)slots[i]={read_u32(p+8+i*8),read_u32(p+12+i*8)};
    ++revision;return true;
}
}
