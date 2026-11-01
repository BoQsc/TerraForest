// SPDX-License-Identifier: 0BSD
#include "containers.hpp"
#include <godot_cpp/classes/hashing_context.hpp>
#include <algorithm>
#include <climits>
#include <cstring>

namespace terraforest {
using namespace godot;
namespace {
constexpr int patch_header=24,patch_record=544,patch_digest_size=32,patch_count_limit=64;
constexpr uint32_t patch_magic=0x50434654;
PackedByteArray digest(const PackedByteArray &bytes){
    Ref<HashingContext> hash;hash.instantiate();
    if(hash.is_null()||hash->start(HashingContext::HASH_SHA256)!=OK||hash->update(bytes.slice(0,bytes.size()-patch_digest_size))!=OK)return {};
    return hash->finish();
}
bool nonempty(const PackedByteArray &inventory){
    for(int slot=0;slot<32;++slot)if(inventory.decode_u32(12+slot*16))return true;
    return false;
}
}
Dictionary NativeContainerStore::container_patch_state() const {
    Dictionary result;result["revision"]=revision;result["owner"]=int64_t(get_instance_id());return result;
}
PackedByteArray NativeContainerStore::capture_container_patch(const PackedInt64Array &ids,int64_t expected_revision,int64_t expected_owner) const {
    if(schema.is_null()||ids.is_empty()||ids.size()>patch_count_limit||expected_revision!=revision||expected_owner!=int64_t(get_instance_id()))return {};
    std::array<int64_t,patch_count_limit> ordered{};
    for(int index=0;index<ids.size();++index){if(ids[index]<=0)return {};ordered[index]=ids[index];}
    std::sort(ordered.begin(),ordered.begin()+ids.size());
    for(int index=1;index<ids.size();++index)if(ordered[index]==ordered[index-1])return {};
    PackedByteArray output;if(output.resize(patch_header+ids.size()*patch_record+patch_digest_size)!=OK)return {};
    output.fill(0);output.encode_u32(0,patch_magic);output.encode_u32(4,1);
    output.encode_u32(8,ids.size());output.encode_u32(12,slot_count);output.encode_u64(16,lockpick_item);
    for(int index=0;index<ids.size();++index){
        const int offset=patch_header+index*patch_record;const int64_t id=ordered[index];output.encode_u64(offset,id);
        const auto found=contents.find(id);
        const auto inventory=(found==contents.end()?schema:found->second)->capture_storage_snapshot();
        if(inventory.size()!=520)return {};
        std::memcpy(output.ptrw()+offset+8,inventory.ptr(),520);
        const auto lock=locks.find(id);
        if(lock!=locks.end()){
            output.encode_u32(offset+528,lock->second.remaining);output.encode_u32(offset+532,lock->second.maximum);output.encode_u64(offset+536,lock->second.random_state);
        }
    }
    const auto checksum=digest(output);if(checksum.size()!=patch_digest_size)return {};
    std::memcpy(output.ptrw()+output.size()-patch_digest_size,checksum.ptr(),patch_digest_size);return output;
}
bool NativeContainerStore::validate_container_patch(const PackedByteArray &bytes) const {
    if(schema.is_null()||bytes.size()<patch_header+patch_record+patch_digest_size||bytes.size()>patch_header+patch_count_limit*patch_record+patch_digest_size||
        bytes.decode_u32(0)!=patch_magic||bytes.decode_u32(4)!=1||bytes.decode_u32(12)!=uint32_t(slot_count)||bytes.decode_u64(16)!=uint64_t(lockpick_item))return false;
    const uint32_t count=bytes.decode_u32(8);
    if(count<1||count>patch_count_limit||bytes.size()!=patch_header+count*patch_record+patch_digest_size||digest(bytes)!=bytes.slice(bytes.size()-patch_digest_size))return false;
    uint64_t previous=0;
    for(uint32_t index=0;index<count;++index){
        const int offset=patch_header+index*patch_record;const uint64_t id=bytes.decode_u64(offset);
        if(id<=previous||id>uint64_t(INT64_MAX)||!schema->validate_snapshot(bytes.slice(offset+8,offset+528)))return false;
        previous=id;
        const uint32_t remaining=bytes.decode_u32(offset+528),maximum=bytes.decode_u32(offset+532);const uint64_t random=bytes.decode_u64(offset+536);
        if(remaining?(lockpick_item==0||!supports_locks()||remaining>maximum||maximum>1000000||random==0):(maximum!=0||random!=0))return false;
    }
    return true;
}
Dictionary NativeContainerStore::restore_container_patch(const PackedByteArray &bytes,int64_t expected_revision,int64_t expected_owner){
    Dictionary result;result["ok"]=false;result["changes"]=0;result["revision"]=revision;result["reason"]="invalid_or_stale";
    if(expected_revision!=revision||expected_owner!=int64_t(get_instance_id())||revision==INT64_MAX||!validate_container_patch(bytes))return result;
    const uint32_t count=bytes.decode_u32(8);
    decltype(contents) staged_contents;decltype(locks) staged_locks;
    std::array<int64_t,patch_count_limit> changed{};int changes=0;
    int64_t active=int64_t(contents.size())+lock_only_count,next_lock_only=lock_only_count;
    for(uint32_t index=0;index<count;++index){
        const int offset=patch_header+index*patch_record;const int64_t id=int64_t(bytes.decode_u64(offset));
        const auto inventory=bytes.slice(offset+8,offset+528);const bool has_inventory=nonempty(inventory);
        const uint32_t remaining=bytes.decode_u32(offset+528),maximum=bytes.decode_u32(offset+532);const uint64_t random=bytes.decode_u64(offset+536);
        const auto old_contents=contents.find(id);const auto old_lock=locks.find(id);
        const bool had_inventory=old_contents!=contents.end(),had_lock=old_lock!=locks.end();
        const bool same_inventory=has_inventory==had_inventory&&(!has_inventory||old_contents->second->capture_storage_snapshot()==inventory);
        const bool same_lock=bool(remaining)==had_lock&&(!remaining||(old_lock->second.remaining==remaining&&old_lock->second.maximum==maximum&&old_lock->second.random_state==random));
        if(same_inventory&&same_lock)continue;
        changed[changes++]=id;active-=had_inventory||had_lock;active+=has_inventory||remaining;
        next_lock_only-=had_lock&&!had_inventory;next_lock_only+=remaining&&!has_inventory;
        if(has_inventory){
            auto value=empty_inventory();if(value.is_null()||!value->restore_storage_snapshot(inventory))return result;
            value->slot_limit=visible_slots(value);value->revision=revision+1;staged_contents.emplace(id,value);
        }
        if(remaining)staged_locks.emplace(id,Lock{remaining,maximum,random,revision+1});
    }
    if(active>capacity){result["reason"]="container_capacity";return result;}
    if(changes){
        for(int index=0;index<changes;++index){contents.erase(changed[index]);locks.erase(changed[index]);}
        contents.merge(staged_contents);locks.merge(staged_locks);lock_only_count=next_lock_only;++revision;
    }
    result["ok"]=true;result["changes"]=changes;result["revision"]=revision;result["reason"]="";return result;
}
}
