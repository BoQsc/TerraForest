#include "static_batch.hpp"
#include <godot_cpp/classes/multi_mesh.hpp>
#include <algorithm>
#include <cmath>

namespace terraforest {
uint32_t NativeStaticBatch::render_page_capacity() const {
    // Even a dense origin group uploads in small independent draw pages. Tiny
    // application budgets reduce capacity rather than making the group invisible.
    return render_streaming?uint32_t(std::min({uint64_t(1024),render_tick_bytes/48,render_byte_limit/48})):100000;
}
uint64_t NativeStaticBatch::render_page_size(RenderKey key) const {
    auto group=render_ids.find(key.first);if(group==render_ids.end())return 0;
    uint64_t start=uint64_t(key.second)*render_page_capacity();
    return start>=group->second.size()?0:std::min(uint64_t(render_page_capacity()),group->second.size()-start);
}
void NativeStaticBatch::release_batch(RenderKey key) {
    auto batch=batches.find(key);if(batch==batches.end())return;
    auto ids=resident_ids.find(key);
    if(ids!=resident_ids.end()) {
        render_bytes-=ids->second.size()*48;
        for(auto id:ids->second)slots.erase(id);
        resident_ids.erase(ids);
    }
    memdelete(batch->second);batches.erase(batch);++render_evictions;
}
void NativeStaticBatch::release_group(BlockKey key) {
    auto it=batches.lower_bound({key,0});
    while(it!=batches.end()&&!(key<it->first.first)&&!(it->first.first<key)) {
        RenderKey page=it->first;++it;release_batch(page);
    }
}
void NativeStaticBatch::upload_batch(RenderKey page) {
    auto key=page.first;uint64_t count=render_page_size(page);
    if(!count||source_mesh.is_null()||retirement_locks(key))return;
    const auto &ordered=render_ids.at(key);
    uint64_t start=uint64_t(page.second)*render_page_capacity();
    Ref<MultiMesh> multi;multi.instantiate();
    multi->set_transform_format(MultiMesh::TRANSFORM_3D);multi->set_mesh(source_mesh);
    PackedFloat32Array buffer;buffer.resize(count*12);int offset=0;
    auto &ids=resident_ids[page];ids.reserve(count);
    for(uint64_t i=start;i<start+count;i++) {
        auto id=ordered[i];
        slots[id]=offset/12;ids.push_back(id);
        const auto &t=placements.at(id);std::copy(t.begin(),t.end(),buffer.ptrw()+offset);
        buffer[offset+3]-=key.x*32;buffer[offset+7]-=key.y*32;buffer[offset+11]-=key.z*32;offset+=12;
    }
    multi->set_instance_count(count);multi->set_buffer(buffer);
    auto *instance=memnew(MultiMeshInstance3D);instance->set_multimesh(multi);
    instance->set_cast_shadows_setting(casts_shadows?GeometryInstance3D::SHADOW_CASTING_SETTING_ON:GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
    instance->set_position(Vector3(key.x*32,key.y*32,key.z*32));
    add_child(instance);batches.emplace(page,instance);
    render_bytes+=count*48;render_uploaded_bytes+=count*48;++uploads;
}
bool NativeStaticBatch::configure_render_streaming(bool enabled,double radius,int64_t batch_limit,int64_t byte_limit,int64_t uploads_per_tick,int64_t bytes_per_tick) {
    if(admission)return false;
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
    if(!enabled)for(const auto &group:groups)upload_batch({group.first,0});
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
        if(retirement_locks(entry.first))continue;
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
    render_candidates=render_blocked=0;
    uint64_t bytes=0;std::set<RenderKey> wanted;std::vector<RenderKey> ordered;
    uint32_t capacity=render_page_capacity();
    for(const auto &candidate:candidates) {
        uint32_t pages=uint32_t((render_ids.at(candidate.key).size()+capacity-1)/capacity);
        render_candidates+=pages;
        for(uint32_t page=0;page<pages;page++) {
            if(wanted.size()>=size_t(render_batch_limit)) {render_blocked+=pages-page;break;}
            RenderKey key{candidate.key,page};uint64_t cost=render_page_size(key)*48;
            if(bytes+cost>render_byte_limit) {
                ++render_blocked;
                // All intervening full pages have identical cost. The final
                // partial page may still fit, so examine it without a dense scan.
                if(page+1<pages) {render_blocked+=pages-page-2;page=pages-2;}
                continue;
            }
            wanted.insert(key);ordered.push_back(key);bytes+=cost;
        }
    }
    std::vector<RenderKey> evict;
    for(const auto &batch:batches)if(!wanted.count(batch.first))evict.push_back(batch.first);
    for(auto key:evict)release_batch(key);
    render_pending.clear();
    for(auto it=ordered.rbegin();it!=ordered.rend();++it)if(!batches.count(*it))render_pending.push_back(*it);
}
void NativeStaticBatch::_process(double) {
    if(collision_only)return;
    if(!render_streaming||!is_inside_tree())return;
    if(render_dirty)select_render_batches();
    uint64_t uploaded=0;int count=0;
    while(!render_pending.empty()&&count<render_upload_limit) {
        RenderKey key=render_pending.back();uint64_t cost=render_page_size(key)*48;
        if(uploaded+cost>render_tick_bytes)break;
        render_pending.pop_back();upload_batch(key);uploaded+=cost;++count;
    }
}
void NativeStaticBatch::set_casts_shadows(bool enabled) {
    casts_shadows=enabled;
    for(auto &entry:batches)entry.second->set_cast_shadows_setting(enabled?GeometryInstance3D::SHADOW_CASTING_SETTING_ON:GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
}
Dictionary NativeStaticBatch::render_stats() const {
    Dictionary d;d["enabled"]=render_streaming;d["casts_shadows"]=casts_shadows;d["radius"]=render_radius;
    d["batch_limit"]=render_batch_limit;d["byte_limit"]=int64_t(render_byte_limit);
    d["uploads_per_tick"]=render_upload_limit;d["bytes_per_tick"]=int64_t(render_tick_bytes);
    d["resident_batches"]=int(batches.size());d["resident_instances"]=int(slots.size());
    d["resident_transform_bytes"]=int64_t(render_bytes);d["authored_groups"]=int(groups.size());
    d["candidate_batches"]=render_candidates;d["budget_deferred"]=render_blocked;
    d["pending_batches"]=int(render_pending.size());d["selection_pending"]=render_dirty;
    d["selection_queries"]=int64_t(render_queries);d["evictions"]=int64_t(render_evictions);
    d["uploaded_transform_bytes"]=int64_t(render_uploaded_bytes);
    d["page_capacity"]=int(render_page_capacity());
    uint64_t indexed=0,index_capacity=0;
    for(const auto &group:render_ids) {indexed+=group.second.size();index_capacity+=group.second.capacity()*sizeof(int64_t);}
    d["indexed_instances"]=int64_t(indexed);d["index_capacity_bytes"]=int64_t(index_capacity);
    return d;
}
}
