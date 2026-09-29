// SPDX-License-Identifier: 0BSD
#include "block_world.hpp"
#include <godot_cpp/classes/hashing_context.hpp>
#include <algorithm>
#include <cmath>
#include <cstring>

namespace terraforest {
static constexpr int REGION_LIMIT=16384, MAX_UNLOADED=65536;
static PackedByteArray region_hash(const PackedByteArray &data) {
    Ref<HashingContext> h;h.instantiate();h->start(HashingContext::HASH_SHA256);h->update(data);return h->finish();
}
bool NativeBlockWorld::valid_region(BlockKey k) {
    for(int v:{k.x,k.y,k.z})if(v<-REGION_LIMIT||v>=REGION_LIMIT)return false;
    return true;
}
bool NativeBlockWorld::is_region_loaded(Vector3i p) const {
    BlockKey k{p.x,p.y,p.z};return valid_region(k)&&!unloaded_regions.count(k);
}
bool NativeBlockWorld::unavailable_region(const AABB &bounds) const {
    if(unloaded_regions.empty())return false;
    Vector3 lo=bounds.position,hi=bounds.get_end();
    if(!lo.is_finite()||!hi.is_finite())return true;
    int a[3],b[3];int64_t volume=1;
    for(int axis=0;axis<3;axis++) {
        lo[axis]=std::max(double(lo[axis]),-1048576.0);
        hi[axis]=std::min(double(hi[axis]),1048576.0);
        if(hi[axis]<=lo[axis])return false;
        a[axis]=int(std::floor(lo[axis]/64));b[axis]=int(std::ceil(hi[axis]/64))-1;
        volume*=int64_t(b[axis]-a[axis]+1);
    }
    if(volume<=int64_t(unloaded_regions.size())) {
        for(int z=a[2];z<=b[2];z++)for(int y=a[1];y<=b[1];y++)for(int x=a[0];x<=b[0];x++)
            if(unloaded_regions.count({x,y,z}))return true;
    } else for(const auto &entry:unloaded_regions) {
        const auto k=entry.first;
        if(k.x>=a[0]&&k.x<=b[0]&&k.y>=a[1]&&k.y<=b[1]&&k.z>=a[2]&&k.z<=b[2])return true;
    }
    return false;
}
PackedByteArray NativeBlockWorld::capture_region(Vector3i position) const {
    BlockKey region{position.x,position.y,position.z};
    if(!valid_region(region)||unloaded_regions.count(region))return {};
    std::map<BlockKey,BlockChunk> selected;
    for(int z=0;z<4;z++)for(int y=0;y<4;y++)for(int x=0;x<4;x++) {
        auto it=chunks.find({region.x*4+x,region.y*4+y,region.z*4+z});
        if(it!=chunks.end())selected.emplace(it->first,it->second);
    }
    PackedByteArray payload=encode_chunks(selected),out;out.resize(24);
    std::memcpy(out.ptrw(),"TFRG\1\0\0\0",8);
    out.encode_s32(8,region.x);out.encode_s32(12,region.y);out.encode_s32(16,region.z);
    out.encode_u32(20,uint32_t(payload.size()));out.append_array(payload);out.append_array(region_hash(out));
    return out;
}
bool NativeBlockWorld::parse_region(const PackedByteArray &bytes,BlockKey &region,std::map<BlockKey,BlockChunk> &out) {
    // At most 64 chunks, each with up to 4096 four-byte RLE records.
    if(bytes.size()<100||bytes.size()>2*1024*1024||std::memcmp(bytes.ptr(),"TFRG\1\0\0\0",8))return false;
    if(bytes.decode_u32(20)!=uint64_t(bytes.size()-56))return false;
    if(region_hash(bytes.slice(0,bytes.size()-32))!=bytes.slice(bytes.size()-32))return false;
    region={int(bytes.decode_s32(8)),int(bytes.decode_s32(12)),int(bytes.decode_s32(16))};
    if(!valid_region(region))return false;
    const PackedByteArray payload=bytes.slice(24,bytes.size()-32);
    if(payload.size()<44||payload.decode_u32(8)>64||!parse(payload,&out))return false;
    for(const auto &entry:out) {
        BlockKey actual=region_for(entry.first);
        if(actual<region||region<actual)return false;
    }
    return true;
}
bool NativeBlockWorld::validate_region_snapshot(const PackedByteArray &bytes) const {
    BlockKey region;std::map<BlockKey,BlockChunk> restored;return parse_region(bytes,region,restored);
}
void NativeBlockWorld::replace_region_chunks(BlockKey region,std::map<BlockKey,BlockChunk> &&restored) {
    std::set<BlockKey> affected;
    for(int z=0;z<4;z++)for(int y=0;y<4;y++)for(int x=0;x<4;x++) {
        BlockKey key{region.x*4+x,region.y*4+y,region.z*4+z};
        if(chunks.erase(key))affected.insert(key);
    }
    for(auto &entry:restored) {affected.insert(entry.first);chunks.emplace(entry.first,std::move(entry.second));}
    for(auto k:affected) {
        invalidate(k);
        invalidate({k.x-1,k.y,k.z});invalidate({k.x+1,k.y,k.z});
        invalidate({k.x,k.y-1,k.z});invalidate({k.x,k.y+1,k.z});
        invalidate({k.x,k.y,k.z-1});invalidate({k.x,k.y,k.z+1});
    }
    clear_history();set_process(true);
}
bool NativeBlockWorld::unload_region(const PackedByteArray &expected_snapshot) {
    BlockKey region;std::map<BlockKey,BlockChunk> parsed;
    if(unloaded_regions.size()>=MAX_UNLOADED||!parse_region(expected_snapshot,region,parsed))return false;
    if(capture_region(Vector3i(region.x,region.y,region.z))!=expected_snapshot)return false;
    unloaded_regions.emplace(region,expected_snapshot.slice(expected_snapshot.size()-32));
    replace_region_chunks(region,{});
    emit_signal("changed");return true;
}
bool NativeBlockWorld::restore_region(const PackedByteArray &bytes,const PackedByteArray &expected_current) {
    BlockKey region;std::map<BlockKey,BlockChunk> restored;
    if(!parse_region(bytes,region,restored))return false;
    auto unloaded=unloaded_regions.find(region);
    if(unloaded!=unloaded_regions.end()) {
        if(!expected_current.is_empty()||unloaded->second!=bytes.slice(bytes.size()-32))return false;
    } else if(capture_region(Vector3i(region.x,region.y,region.z))!=expected_current)return false;
    size_t removed=0;
    for(int z=0;z<4;z++)for(int y=0;y<4;y++)for(int x=0;x<4;x++)removed+=chunks.count({region.x*4+x,region.y*4+y,region.z*4+z});
    if(chunks.size()-removed+restored.size()>2048)return false;
    if(unloaded==unloaded_regions.end()&&bytes==expected_current)return true;
    unloaded_regions.erase(region);replace_region_chunks(region,std::move(restored));
    emit_signal("changed");return true;
}
Dictionary NativeBlockWorld::region_stats() const {
    Dictionary out;out["region_edge_cells"]=64;out["resident_chunks"]=int(chunks.size());
    out["unloaded_regions"]=int(unloaded_regions.size());out["unloaded_digest_bytes"]=int64_t(unloaded_regions.size()*32);
    out["max_unloaded_regions"]=MAX_UNLOADED;out["whole_snapshot_available"]=unloaded_regions.empty();return out;
}
}
