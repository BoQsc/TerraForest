#include "block_world.hpp"
#include <algorithm>
#include <cmath>

namespace terraforest {
double NativeBlockWorld::distance_to_focus(BlockKey k) const {
    return Vector3(k.x*16+8,k.y*16+8,k.z*16+8).distance_squared_to(focus);
}
void NativeBlockWorld::set_focus(Vector3 p) {
    if(!p.is_finite())return;
    focus=p;
    if(streaming&&p.distance_squared_to(residency_focus)>=64) {
        residency_focus=p;residency_dirty=true;set_process(true);
    }
}
bool NativeBlockWorld::configure_streaming(bool enabled,double radius,int64_t chunk_limit,int64_t mesh_byte_limit,int64_t cache_byte_limit) {
    if(!std::isfinite(radius)||radius<16||radius>4096||chunk_limit<1||chunk_limit>2048||
       mesh_byte_limit<65536||mesh_byte_limit>512*1024*1024||cache_byte_limit<0||cache_byte_limit>512*1024*1024)return false;
    streaming=enabled;render_radius=radius;render_limit=int(chunk_limit);
    mesh_budget=uint64_t(mesh_byte_limit);cache_budget=uint64_t(cache_byte_limit);
    if(!streaming) {bake_cache.clear();cache_bytes=0;}else trim_cache();
    residency_focus=focus;residency_dirty=true;set_process(true);return true;
}
void NativeBlockWorld::release_visual(BlockKey key) {
    auto it=visuals.find(key);if(it==visuals.end())return;
    mesh_bytes-=it->second.payload_bytes;
    retire_collision(it->second);
    memdelete(it->second.mesh);visuals.erase(it);
}
void NativeBlockWorld::erase_cached(BlockKey key) {
    auto it=bake_cache.find(key);if(it==bake_cache.end())return;
    cache_bytes-=it->second.bake.vertices.capacity()*sizeof(BlockVertex)+it->second.bake.indices.capacity()*sizeof(int32_t);
    bake_cache.erase(it);
}
void NativeBlockWorld::trim_cache() {
    while(!bake_cache.empty()&&(cache_bytes>cache_budget||!cache_budget)) {
        auto oldest=bake_cache.begin();
        for(auto it=bake_cache.begin();it!=bake_cache.end();++it)if(it->second.used<oldest->second.used)oldest=it;
        BlockKey key=oldest->first;erase_cached(key);cache_evictions++;
    }
}
void NativeBlockWorld::cache_bake(BlockBake &&b) {
    if(!streaming||!cache_budget||!chunks.count(b.key))return;
    auto pending=tickets.find(b.key);
    if(pending!=tickets.end()&&pending->second!=b.revision)return;
    uint64_t bytes=b.vertices.capacity()*sizeof(BlockVertex)+b.indices.capacity()*sizeof(int32_t);
    if(bytes>cache_budget)return;
    BlockKey key=b.key;erase_cached(key);
    cache_bytes+=bytes;bake_cache.emplace(key,CachedBlockBake{std::move(b),++cache_clock});trim_cache();
}
bool NativeBlockWorld::admit_mesh(BlockKey key,uint64_t bytes) {
    if(!streaming)return true;
    if(bytes>mesh_budget)return false;
    while(mesh_bytes+bytes>mesh_budget) {
        auto farthest=visuals.end();double distance=distance_to_focus(key);
        for(auto it=visuals.begin();it!=visuals.end();++it) {
            double d=distance_to_focus(it->first);
            if(d>distance) {distance=d;farthest=it;}
        }
        if(farthest==visuals.end())return false;
        BlockKey victim=farthest->first;release_visual(victim);settled.erase(victim);budget_blocked.insert(victim);mesh_evictions++;
    }
    return true;
}
void NativeBlockWorld::refresh_residency() {
    if(!residency_dirty)return;
    residency_dirty=false;residency_checks++;
    std::set<BlockKey> next;
    std::vector<std::pair<double,BlockKey>> candidates;
    for(const auto &entry:chunks) {
        double d=distance_to_focus(entry.first);
        if(!streaming)next.insert(entry.first);
        else if(d<=(render_radius+14)*(render_radius+14))candidates.emplace_back(d,entry.first);
    }
    if(streaming) {
        std::sort(candidates.begin(),candidates.end(),[](const auto &a,const auto &b){return a.first==b.first?a.second<b.second:a.first<b.first;});
        for(size_t i=0;i<std::min(candidates.size(),size_t(render_limit));i++)next.insert(candidates[i].second);
    }
    std::vector<BlockKey> remove;
    for(const auto &entry:visuals)if(!next.count(entry.first))remove.push_back(entry.first);
    for(auto key:remove) {release_visual(key);mesh_evictions++;}
    for(auto it=settled.begin();it!=settled.end();)if(!next.count(*it))it=settled.erase(it);else ++it;
    budget_blocked.clear();wanted=std::move(next);
    if(streaming)while(mesh_bytes>mesh_budget&&!visuals.empty()) {
        auto farthest=visuals.begin();
        for(auto it=visuals.begin();it!=visuals.end();++it)
            if(distance_to_focus(it->first)>distance_to_focus(farthest->first))farthest=it;
        BlockKey key=farthest->first;release_visual(key);settled.erase(key);budget_blocked.insert(key);mesh_evictions++;
    }
    for(auto it=dirty.begin();it!=dirty.end();) {
        if(!wanted.count(*it)) {
            bool active=worker_active&&!(*it<worker_key)&&!(worker_key<*it);
            if(!active)tickets.erase(*it);
            it=dirty.erase(it);
        } else ++it;
    }
    for(auto key:wanted) {
        bool active=worker_active&&!(key<worker_key)&&!(worker_key<key);
        if(!settled.count(key)&&!budget_blocked.count(key)&&!dirty.count(key)&&!active) {
            tickets[key]=++revision;dirty.insert(key);
        }
    }
}
Dictionary NativeBlockWorld::streaming_stats() const {
    int deferred=0;for(const auto &entry:chunks)deferred+=!wanted.count(entry.first);
    Dictionary out;out["enabled"]=streaming;out["radius"]=render_radius;out["chunk_limit"]=render_limit;
    out["wanted_chunks"]=int(wanted.size());out["settled_chunks"]=int(settled.size());out["budget_blocked_chunks"]=int(budget_blocked.size());
    out["deferred_chunks"]=deferred;out["residency_pending"]=residency_dirty;out["mesh_payload_bytes"]=int64_t(mesh_bytes);out["mesh_byte_limit"]=int64_t(mesh_budget);
    out["cache_capacity_bytes"]=int64_t(cache_bytes);out["cache_byte_limit"]=int64_t(cache_budget);out["cached_chunks"]=int(bake_cache.size());
    out["cache_hits"]=int64_t(cache_hits);out["bake_jobs"]=int64_t(cache_misses);out["mesh_evictions"]=int64_t(mesh_evictions);
    out["cache_evictions"]=int64_t(cache_evictions);out["residency_checks"]=int64_t(residency_checks);return out;
}
}
