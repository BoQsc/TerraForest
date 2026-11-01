// SPDX-License-Identifier: 0BSD
#include "zombie_population.hpp"
#include <godot_cpp/classes/hashing_context.hpp>
#include <climits>
#include <cstring>
#include <map>
#include <set>

namespace terraforest {
using namespace godot;
namespace {
constexpr uint32_t magic=0x50524654;
constexpr int header=32,stride=148,trailer=32,limit=256;
PackedByteArray digest(const PackedByteArray &bytes){
    Ref<HashingContext> hash;hash.instantiate();
    if(hash.is_null()||hash->start(HashingContext::HASH_SHA256)!=OK||hash->update(bytes.slice(0,bytes.size()-trailer))!=OK)return {};
    return hash->finish();
}
bool equal_point(const Vector3 &left,const Vector3 &right){
    for(int axis=0;axis<3;++axis)if(std::memcmp(&left[axis],&right[axis],sizeof(real_t)))return false;
    return true;
}
}
Dictionary NativeZombiePopulation::resident_patch_state()const{
    Dictionary result;result["revision"]=revision_;result["owner"]=int64_t(get_instance_id());result["seed"]=seed_;return result;
}
PackedByteArray NativeZombiePopulation::capture_resident_patch(const PackedInt64Array &ids,int64_t expected_revision,int64_t expected_owner)const{
    if(seed_<0||expected_revision!=revision_||uint64_t(expected_owner)!=get_instance_id()||ids.size()<1||ids.size()>limit)return {};
    std::set<int64_t> selected;
    for(int index=0;index<ids.size();++index){
        const int64_t identity=ids[index];
        if(identity<=2500||identity>int64_t(residents_.size())||!residents_[identity-1].anchor||!selected.insert(identity).second)return {};
    }
    PackedByteArray bytes;if(bytes.resize(header+stride*ids.size()+trailer)!=OK)return {};bytes.fill(0);
    bytes.encode_u32(0,magic);bytes.encode_u32(4,1);bytes.encode_u32(8,seed_);bytes.encode_u32(12,ids.size());
    for(int axis=0;axis<3;++axis)bytes.encode_float(16+axis*4,sanctuary_[axis]);
    int offset=header;
    for(auto identity:selected){
        const auto &record=residents_[identity-1];bytes.encode_s64(offset,identity);
        for(int axis=0;axis<3;++axis)bytes.encode_float(offset+8+axis*4,record.position[axis]);
        bytes.encode_float(offset+20,record.yaw);bytes.encode_u32(offset+24,record.state);bytes.encode_u32(offset+28,record.vitals.size());
        for(int index=0;index<record.vitals.size();++index)bytes.set(offset+32+index,record.vitals[index]);
        bytes.encode_u32(offset+92,record.sleep.size());
        for(int index=0;index<record.sleep.size();++index)bytes.set(offset+96+index,record.sleep[index]);
        bytes.encode_u64(offset+140,record.anchor);offset+=stride;
    }
    const auto checksum=digest(bytes);if(checksum.size()!=trailer)return {};
    std::memcpy(bytes.ptrw()+bytes.size()-trailer,checksum.ptr(),trailer);return bytes;
}
bool NativeZombiePopulation::decode_resident_patch(const PackedByteArray &bytes,std::vector<std::pair<int,Resident>> &selected)const{
    if(bytes.size()<header+stride+trailer||bytes.size()>header+limit*stride+trailer||bytes.decode_u32(0)!=magic||bytes.decode_u32(4)!=1||bytes.decode_u32(28)!=0)return false;
    const uint32_t count=bytes.decode_u32(12);
    if(count<1||count>limit||bytes.size()!=header+count*stride+trailer||seed_<0||bytes.decode_u32(8)!=uint32_t(seed_)||digest(bytes)!=bytes.slice(bytes.size()-trailer))return false;
    for(int axis=0;axis<3;++axis)if(bytes.decode_float(16+axis*4)!=sanctuary_[axis])return false;
    int64_t previous=2500;std::set<uint64_t> anchors;selected.reserve(count);
    for(uint32_t index=0;index<count;++index){
        const int offset=header+index*stride;const int64_t identity=bytes.decode_s64(offset);
        Resident record;record.state=bytes.decode_u32(offset+24);record.anchor=bytes.decode_u64(offset+140);
        if(identity<=previous||identity>2756||record.anchor<1||record.anchor>9007199254740991ULL||!anchors.insert(record.anchor).second||(record.state!=1&&record.state!=2)||bytes.decode_u32(offset+28)!=60)return false;
        previous=identity;
        for(int axis=0;axis<3;++axis)record.position[axis]=bytes.decode_float(offset+8+axis*4);
        record.yaw=bytes.decode_float(offset+20);
        if(!valid_position(record.position)||!std::isfinite(record.yaw)||std::abs(record.yaw)>10000)return false;
        record.vitals=bytes.slice(offset+32,offset+92);
        if(!valid_vitals(record.vitals)||((record.vitals.decode_float(0)==0)!=(record.state==2)))return false;
        const uint32_t length=bytes.decode_u32(offset+92);
        if(length!=0&&length!=44)return false;
        if(length){
            record.sleep=bytes.slice(offset+96,offset+140);
            if(record.state!=1||!valid_sleep_state(record.sleep))return false;
        }else for(int byte=0;byte<44;++byte)if(bytes[offset+96+byte])return false;
        selected.emplace_back(int(identity-1),std::move(record));
    }
    return true;
}
bool NativeZombiePopulation::validate_resident_patch(const PackedByteArray &bytes)const{
    std::vector<std::pair<int,Resident>> selected;return decode_resident_patch(bytes,selected);
}
Dictionary NativeZombiePopulation::restore_resident_patch(const PackedByteArray &bytes,int64_t expected_revision,int64_t expected_owner){
    Dictionary result;result["ok"]=false;result["changes"]=0;result["buckets"]=0;result["revision"]=revision_;result["reason"]="invalid_or_stale";
    if(expected_revision!=revision_||uint64_t(expected_owner)!=get_instance_id()||revision_==INT64_MAX)return result;
    std::vector<std::pair<int,Resident>> selected;if(!decode_resident_patch(bytes,selected))return result;
    std::vector<int> changed;std::map<int,std::vector<int>> buckets;
    for(int index=0;index<int(selected.size());++index){
        const auto &[identity,after]=selected[index];
        if(identity>=int(residents_.size())||residents_[identity].anchor!=after.anchor){result["reason"]="resident_identity_changed";return result;}
        const auto &before=residents_[identity];
        if(equal_point(before.position,after.position)&&std::memcmp(&before.yaw,&after.yaw,sizeof(float))==0&&before.state==after.state&&before.vitals==after.vitals&&before.sleep==after.sleep)continue;
        changed.push_back(index);
        if(before.state<2)buckets.try_emplace(cell(before.position),cells_[cell(before.position)]);
        if(after.state<2)buckets.try_emplace(cell(after.position),cells_[cell(after.position)]);
    }
    for(auto index:changed){
        const auto &[identity,after]=selected[index];const auto &before=residents_[identity];
        if(before.state<2){auto &bucket=buckets.at(cell(before.position));bucket.erase(std::remove(bucket.begin(),bucket.end(),identity),bucket.end());}
        if(after.state<2)buckets.at(cell(after.position)).push_back(identity);
    }
    for(auto index:changed){auto &[identity,after]=selected[index];residents_[identity]=std::move(after);}
    for(auto &[identity,bucket]:buckets)cells_[identity].swap(bucket);
    if(!changed.empty())++revision_;
    result["ok"]=true;result["changes"]=int64_t(changed.size());result["buckets"]=int64_t(buckets.size());result["revision"]=revision_;result["reason"]="";return result;
}
}
