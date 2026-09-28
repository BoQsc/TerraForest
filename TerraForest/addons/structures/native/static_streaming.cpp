#include "static_batch.hpp"
#include <godot_cpp/classes/multi_mesh.hpp>
#include <algorithm>
#include <cmath>

namespace terraforest {
void NativeStaticBatch::release_batch(BlockKey key) {
    auto batch=batches.find(key);if(batch==batches.end())return;
    auto ids=resident_ids.find(key);
    if(ids!=resident_ids.end()) {
        render_bytes-=ids->second.size()*48;
        for(auto id:ids->second)slots.erase(id);
        resident_ids.erase(ids);
    }
    memdelete(batch->second);batches.erase(batch);++render_evictions;
}
void NativeStaticBatch::upload_batch(BlockKey key) {
    auto group=groups.find(key);if(group==groups.end()||source_mesh.is_null())return;
    Ref<MultiMesh> multi;multi.instantiate();
    multi->set_transform_format(MultiMesh::TRANSFORM_3D);multi->set_mesh(source_mesh);
    PackedFloat32Array buffer;buffer.resize(group->second.size()*12);int offset=0;
    auto &ids=resident_ids[key];ids.reserve(group->second.size());
    for(auto id:group->second) {
        slots[id]=offset/12;ids.push_back(id);
        const auto &t=placements.at(id);std::copy(t.begin(),t.end(),buffer.ptrw()+offset);
        buffer[offset+3]-=key.x*32;buffer[offset+7]-=key.y*32;buffer[offset+11]-=key.z*32;offset+=12;
    }
    multi->set_instance_count(group->second.size());multi->set_buffer(buffer);
    auto *instance=memnew(MultiMeshInstance3D);instance->set_multimesh(multi);
    instance->set_position(Vector3(key.x*32,key.y*32,key.z*32));
    add_child(instance);batches.emplace(key,instance);
    render_bytes+=group->second.size()*48;render_uploaded_bytes+=group->second.size()*48;++uploads;
}
bool NativeStaticBatch::configure_render_streaming(bool enabled,double radius,int64_t batch_limit,int64_t byte_limit,int64_t uploads_per_tick,int64_t bytes_per_tick) {
    if(!std::isfinite(radius)||radius<0||radius>16384||batch_limit<1||batch_limit>4096||
       byte_limit<48||byte_limit>4800000||uploads_per_tick<1||uploads_per_tick>64||
       bytes_per_tick<48||bytes_per_tick>4800000)return false;
    // Reconfiguration evicts immediately, so lower budgets cannot leave a stale
    // over-budget frame. Authored placements, proxies and journals are unchanged.
    while(!batches.empty())release_batch(batches.begin()->first);
    render_pending.clear();render_streaming=enabled;render_radius=radius;
    render_batch_limit=int(batch_limit);render_byte_limit=uint64_t(byte_limit);
    render_upload_limit=int(uploads_per_tick);render_tick_bytes=uint64_t(bytes_per_tick);
    render_dirty=true;render_candidates=render_blocked=0;set_process(enabled);
    if(!enabled)for(const auto &group:groups)upload_batch(group.first);
    return true;
}
void NativeStaticBatch::set_render_focus(Vector3 focus) {
    if(!focus.is_finite())return;
    render_focus=focus;
    // Local-space focus, like collision focus. A four-unit padding preserves
    // coverage while avoiding selection on every sub-unit camera movement.
    if(focus.distance_squared_to(render_selection_focus)>=16)render_dirty=true;
}
void NativeStaticBatch::select_render_batches() {
    render_dirty=false;render_selection_focus=render_focus;++render_queries;
    struct Candidate {double distance;BlockKey key;};
    std::vector<Candidate> candidates;
    const double range=(render_radius+4)*(render_radius+4);
    for(const auto &entry:render_bounds) {
        const auto &box=entry.second;Vector3 end=box.position+box.size;
        Vector3 nearest(std::clamp(render_focus.x,box.position.x,end.x),
                        std::clamp(render_focus.y,box.position.y,end.y),
                        std::clamp(render_focus.z,box.position.z,end.z));
        double distance=nearest.distance_squared_to(render_focus);
        if(std::isfinite(distance)&&distance<=range)candidates.push_back({distance,entry.first});
    }
    std::sort(candidates.begin(),candidates.end(),[](const Candidate &a,const Candidate &b){
        return a.distance==b.distance?a.key<b.key:a.distance<b.distance;
    });
    render_candidates=int(candidates.size());render_blocked=0;
    uint64_t bytes=0;std::set<BlockKey> wanted;std::vector<BlockKey> ordered;
    for(const auto &candidate:candidates) {
        uint64_t cost=groups.at(candidate.key).size()*48;
        if(wanted.size()>=size_t(render_batch_limit)||bytes+cost>render_byte_limit||cost>render_tick_bytes) {
            ++render_blocked;continue;
        }
        wanted.insert(candidate.key);ordered.push_back(candidate.key);bytes+=cost;
    }
    std::vector<BlockKey> evict;
    for(const auto &batch:batches)if(!wanted.count(batch.first))evict.push_back(batch.first);
    for(auto key:evict)release_batch(key);
    render_pending.clear();
    for(auto it=ordered.rbegin();it!=ordered.rend();++it)if(!batches.count(*it))render_pending.push_back(*it);
}
void NativeStaticBatch::_process(double) {
    if(!render_streaming||!is_inside_tree())return;
    if(render_dirty)select_render_batches();
    uint64_t uploaded=0;int count=0;
    while(!render_pending.empty()&&count<render_upload_limit) {
        BlockKey key=render_pending.back();uint64_t cost=groups.at(key).size()*48;
        if(uploaded+cost>render_tick_bytes)break;
        render_pending.pop_back();upload_batch(key);uploaded+=cost;++count;
    }
}
Dictionary NativeStaticBatch::render_stats() const {
    Dictionary d;d["enabled"]=render_streaming;d["radius"]=render_radius;
    d["batch_limit"]=render_batch_limit;d["byte_limit"]=int64_t(render_byte_limit);
    d["uploads_per_tick"]=render_upload_limit;d["bytes_per_tick"]=int64_t(render_tick_bytes);
    d["resident_batches"]=int(batches.size());d["resident_instances"]=int(slots.size());
    d["resident_transform_bytes"]=int64_t(render_bytes);d["authored_groups"]=int(groups.size());
    d["candidate_batches"]=render_candidates;d["budget_deferred"]=render_blocked;
    d["pending_batches"]=int(render_pending.size());d["selection_pending"]=render_dirty;
    d["selection_queries"]=int64_t(render_queries);d["evictions"]=int64_t(render_evictions);
    d["uploaded_transform_bytes"]=int64_t(render_uploaded_bytes);
    return d;
}
}
