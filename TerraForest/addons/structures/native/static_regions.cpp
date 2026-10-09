// SPDX-License-Identifier: 0BSD
#include "static_batch.hpp"
#include <godot_cpp/classes/hashing_context.hpp>
#include <cstring>

namespace terraforest {
static PackedByteArray region_digest(const PackedByteArray &bytes) {
    Ref<HashingContext> hash;hash.instantiate();hash->start(HashingContext::HASH_SHA256);
    hash->update(bytes);return hash->finish();
}
bool NativeStaticBatch::valid_model_region(BlockKey key) {
    for(int axis:{key.x,key.y,key.z})if(axis<-32768||axis>=32768)return false;
    return true;
}
bool NativeStaticBatch::is_region_loaded(Vector3i position) const {
    BlockKey key{position.x,position.y,position.z};
    return valid_model_region(key)&&!unloaded_regions.count(key);
}
PackedByteArray NativeStaticBatch::capture_region(Vector3i position) const {
    BlockKey key{position.x,position.y,position.z};
    if(!valid_model_region(key)||!valid_asset(asset_id)||unloaded_regions.count(key))return {};
    // One lookup plus this region's ordered IDs: never scan all placements.
    std::map<int64_t,Placement> selected;
    auto group=groups.find(key);
    if(group!=groups.end())for(auto id:group->second)selected.emplace(id,placements.at(id));
    PackedByteArray payload=encode_placements(asset_id,selected),out;out.resize(24);
    std::memcpy(out.ptrw(),"TFMR\1\0\0\0",8);
    out.encode_s32(8,key.x);out.encode_s32(12,key.y);out.encode_s32(16,key.z);
    out.encode_u32(20,payload.size());out.append_array(payload);
    out.append_array(region_digest(out));return out;
}
bool NativeStaticBatch::parse_region(const PackedByteArray &bytes,String &asset,BlockKey &key,std::map<int64_t,Placement> &values) {
    if(bytes.size()<105||bytes.size()>5600232||std::memcmp(bytes.ptr(),"TFMR\1\0\0\0",8))return false;
    if(bytes.decode_u32(20)!=uint64_t(bytes.size()-56))return false;
    if(region_digest(bytes.slice(0,bytes.size()-32))!=bytes.slice(bytes.size()-32))return false;
    key={int(bytes.decode_s32(8)),int(bytes.decode_s32(12)),int(bytes.decode_s32(16))};
    if(!valid_model_region(key)||!parse(bytes.slice(24,bytes.size()-32),asset,&values))return false;
    for(const auto &entry:values) {
        auto actual=group_for(entry.second);
        if(actual<key||key<actual)return false;
    }
    return true;
}
bool NativeStaticBatch::validate_region_snapshot(const PackedByteArray &bytes) const {
    BlockKey key;String asset;std::map<int64_t,Placement> values;
    return parse_region(bytes,asset,key,values)&&asset==asset_id;
}
bool NativeStaticBatch::unload_region(const PackedByteArray &expected) {
    if(defer_change_signal)return false; // Never enter during a journal mutation.
    BlockKey key;String asset;std::map<int64_t,Placement> values;
    if(!parse_region(expected,asset,key,values)||asset!=asset_id||unloaded_regions.count(key)||
       groups.size()+unloaded_regions.size()+(groups.count(key)?0:1)>4096||
       capture_region(Vector3i(key.x,key.y,key.z))!=expected)return false;
    UnloadedRegion metadata;metadata.checksum=expected.slice(expected.size()-32);metadata.count=values.size();
    if(!values.empty())metadata.bounds=collision_bounds.at(key);
    // Publish unavailable metadata, reservations and record removal together,
    // before observers can query readiness or attempt new authoring.
    unloaded_regions.emplace(key,metadata);
    for(const auto &entry:values) {
        unloaded_ids.insert(entry.first);invalidate_proxy(entry.first);
        placements.erase(entry.first);slots.erase(entry.first);
    }
    groups.erase(key);rebuild({key});publish_change();return true;
}
bool NativeStaticBatch::restore_region(const PackedByteArray &bytes) {
    if(defer_change_signal||source_mesh.is_null())return false;
    BlockKey key;String asset;std::map<int64_t,Placement> values;
    if(!parse_region(bytes,asset,key,values)||asset!=asset_id)return false;
    auto missing=unloaded_regions.find(key);
    if(missing==unloaded_regions.end()||missing->second.checksum!=bytes.slice(bytes.size()-32)||
       missing->second.count!=values.size()||groups.count(key))return false;
    for(const auto &entry:values)if(placements.count(entry.first)||!unloaded_ids.count(entry.first))return false;
    for(auto &entry:values) {
        unloaded_ids.erase(entry.first);groups[key].insert(entry.first);
        placements.emplace(entry.first,std::move(entry.second));
    }
    unloaded_regions.erase(missing);rebuild({key});publish_change();return true;
}
Dictionary NativeStaticBatch::region_stats() const {
    Dictionary out;out["region_edge_m"]=32;out["resident_regions"]=int(groups.size());
    out["unloaded_regions"]=int(unloaded_regions.size());out["resident_instances"]=int(placements.size());
    out["reserved_ids"]=int(unloaded_ids.size());out["logical_instances"]=int(placements.size()+unloaded_ids.size());
    out["resident_transform_bytes"]=int64_t(placements.size()*sizeof(Placement));
    out["reserved_id_payload_bytes"]=int64_t(unloaded_ids.size()*sizeof(int64_t));
    out["unloaded_digest_bytes"]=int64_t(unloaded_regions.size()*32);
    return out;
}
Dictionary NativeStaticBatch::capture_storage_state() const {
    PackedInt32Array keys;PackedByteArray checksums;
    keys.resize(unloaded_regions.size()*3);checksums.resize(unloaded_regions.size()*32);
    int64_t index=0;
    for(const auto &entry:unloaded_regions) {
        keys.set(index*3,entry.first.x);keys.set(index*3+1,entry.first.y);keys.set(index*3+2,entry.first.z);
        std::memcpy(checksums.ptrw()+index*32,entry.second.checksum.ptr(),32);++index;
    }
    Dictionary out;out["resident"]=encode_placements(asset_id,placements);
    out["unavailable_keys"]=keys;out["unavailable_checksums"]=checksums;return out;
}
}
