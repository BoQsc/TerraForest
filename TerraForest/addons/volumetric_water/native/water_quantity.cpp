// SPDX-License-Identifier: 0BSD
#include "water_quantity.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <limits>
using namespace godot;
namespace terraforest {
void NativeWaterQuantity::_bind_methods() {
    ClassDB::bind_method(D_METHOD("create","capacity_ml","initial_ml","expected"),&NativeWaterQuantity::create);
    ClassDB::bind_method(D_METHOD("remove_empty","id","expected"),&NativeWaterQuantity::remove_empty);
    ClassDB::bind_method(D_METHOD("transfer","source","destination","amount_ml","expected"),&NativeWaterQuantity::transfer);
    ClassDB::bind_method(D_METHOD("inspect","id"),&NativeWaterQuantity::inspect);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterQuantity::statistics);
    ClassDB::bind_method(D_METHOD("capture_snapshot"),&NativeWaterQuantity::capture_snapshot);
    ClassDB::bind_method(D_METHOD("restore_snapshot","bytes"),&NativeWaterQuantity::restore_snapshot);
}
Dictionary NativeWaterQuantity::result(bool ok,const char *reason,int64_t moved) const {
    Dictionary out;out["ok"]=ok;out["reason"]=reason;out["revision"]=revision;out["moved_ml"]=moved;return out;
}
Dictionary NativeWaterQuantity::create(int64_t capacity,int64_t amount,int64_t expected) {
    if(expected!=revision)return result(false,"stale_revision");
    if(revision==limit||next_id==limit)return result(false,"identity_limit");
    if(records.size()>=max_records)return result(false,"record_limit");
    if(capacity<1||capacity>limit||amount<0||amount>capacity||amount>limit-total)return result(false,"invalid_quantity");
    const int64_t id=next_id++;
    records.emplace(id,Record{amount,capacity});total+=amount;++revision;
    Dictionary out=result(true,"created");out["id"]=id;return out;
}
Dictionary NativeWaterQuantity::remove_empty(int64_t id,int64_t expected) {
    if(expected!=revision)return result(false,"stale_revision");
    if(revision==limit)return result(false,"revision_limit");
    const auto entry=records.find(id);
    if(entry==records.end())return result(false,"missing_record");
    if(entry->second.amount)return result(false,"contains_water");
    records.erase(entry);++revision;return result(true,"removed");
}
Dictionary NativeWaterQuantity::transfer(int64_t source,int64_t destination,int64_t amount,int64_t expected) {
    if(expected!=revision)return result(false,"stale_revision");
    if(revision==limit)return result(false,"revision_limit");
    if(source==destination||amount<1||amount>limit)return result(false,"invalid_transfer");
    auto from=records.find(source),to=records.find(destination);
    if(from==records.end()||to==records.end())return result(false,"missing_record");
    if(from->second.amount<amount)return result(false,"insufficient_water");
    if(to->second.capacity-to->second.amount<amount)return result(false,"insufficient_capacity");
    // Commit both sides after all checks. No partial transfer or hidden spill.
    from->second.amount-=amount;to->second.amount+=amount;++revision;
    return result(true,"transferred",amount);
}
Dictionary NativeWaterQuantity::inspect(int64_t id) const {
    const auto entry=records.find(id);Dictionary out=result(entry!=records.end(),entry!=records.end()?"found":"missing_record");
    if(entry!=records.end()){out["id"]=id;out["amount_ml"]=entry->second.amount;out["capacity_ml"]=entry->second.capacity;}return out;
}
Dictionary NativeWaterQuantity::statistics() const {
    Dictionary out;out["records"]=int64_t(records.size());out["record_limit"]=int64_t(max_records);
    out["total_ml"]=total;out["revision"]=revision;out["next_id"]=next_id;return out;
}
static uint32_t quantity_checksum(const PackedByteArray &bytes) {
    uint32_t hash=2166136261u;
    for(int64_t i=16;i<bytes.size();++i)hash=(hash^bytes[i])*16777619u;
    return hash;
}
PackedByteArray NativeWaterQuantity::capture_snapshot() const {
    PackedByteArray bytes;bytes.resize(48+records.size()*24);bytes.fill(0);
    bytes.encode_u32(0,0x31515754);bytes.encode_u32(4,1);bytes.encode_u32(8,bytes.size());
    bytes.encode_u64(16,revision);bytes.encode_u64(24,next_id);bytes.encode_u64(32,total);bytes.encode_u32(40,records.size());
    int64_t at=48;
    for(const auto &entry:records){bytes.encode_u64(at,entry.first);bytes.encode_u64(at+8,entry.second.amount);bytes.encode_u64(at+16,entry.second.capacity);at+=24;}
    bytes.encode_u32(12,quantity_checksum(bytes));return bytes;
}
bool NativeWaterQuantity::restore_snapshot(const PackedByteArray &bytes) {
    // Restore only into a fresh store, preventing replay from rolling back live commands.
    if(revision||next_id!=1||!records.empty()||bytes.size()<48||bytes.size()>48+max_records*24)return false;
    if(bytes.decode_u32(0)!=0x31515754||bytes.decode_u32(4)!=1||bytes.decode_u32(8)!=uint64_t(bytes.size())||bytes.decode_u32(12)!=quantity_checksum(bytes)||bytes.decode_u32(44))return false;
    const uint64_t saved_revision=bytes.decode_u64(16),saved_next=bytes.decode_u64(24),saved_total=bytes.decode_u64(32),count=bytes.decode_u32(40);
    if(saved_revision>limit||saved_next<1||saved_next>limit||saved_total>limit||count>max_records||bytes.size()!=48+count*24||saved_revision<saved_next-1)return false;
    std::map<int64_t,Record> staged;uint64_t sum=0,previous=0;
    for(uint64_t i=0;i<count;++i){
        const int64_t at=48+i*24;const uint64_t id=bytes.decode_u64(at),amount=bytes.decode_u64(at+8),capacity=bytes.decode_u64(at+16);
        if(id<=previous||id>=saved_next||capacity<1||capacity>limit||amount>capacity||amount>uint64_t(limit)-sum)return false;
        staged.emplace(int64_t(id),Record{int64_t(amount),int64_t(capacity)});sum+=amount;previous=id;
    }
    if(sum!=saved_total)return false;
    records.swap(staged);revision=saved_revision;next_id=saved_next;total=sum;return true;
}
}
