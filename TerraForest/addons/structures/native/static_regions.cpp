// SPDX-License-Identifier: 0BSD
#include "static_batch.hpp"
#include <godot_cpp/classes/hashing_context.hpp>
#include <cstring>
#include <cmath>
#include <limits>

namespace terraforest {
static PackedByteArray region_digest(const PackedByteArray &bytes) {
    Ref<HashingContext> hash;hash.instantiate();hash->start(HashingContext::HASH_SHA256);
    hash->update(bytes);return hash->finish();
}
// TFMD v1: asset length, region count, checkpoint, asset; sorted regions each
// contain xyz, packet digest, ID count, absolute basis maxima (row-major), IDs.
// Translation lies inside the origin region. This bounds any registered mesh
// or proxy without storing the transforms or baking prototype-specific bounds.
bool NativeStaticBatch::parse_metadata(const PackedByteArray &bytes,String &asset,PackedByteArray &checkpoint,std::map<BlockKey,MetadataRegion> &regions,std::set<int64_t> &ids) {
    if(bytes.size()<81||bytes.size()>1144272||std::memcmp(bytes.ptr(),"TFMD\1\0\0\0",8))return false;
    const int64_t end=bytes.size()-32,length=bytes.decode_u32(8),count=bytes.decode_u32(12);
    if(length<1||length>128||count>4096||48+length>end||region_digest(bytes.slice(0,end))!=bytes.slice(end))return false;
    for(int64_t i=0;i<length;++i)if(bytes[48+i]<33||bytes[48+i]>126)return false;
    asset=String::utf8(reinterpret_cast<const char*>(bytes.ptr()+48),length);checkpoint=bytes.slice(16,48);
    int64_t at=48+length;BlockKey previous;
    for(int64_t i=0;i<count;++i) {
        if(end-at<84)return false;
        BlockKey key{int(bytes.decode_s32(at)),int(bytes.decode_s32(at+4)),int(bytes.decode_s32(at+8))};
        const int64_t n=bytes.decode_u32(at+44);
        if(!valid_model_region(key)||(i&&!(previous<key))||n>100000-int64_t(ids.size())||n*8>end-at-84)return false;
        MetadataRegion entry;entry.checksum=bytes.slice(at+12,at+44);
        for(int j=0;j<9;++j){float value=bytes.decode_float(at+48+j*4);if(!std::isfinite(value)||value<0||value>1048575)return false;entry.basis_max[j]=value;}
        at+=84;int64_t last=0;entry.ids.reserve(n);
        for(int64_t j=0;j<n;++j){const uint64_t raw=bytes.decode_u64(at);at+=8;if(raw>uint64_t(INT64_MAX)||int64_t(raw)<=last||!ids.insert(int64_t(raw)).second)return false;last=int64_t(raw);entry.ids.push_back(last);}
        regions.emplace(key,std::move(entry));previous=key;
    }
    return at==end;
}
bool NativeStaticBatch::validate_metadata(const PackedByteArray &bytes) const {
    String asset;PackedByteArray checkpoint;std::map<BlockKey,MetadataRegion> regions;std::set<int64_t> ids;
    return parse_metadata(bytes,asset,checkpoint,regions,ids)&&asset==asset_id;
}
bool NativeStaticBatch::restore_metadata(const PackedByteArray &bytes) {
    if(source_mesh.is_null()||defer_change_signal)return false;
    String asset;PackedByteArray checkpoint;std::map<BlockKey,MetadataRegion> regions;std::set<int64_t> ids;
    if(!parse_metadata(bytes,asset,checkpoint,regions,ids)||asset!=asset_id)return false;
    const AABB prototype=proxy_parts.empty()?source_mesh->get_aabb():proxy_box;
    if(!prototype.position.is_finite()||!prototype.size.is_finite()||!prototype.get_end().is_finite())return false;
    std::map<BlockKey,UnloadedRegion> staged;
    for(const auto &entry:regions) {
        UnloadedRegion missing;missing.checksum=entry.second.checksum;missing.count=entry.second.ids.size();
        Vector3 low,extent;const int axes[3]={entry.first.x,entry.first.y,entry.first.z};
        for(int row=0;row<3;++row) {
            double reach=0;
            for(int col=0;col<3;++col)reach+=double(entry.second.basis_max[row*3+col])*std::max(std::abs(double(prototype.position[col])),std::abs(double(prototype.get_end()[col])));
            // Round outwards when converting the conservative double bounds to
            // Godot's single precision vectors, including very large proxies.
            low[row]=std::nextafter(float(axes[row]*32.0-reach),-std::numeric_limits<float>::infinity());
            const float high=std::nextafter(float(axes[row]*32.0+32.0+reach),std::numeric_limits<float>::infinity());
            extent[row]=std::nextafter(high-low[row],std::numeric_limits<float>::infinity());
        }
        missing.bounds=AABB(low,extent);if(!low.is_finite()||!extent.is_finite())return false;
        staged.emplace(entry.first,std::move(missing));
    }
    // Validate all metadata and bounds before replacing live records or bodies.
    std::set<BlockKey> touched;for(const auto &entry:groups)touched.insert(entry.first);
    clear_proxies();collision_bounds.clear();collision_dirty=true;
    placements.clear();groups.clear();slots.clear();
    unloaded_regions=std::move(staged);unloaded_ids=std::move(ids);
    rebuild(touched);publish_change();return true;
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
    return unload_region_impl(expected);
}
bool NativeStaticBatch::unload_region_impl(const PackedByteArray &expected) {
    BlockKey key;String asset;std::map<int64_t,Placement> values;
    if(!parse_region(expected,asset,key,values)||asset!=asset_id||unloaded_regions.count(key)||
       groups.size()+unloaded_regions.size()+(groups.count(key)?0:1)>4096)return false;
    // parse_region already validated the canonical packet, both digests, IDs
    // and transforms. Compare the exact live records without allocating and
    // hashing another region packet. Float equality would miss signed-zero
    // changes, so compare the stored IEEE bits as the serializer does.
    auto group=groups.find(key);
    if((group==groups.end()?0:group->second.size())!=values.size())return false;
    if(group!=groups.end()) {
        auto id=group->second.begin();
        for(const auto &entry:values) {
            if(*id++!=entry.first)return false;
            const auto live=placements.find(entry.first);
            if(live==placements.end()||std::memcmp(live->second.data(),entry.second.data(),sizeof(float)*12))return false;
        }
    }
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
    if(defer_change_signal)return false;
    return restore_region_impl(bytes);
}
bool NativeStaticBatch::restore_region_impl(const PackedByteArray &bytes) {
    if(source_mesh.is_null())return false;
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
