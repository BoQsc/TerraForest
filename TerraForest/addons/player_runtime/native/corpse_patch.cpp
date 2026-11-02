// SPDX-License-Identifier: 0BSD
#include "corpses.hpp"
#include <godot_cpp/classes/hashing_context.hpp>
#include <climits>
#include <cstring>
#include <set>

namespace terraforest {
using namespace godot;
namespace {
constexpr uint32_t magic=0x505a4654;
constexpr int header=24,stride=1288,trailer=32,limit=64;
PackedByteArray digest(const PackedByteArray &bytes){
    Ref<HashingContext> hash;hash.instantiate();
    if(hash.is_null()||hash->start(HashingContext::HASH_SHA256)!=OK||hash->update(bytes.slice(0,bytes.size()-trailer))!=OK)return {};
    return hash->finish();
}
bool nonempty(const PackedByteArray &bytes){for(int slot=0;slot<32;++slot)if(bytes.decode_u32(12+slot*16))return true;return false;}
}
Dictionary NativeCorpseStore::corpse_patch_state()const{
    Dictionary result;result["revision"]=revision;result["owner"]=int64_t(get_instance_id());return result;
}
PackedByteArray NativeCorpseStore::capture_corpse_patch(const PackedInt64Array &residents,const PackedInt64Array &anchors,int64_t expected_revision,int64_t expected_owner)const{
    if(schema.is_null()||residents.is_empty()||residents.size()>limit||residents.size()!=anchors.size()||expected_revision!=revision||expected_owner!=int64_t(get_instance_id()))return {};
    std::map<int64_t,int64_t> selected;std::set<int64_t> keys;
    for(int index=0;index<residents.size();++index)if(anchors[index]<=0||!valid_owner(residents[index],anchors[index])||!selected.emplace(residents[index],anchors[index]).second||!keys.insert(anchors[index]).second)return {};
    PackedByteArray bytes;if(bytes.resize(header+stride*selected.size()+trailer)!=OK)return {};bytes.fill(0);
    bytes.encode_u32(0,magic);bytes.encode_u32(4,1);bytes.encode_u32(8,selected.size());bytes.encode_u32(12,slot_count);
    int offset=header;
    for(const auto &[resident,anchor]:selected){
        bytes.encode_u64(offset,resident);bytes.encode_u64(offset+8,anchor);
        auto found=resident_corpses.find(resident);
        if(found==resident_corpses.end()){if(anchor_corpses.count(anchor))return {};offset+=stride;continue;}
        const auto &corpse=records.at(found->second);if(corpse.anchor!=anchor)return {};
        bytes.encode_u64(offset+16,found->second);
        for(int axis=0;axis<3;++axis)bytes.encode_float(offset+24+axis*4,corpse.position[axis]);
        bytes.encode_float(offset+36,corpse.yaw);bytes.encode_u32(offset+40,corpse.missing);bytes.encode_u32(offset+44,corpse.pose.is_empty()?0:1);
        for(int index=0;index<corpse.pose.size();++index)bytes.encode_float(offset+48+index*4,corpse.pose[index]);
        auto inventory=contents.find(found->second);const auto snapshot=(inventory==contents.end()?schema:inventory->second)->capture_storage_snapshot();
        if(snapshot.size()!=520)return {};std::memcpy(bytes.ptrw()+offset+768,snapshot.ptr(),520);offset+=stride;
    }
    const auto checksum=digest(bytes);if(checksum.size()!=trailer)return {};std::memcpy(bytes.ptrw()+bytes.size()-trailer,checksum.ptr(),trailer);return bytes;
}
bool NativeCorpseStore::decode_corpse_patch(const PackedByteArray &bytes,std::vector<PatchEntry> &selected)const{
    if(schema.is_null()||bytes.size()<header+stride+trailer||bytes.size()>header+limit*stride+trailer||bytes.decode_u32(0)!=magic||bytes.decode_u32(4)!=1||bytes.decode_u32(12)!=uint32_t(slot_count)||bytes.decode_u64(16)!=0)return false;
    const uint32_t count=bytes.decode_u32(8);if(count<1||count>limit||bytes.size()!=header+count*stride+trailer||digest(bytes)!=bytes.slice(bytes.size()-trailer))return false;
    int64_t previous=0;std::set<int64_t> keys,ids;selected.reserve(count);
    for(uint32_t index=0;index<count;++index){
        const int offset=header+index*stride;PatchEntry entry;entry.resident=bytes.decode_u64(offset);entry.anchor=bytes.decode_u64(offset+8);entry.id=bytes.decode_u64(offset+16);
        if(entry.resident<=previous||entry.anchor<=0||!valid_owner(entry.resident,entry.anchor)||!keys.insert(entry.anchor).second||entry.id<0||entry.id==INT64_MAX||(entry.id&&!ids.insert(entry.id).second))return false;
        previous=entry.resident;
        if(!entry.id){for(int byte=24;byte<stride;++byte)if(bytes[offset+byte])return false;selected.push_back(std::move(entry));continue;}
        auto &corpse=entry.corpse;corpse.resident=entry.resident;corpse.anchor=entry.anchor;
        for(int axis=0;axis<3;++axis)corpse.position[axis]=bytes.decode_float(offset+24+axis*4);
        corpse.yaw=bytes.decode_float(offset+36);corpse.missing=bytes.decode_u32(offset+40);const uint32_t posed=bytes.decode_u32(offset+44);
        if(!corpse.position.is_finite()||corpse.position.length_squared()>1e12||!std::isfinite(corpse.yaw)||corpse.missing>16383||posed>1)return false;
        if(posed){corpse.pose.resize(180);for(int item=0;item<180;++item)corpse.pose.set(item,bytes.decode_float(offset+48+item*4));if(!valid_pose(corpse.pose))return false;}
        else for(int byte=0;byte<720;++byte)if(bytes[offset+48+byte])return false;
        entry.inventory=bytes.slice(offset+768,offset+stride);if(!schema->validate_snapshot(entry.inventory))return false;selected.push_back(std::move(entry));
    }
    return true;
}
bool NativeCorpseStore::validate_corpse_patch(const PackedByteArray &bytes)const{std::vector<PatchEntry> selected;return decode_corpse_patch(bytes,selected);}
Dictionary NativeCorpseStore::restore_corpse_patch(const PackedByteArray &bytes,int64_t expected_revision,int64_t expected_owner){
    Dictionary result;result["ok"]=false;result["changes"]=0;result["revision"]=revision;result["reason"]="invalid_or_stale";
    if(expected_revision!=revision||expected_owner!=int64_t(get_instance_id())||revision==INT64_MAX)return result;
    std::vector<PatchEntry> selected;if(!decode_corpse_patch(bytes,selected))return result;
    decltype(records) staged_records;decltype(contents) staged_contents;decltype(resident_corpses) staged_owners,staged_anchors;
    std::set<int64_t> removed,changed;int64_t record_count=records.size(),content_count=contents.size(),next=next_id;
    for(const auto &entry:selected){
        const auto owner=resident_corpses.find(entry.resident);const int64_t before_id=owner==resident_corpses.end()?0:owner->second;
        if(before_id&&records.at(before_id).anchor!=entry.anchor){result["reason"]="resident_identity_changed";return result;}
        const auto anchor=anchor_corpses.find(entry.anchor);
        if(anchor!=anchor_corpses.end()&&anchor->second!=before_id){result["reason"]="anchor_owned_elsewhere";return result;}
        if(entry.id!=before_id&&(records.count(entry.id)||contents.count(entry.id))){result["reason"]="corpse_identity_owned_elsewhere";return result;}
        bool same=before_id==entry.id;
        if(same&&entry.id){
            const auto &before=records.at(before_id),&after=entry.corpse;
            same=std::memcmp(&before.yaw,&after.yaw,sizeof(float))==0&&before.missing==after.missing&&before.pose.size()==after.pose.size()&&(before.pose.is_empty()||std::memcmp(before.pose.ptr(),after.pose.ptr(),before.pose.size()*sizeof(float))==0);
            for(int axis=0;axis<3;++axis)same=same&&std::memcmp(&before.position[axis],&after.position[axis],sizeof(real_t))==0;
            auto inventory=contents.find(before_id);same=same&&(inventory==contents.end()?schema:inventory->second)->capture_storage_snapshot()==entry.inventory;
        }
        if(same)continue;
        changed.insert(entry.resident);
        if(before_id){removed.insert(before_id);--record_count;content_count-=contents.count(before_id);}
        if(entry.id){
            ++record_count;next=std::max(next,entry.id+1);staged_records.emplace(entry.id,entry.corpse);staged_owners.emplace(entry.resident,entry.id);staged_anchors.emplace(entry.anchor,entry.id);
            if(nonempty(entry.inventory)){auto inventory=staged_inventory(entry.inventory,revision+1);if(inventory.is_null())return result;staged_contents.emplace(entry.id,inventory);++content_count;}
        }
    }
    if(record_count>capacity||content_count>capacity){result["reason"]="corpse_capacity";return result;}
    for(auto identity:removed){const auto &corpse=records.at(identity);resident_corpses.erase(corpse.resident);anchor_corpses.erase(corpse.anchor);records.erase(identity);contents.erase(identity);}
    records.merge(staged_records);contents.merge(staged_contents);resident_corpses.merge(staged_owners);anchor_corpses.merge(staged_anchors);next_id=next;
    if(!changed.empty())++revision;
    result["ok"]=true;result["changes"]=int64_t(changed.size());result["revision"]=revision;result["reason"]="";return result;
}
}
