// SPDX-License-Identifier: 0BSD
#include "durability.hpp"
#include <godot_cpp/classes/hashing_context.hpp>
#include <climits>
#include <cstring>
#include <vector>

namespace terraforest {
using namespace godot;
namespace {
constexpr uint32_t magic=0x50574654;
constexpr int header=16,trailer=32,limit=4096;
PackedByteArray digest(const PackedByteArray &bytes){
    Ref<HashingContext> hash;hash.instantiate();
    if(hash.is_null()||hash->start(HashingContext::HASH_SHA256)!=OK||hash->update(bytes.slice(0,bytes.size()-trailer))!=OK)return {};
    return hash->finish();
}
}
Dictionary NativeWorldDurability::damage_patch_state() const {
    Dictionary result;result["revision"]=revision;result["owner"]=int64_t(get_instance_id());return result;
}
PackedByteArray NativeWorldDurability::capture_damage_patch(const PackedStringArray &keys,int64_t expected_revision,int64_t expected_owner) const {
    if(expected_revision!=revision||expected_owner!=int64_t(get_instance_id())||keys.size()<1||keys.size()>limit)return {};
    std::map<std::string,Entry> selected;int size=header+trailer;
    for(int index=0;index<keys.size();++index){
        const auto raw=keys[index].utf8();const std::string key(raw.get_data(),raw.length());
        if(!valid_key(key))return {};
        auto found=damaged.find(key);if(!selected.emplace(key,found==damaged.end()?Entry{0,0}:found->second).second)return {};
        size+=12+key.size();
    }
    PackedByteArray bytes;if(bytes.resize(size)!=OK)return {};bytes.fill(0);
    bytes.encode_u32(0,magic);bytes.encode_u32(4,1);bytes.encode_u32(8,selected.size());int offset=header;
    for(const auto &entry:selected){
        bytes.encode_u32(offset,entry.first.size());bytes.encode_u32(offset+4,entry.second.health);bytes.encode_u32(offset+8,entry.second.damage);
        std::memcpy(bytes.ptrw()+offset+12,entry.first.data(),entry.first.size());offset+=12+entry.first.size();
    }
    const auto checksum=digest(bytes);if(checksum.size()!=trailer)return {};
    std::memcpy(bytes.ptrw()+size-trailer,checksum.ptr(),trailer);return bytes;
}
bool NativeWorldDurability::decode_damage_patch(const PackedByteArray &bytes,std::map<std::string,Entry> &selected){
    if(bytes.size()<header+13+trailer||bytes.size()>header+limit*172+trailer||bytes.decode_u32(0)!=magic||bytes.decode_u32(4)!=1||bytes.decode_u32(12)!=0)return false;
    const uint32_t count=bytes.decode_u32(8);
    if(count<1||count>limit||digest(bytes)!=bytes.slice(bytes.size()-trailer))return false;
    int offset=header;std::string previous;
    for(uint32_t index=0;index<count;++index){
        if(offset+12>bytes.size()-trailer)return false;
        const uint32_t length=bytes.decode_u32(offset),maximum=bytes.decode_u32(offset+4),amount=bytes.decode_u32(offset+8);
        if(length<1||length>160||offset+12+length>uint64_t(bytes.size()-trailer)||maximum>1000000||amount>maximum||(maximum>0&&amount==0))return false;
        const std::string key(reinterpret_cast<const char *>(bytes.ptr()+offset+12),length);
        if(!valid_key(key)||key<=previous)return false;previous=key;
        selected.emplace(key,Entry{int(maximum),int(amount)});offset+=12+length;
    }
    return offset==bytes.size()-trailer;
}
bool NativeWorldDurability::validate_damage_patch(const PackedByteArray &bytes) const {
    decltype(damaged) selected;return decode_damage_patch(bytes,selected);
}
Dictionary NativeWorldDurability::restore_damage_patch(const PackedByteArray &bytes,int64_t expected_revision,int64_t expected_owner){
    Dictionary result;result["ok"]=false;result["changes"]=0;result["revision"]=revision;result["reason"]="invalid_or_stale";
    if(expected_revision!=revision||expected_owner!=int64_t(get_instance_id())||revision==INT64_MAX)return result;
    decltype(damaged) selected;if(!decode_damage_patch(bytes,selected))return result;
    std::vector<std::string> changed;int64_t count=damaged.size();
    for(auto entry=selected.begin();entry!=selected.end();){
        const auto found=damaged.find(entry->first);const bool had=found!=damaged.end(),has=entry->second.health>0;
        if(had==has&&(!has||(found->second.health==entry->second.health&&found->second.damage==entry->second.damage))){entry=selected.erase(entry);continue;}
        changed.push_back(entry->first);count+=int(has)-int(had);
        if(!has)entry=selected.erase(entry);else ++entry;
    }
    if(count>65536){result["reason"]="capacity";return result;}
    if(!changed.empty()){
        for(const auto &key:changed)damaged.erase(key);
        damaged.merge(selected);++revision;
    }
    result["ok"]=true;result["changes"]=int64_t(changed.size());result["revision"]=revision;result["reason"]="";return result;
}
}
