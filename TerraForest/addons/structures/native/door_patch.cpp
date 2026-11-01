// SPDX-License-Identifier: 0BSD
#include "hinged_doors.hpp"
#include <climits>
#include <cmath>
#include <cstring>

namespace terraforest {
using namespace godot;
namespace {
constexpr uint32_t magic=0x50444654;
constexpr int header=88,record=120,trailer=32,limit=256;
PackedByteArray digest(const PackedByteArray &bytes){
    Ref<HashingContext> hash;hash.instantiate();
    if(hash.is_null()||hash->start(HashingContext::HASH_SHA256)!=OK||hash->update(bytes.slice(0,bytes.size()-trailer))!=OK)return {};
    return hash->finish();
}
bool pose(const PackedByteArray &bytes,int offset,PackedFloat32Array &values){
    if(values.resize(12)!=OK)return false;
    for(int index=0;index<12;++index){const float value=bytes.decode_float(offset+index*4);if(!std::isfinite(value)||std::abs(value)>1048575)return false;values.set(index,value);}
    return std::abs(Basis(values[0],values[1],values[2],values[4],values[5],values[6],values[8],values[9],values[10]).determinant())>=1e-9;
}
bool equal_pose(const PackedFloat32Array &left,const PackedFloat32Array &right){
    return left.size()==right.size()&&(!left.size()||std::memcmp(left.ptr(),right.ptr(),left.size()*sizeof(float))==0);
}
}
Dictionary NativeHingedDoors::door_patch_state() const {
    Dictionary result;result["revision"]=int64_t(revision);result["owner"]=int64_t(get_instance_id());result["busy"]=state_busy;return result;
}
PackedByteArray NativeHingedDoors::capture_door_patch(const PackedInt64Array &ids,int64_t expected_revision,int64_t expected_owner) const {
    if(state_busy||expected_revision<0||uint64_t(expected_revision)!=revision||uint64_t(expected_owner)!=get_instance_id()||ids.size()<1||ids.size()>limit)return {};
    std::set<int64_t> selected;for(int index=0;index<ids.size();++index)if(ids[index]<=0||!selected.insert(ids[index]).second)return {};
    PackedByteArray bytes;if(bytes.resize(header+ids.size()*record+trailer)!=OK)return {};bytes.fill(0);
    bytes.encode_u32(0,magic);bytes.encode_u32(4,1);bytes.encode_u32(8,ids.size());bytes.encode_u32(12,curve_signature.size());
    for(int axis=0;axis<3;++axis){bytes.encode_float(16+axis*4,leaf.position[axis]);bytes.encode_float(28+axis*4,leaf.size[axis]);bytes.encode_float(40+axis*4,pivot[axis]);}
    bytes.encode_float(52,opening_degrees);for(int index=0;index<curve_signature.size();++index)bytes.set(56+index,curve_signature[index]);
    int offset=header;
    for(auto id:selected){
        bytes.encode_s64(offset,id);auto closed=opened.find(id);auto moving=motions.find(id);
        if(closed!=opened.end()){
            uint32_t flags=1;for(int index=0;index<12;++index)bytes.encode_float(offset+16+index*4,closed->second[index]);
            if(moving!=motions.end()){
                flags|=2|(moving->second.target?4:0)|(moving->second.blocked?8:0);
                for(int index=0;index<12;++index)bytes.encode_float(offset+64+index*4,moving->second.last[index]);
                bytes.encode_double(offset+112,moving->second.elapsed);
            }
            bytes.encode_u32(offset+8,flags);
        }
        offset+=record;
    }
    const auto checksum=digest(bytes);if(checksum.size()!=trailer)return {};
    std::memcpy(bytes.ptrw()+bytes.size()-trailer,checksum.ptr(),trailer);return bytes;
}
bool NativeHingedDoors::decode_door_patch(const PackedByteArray &bytes,std::vector<int64_t> &ids,std::map<int64_t,PackedFloat32Array> &selected,std::map<int64_t,Motion> &moving) const {
    if(bytes.size()<header+record+trailer||bytes.size()>header+limit*record+trailer||bytes.decode_u32(0)!=magic||bytes.decode_u32(4)!=1)return false;
    const uint32_t count=bytes.decode_u32(8);
    if(count<1||count>limit||bytes.size()!=header+count*record+trailer||bytes.decode_u32(12)!=uint32_t(curve_signature.size())||digest(bytes)!=bytes.slice(bytes.size()-trailer))return false;
    for(int axis=0;axis<3;++axis)if(bytes.decode_float(16+axis*4)!=leaf.position[axis]||bytes.decode_float(28+axis*4)!=leaf.size[axis]||bytes.decode_float(40+axis*4)!=pivot[axis])return false;
    if(bytes.decode_float(52)!=float(opening_degrees))return false;
    for(int index=0;index<32;++index)if(bytes[56+index]!=(curve_signature.is_empty()?0:curve_signature[index]))return false;
    int64_t previous=0;
    for(uint32_t index=0;index<count;++index){
        const int offset=header+index*record;const int64_t id=bytes.decode_s64(offset);const uint32_t flags=bytes.decode_u32(offset+8);
        if(id<=previous||flags>15||bytes.decode_u32(offset+12)!=0||(!(flags&1)&&flags)||(!(flags&2)&&(flags&12)))return false;
        previous=id;ids.push_back(id);
        if(!(flags&1)){for(int at=16;at<record;++at)if(bytes[offset+at])return false;continue;}
        PackedFloat32Array closed;if(!pose(bytes,offset+16,closed))return false;selected.emplace(id,closed);
        if(!(flags&2)){for(int at=64;at<record;++at)if(bytes[offset+at])return false;continue;}
        if(curve_signature.is_empty()||moving.size()>=32)return false;
        Motion motion;motion.target=flags&4;motion.blocked=flags&8;motion.elapsed=bytes.decode_double(offset+112);
        const auto &curve=motion.target?opening_curve:closing_curve;
        if(!std::isfinite(motion.elapsed)||motion.elapsed<0||motion.elapsed>=curve[curve.size()-2]||!pose(bytes,offset+64,motion.last)||!equal_pose(pose_at(closed,fraction(motion)),motion.last))return false;
        moving.emplace(id,motion);
    }
    return true;
}
bool NativeHingedDoors::validate_door_patch(const PackedByteArray &bytes) const {
    std::vector<int64_t> ids;decltype(opened) selected;decltype(motions) moving;return decode_door_patch(bytes,ids,selected,moving);
}
Dictionary NativeHingedDoors::restore_door_patch(const PackedByteArray &bytes,int64_t expected_revision,int64_t expected_owner){
    Dictionary result;result["ok"]=false;result["changes"]=0;result["revision"]=int64_t(revision);result["reason"]="invalid_or_stale";
    if(state_busy||expected_revision<0||uint64_t(expected_revision)!=revision||uint64_t(expected_owner)!=get_instance_id()||revision>=uint64_t(INT64_MAX))return result;
    std::vector<int64_t> ids;decltype(opened) selected;decltype(motions) moving;
    if(!decode_door_patch(bytes,ids,selected,moving))return result;
    std::vector<int64_t> changed;int64_t next_open=opened.size(),next_moving=motions.size();
    for(auto id:ids){
        const auto before=opened.find(id),after=selected.find(id);const auto motion_before=motions.find(id),motion_after=moving.find(id);
        const bool had=before!=opened.end(),has=after!=selected.end(),was_moving=motion_before!=motions.end(),is_moving=motion_after!=moving.end();
        const bool same_pose=had==has&&(!had||equal_pose(before->second,after->second));
        const bool same_motion=was_moving==is_moving&&(!was_moving||(motion_before->second.elapsed==motion_after->second.elapsed&&motion_before->second.target==motion_after->second.target&&motion_before->second.blocked==motion_after->second.blocked&&equal_pose(motion_before->second.last,motion_after->second.last)));
        if(same_pose&&same_motion){selected.erase(id);moving.erase(id);continue;}
        changed.push_back(id);next_open+=int(has)-int(had);next_moving+=int(is_moving)-int(was_moving);
    }
    if(next_open>65536||next_moving>32){result["reason"]="capacity";return result;}
    if(!changed.empty()){
        for(auto id:changed){opened.erase(id);motions.erase(id);}
        opened.merge(selected);motions.merge(moving);++revision;
    }
    result["ok"]=true;result["changes"]=int64_t(changed.size());result["revision"]=int64_t(revision);result["reason"]="";return result;
}
}
