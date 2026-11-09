// SPDX-License-Identifier: 0BSD
#include "block_occlusion.hpp"
#include <godot_cpp/classes/array_occluder3d.hpp>
#include <algorithm>
#include <chrono>
#include <cmath>

namespace terraforest {
void BlockOcclusion::hide(Entry &entry) {
    if(entry.stale)return;
    entry.node->hide();entry.stale=true;++invalidations;
}
bool BlockOcclusion::configure(bool value,double distance,int count,int64_t byte_limit) {
    if(!std::isfinite(distance)||distance<16||distance>256||count<1||count>256||byte_limit<65536||byte_limit>8*1024*1024)return false;
    enabled=value;radius=distance;limit=count;budget=uint64_t(byte_limit);dirty=true;
    // Disabling takes effect now; bounded retirement happens on subsequent ticks.
    if(!enabled)for(auto &entry:entries)hide(entry.second);
    return true;
}
void BlockOcclusion::invalidate(BlockKey key) {
    auto found=entries.find(key);if(found!=entries.end())hide(found->second);
    dirty=true;
}
void BlockOcclusion::forget(BlockKey key) {
    auto found=entries.find(key);
    if(found!=entries.end()){bytes-=found->second.bytes;entries.erase(found);}
    dirty=true;
}
void BlockOcclusion::select() {
    dirty=false;selection_focus=world.focus;++scans;pending.clear();skipped_large=0;
    std::vector<std::pair<double,BlockKey>> candidates;
    if(enabled)for(const auto &item:world.visuals) {
        if(world.dirty.count(item.first)||world.tickets.count(item.first))continue;
        const Vector3 origin(item.first.x*16,item.first.y*16,item.first.z*16);
        const double distance=world.focus.clamp(origin,origin+Vector3(16,16,16)).distance_squared_to(world.focus);
        if(distance>radius*radius)continue;
        const auto &visual=item.second;
        const uint64_t payload=visual.collision_vertices.size()*sizeof(Vector3)+visual.collision_indices.size()*sizeof(int32_t);
        if(!payload||payload>CHUNK_BYTES){++skipped_large;continue;}
        candidates.emplace_back(distance,item.first);
    }
    std::sort(candidates.begin(),candidates.end(),[](const auto &a,const auto &b){return a.first==b.first?a.second<b.second:a.first<b.first;});
    std::set<BlockKey> selected;uint64_t planned=0;
    for(const auto &item:candidates) {
        const auto &visual=world.visuals.at(item.second);
        const uint64_t payload=visual.collision_vertices.size()*sizeof(Vector3)+visual.collision_indices.size()*sizeof(int32_t);
        if(selected.size()>=size_t(limit))break;
        if(planned+payload>budget)continue;
        selected.insert(item.second);planned+=payload;
        auto existing=entries.find(item.second);
        if(existing==entries.end()||existing->second.stale)pending.push_back(item.second);
    }
    for(auto &entry:entries)if(!selected.count(entry.first))hide(entry.second);
}
void BlockOcclusion::step() {
    const auto begin=std::chrono::steady_clock::now();
    const auto elapsed=[&](){return std::chrono::duration<double,std::micro>(std::chrono::steady_clock::now()-begin).count();};
    last_uploads=0;
    if(dirty||world.focus.distance_squared_to(selection_focus)>=64)select();
    // Hidden stale geometry still counts against admission until it is freed.
    int retired=0;
    for(auto it=entries.begin();it!=entries.end()&&retired<4;) {
        if(!it->second.stale){++it;continue;}
        bytes-=it->second.bytes;memdelete(it->second.node);it=entries.erase(it);++retired;
        if(elapsed()>=500)break;
    }
    if(enabled&&!pending.empty()&&elapsed()<500) {
        const BlockKey key=pending.front();
        auto visual=world.visuals.find(key);
        if(visual==world.visuals.end()||world.dirty.count(key)||world.tickets.count(key)){pending.pop_front();dirty=true;}
        else if(!entries.count(key)) {
            const auto &source=visual->second;
            const uint64_t payload=source.collision_vertices.size()*sizeof(Vector3)+source.collision_indices.size()*sizeof(int32_t);
            if(bytes+payload<=budget&&entries.size()<size_t(limit)) {
                Ref<ArrayOccluder3D> shape;shape.instantiate();
                shape->set_arrays(source.collision_vertices,source.collision_indices);
                auto *node=memnew(OccluderInstance3D);node->set_name("BlockOccluder");node->set_occluder(shape);
                source.mesh->add_child(node);entries.emplace(key,Entry{node,payload,false});
                bytes+=payload;pending.pop_front();++published;++last_uploads;
            }
        }
    }
    last_us=elapsed();max_us=std::max(max_us,last_us);max_uploads=std::max(max_uploads,last_uploads);
}
void BlockOcclusion::flush() {
    // No worker or renderer waits: this is only the bounded publication queue.
    for(;;) {
        step();bool stale=false;for(const auto &entry:entries)stale|=entry.second.stale;
        if(!dirty&&pending.empty()&&!stale)break;
    }
}
Dictionary BlockOcclusion::stats() const {
    int stale=0;for(const auto &entry:entries)stale+=entry.second.stale;
    Dictionary out;out["enabled"]=enabled;out["radius"]=radius;out["chunk_limit"]=limit;
    out["geometry_byte_limit"]=int64_t(budget);out["chunk_byte_limit"]=int64_t(CHUNK_BYTES);
    out["geometry_bytes"]=int64_t(bytes);out["resident"]=int(entries.size());out["active"]=int(entries.size())-stale;
    out["retiring"]=stale;out["pending"]=int(pending.size());out["selection_dirty"]=dirty;
    out["selection_scans"]=int64_t(scans);out["published"]=int64_t(published);out["invalidations"]=int64_t(invalidations);
    out["oversized_chunks_skipped"]=int64_t(skipped_large);out["step_last_us"]=last_us;out["step_max_us"]=max_us;
    out["step_uploads"]=last_uploads;out["step_max_uploads"]=max_uploads;return out;
}
bool NativeBlockWorld::configure_occlusion(bool enabled,double radius,int count,int64_t bytes) {
    if(!occlusion)occlusion=new BlockOcclusion(*this);
    return occlusion->configure(enabled,radius,count,bytes);
}
Dictionary NativeBlockWorld::occlusion_stats() const {return occlusion?occlusion->stats():Dictionary();}
}
