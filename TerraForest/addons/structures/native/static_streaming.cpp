#include "static_batch.hpp"
#include <godot_cpp/classes/multi_mesh.hpp>
#include <algorithm>
#include <godot_cpp/classes/time.hpp>
#include <cmath>

namespace terraforest {
void NativeStaticBatch::remove_render_members(const std::set<BlockKey> &keys) {
    std::vector<RenderKey> changed;
    for(auto key:keys) {
        auto &ordered=render_ids.at(key);auto group=groups.find(key);
        if(group==groups.end())ordered.clear();
        else {
            size_t index=0;
            while(index<ordered.size()) {
                if(group->second.count(ordered[index])){++index;continue;}
                ordered[index]=ordered.back();ordered.pop_back();
            }
        }
        auto page=batches.lower_bound({key,0});
        for(;page!=batches.end()&&!(key<page->first.first)&&!(page->first.first<key);++page) {
            const auto &old=resident_ids.at(page->first);
            uint64_t count=std::min(uint64_t(old.size()),render_page_size(page->first));
            if(count!=old.size()||!std::equal(old.begin(),old.end(),ordered.begin()+uint64_t(page->first.second)*render_page_capacity()))changed.push_back(page->first);
        }
        if(group==groups.end()){render_bounds.erase(key);collision_bounds.erase(key);collision_index.erase(key);}
    }
    for(auto page:changed) {
        if(!render_page_size(page))release_batch(page,true,true);
        else for(auto identity:resident_ids.at(page))slots.erase(identity);
    }
    const float birth=float(Time::get_singleton()->get_ticks_msec()/1000.0);
    for(auto page:changed) {
        if(!batches.count(page))continue;
        auto &resident=resident_ids.at(page);
        uint64_t count=std::min(uint64_t(resident.size()),render_page_size(page));
        render_bytes-=resident.size()*64;
        const auto &ordered=render_ids.at(page.first);
        uint64_t start=uint64_t(page.second)*render_page_capacity();
        resident.assign(ordered.begin()+start,ordered.begin()+start+count);
        PackedFloat32Array buffer;buffer.resize(count*16);float *values=buffer.ptrw();
        for(uint64_t index=0;index<count;++index) {
            int64_t identity=resident[index];slots[identity]=int(index);
            const auto &pose=placements.at(identity);float *target=values+index*16;
            std::copy(pose.begin(),pose.end(),target);
            target[3]-=page.first.x*32;target[7]-=page.first.y*32;target[11]-=page.first.z*32;
            target[12]=appearance_birth.emplace(identity,birth).first->second;
            target[13]=1;target[14]=0;target[15]=0;
        }
        Ref<MultiMesh> multi=batches.at(page)->get_multimesh();
        if(multi->get_instance_count()!=int64_t(count))multi->set_instance_count(count);
        multi->set_buffer(buffer);render_bytes+=count*64;render_uploaded_bytes+=count*64;++uploads;
    }
    for(auto key:keys)if(!groups.count(key))render_ids.erase(key);
    if(!keys.empty()){render_dirty=true;collision_dirty=true;}
}
uint32_t NativeStaticBatch::render_page_capacity() const {
    // Even a dense origin group uploads in small independent draw pages. Tiny
    // application budgets reduce capacity rather than making the group invisible.
    return render_streaming?uint32_t(std::min({uint64_t(1024),render_tick_bytes/render_stride_bytes(),render_byte_limit/render_stride_bytes()})):100000;
}
uint64_t NativeStaticBatch::render_page_size(RenderKey key) const {
    auto group=render_ids.find(key.first);if(group==render_ids.end())return 0;
    uint64_t start=uint64_t(key.second)*render_page_capacity();
    return start>=group->second.size()?0:std::min(uint64_t(render_page_capacity()),group->second.size()-start);
}
void NativeStaticBatch::drain_render_retirement(uint64_t budget_usec) {
    const uint64_t started=Time::get_singleton()->get_ticks_usec();
    while(!retired_render_pages.empty()) {
        const auto retired=retired_render_pages.back();retired_render_pages.pop_back();
        if(render_pool.size()<16) {
            retired.node->get_multimesh()->set_instance_count(0);render_pool.push_back(retired.node);
        }else memdelete(retired.node);
        retired_render_bytes-=retired.bytes;
        if(budget_usec&&Time::get_singleton()->get_ticks_usec()-started>=budget_usec)break;
    }
}
void NativeStaticBatch::release_batch(RenderKey key,bool deferred,bool appearance_pruned) {
    auto batch=batches.find(key);if(batch==batches.end())return;
    auto ids=resident_ids.find(key);
    uint64_t bytes=0;
    if(ids!=resident_ids.end()) {
        bytes=ids->second.size()*render_stride_bytes();render_bytes-=bytes;
        for(auto id:ids->second){slots.erase(id);if(!appearance_pruned&&!placements.count(id))appearance_birth.erase(id);}
        resident_ids.erase(ids);
    }
    if(deferred&&appearance_fade&&render_streaming) {
        batch->second->set_visible(false);
        retired_render_pages.push_back({batch->second,bytes});retired_render_bytes+=bytes;
    }else if(appearance_fade&&render_streaming&&render_pool.size()<16) {
        batch->second->get_multimesh()->set_instance_count(0);render_pool.push_back(batch->second);
    }else memdelete(batch->second);
    batches.erase(batch);++render_evictions;
}
void NativeStaticBatch::release_group(BlockKey key) {
    auto it=batches.lower_bound({key,0});
    while(it!=batches.end()&&!(key<it->first.first)&&!(it->first.first<key)) {
        RenderKey page=it->first;++it;release_batch(page);
    }
}
void NativeStaticBatch::upload_batch(RenderKey page,uint64_t limit) {
    auto key=page.first;uint64_t count=std::min(render_page_size(page),limit);
    if(!count||source_mesh.is_null()||retirement_locks(key))return;
    // Replace an admitted partial page atomically within the current scene tick.
    // Callers have already reserved its target payload through selection.
    if(batches.count(page))release_batch(page);
    const auto &ordered=render_ids.at(key);
    uint64_t start=uint64_t(page.second)*render_page_capacity();
    MultiMeshInstance3D *instance=nullptr;Ref<MultiMesh> multi;
    if(!render_pool.empty()){instance=render_pool.back();render_pool.pop_back();multi=instance->get_multimesh();}
    else{multi.instantiate();instance=memnew(MultiMeshInstance3D);instance->set_multimesh(multi);add_child(instance);}
    multi->set_transform_format(MultiMesh::TRANSFORM_3D);multi->set_mesh(source_mesh);
    const int stride=appearance_fade?16:12;
    multi->set_use_custom_data(appearance_fade);
    const float birth=float(Time::get_singleton()->get_ticks_msec()/1000.0);
    PackedFloat32Array buffer;buffer.resize(count*stride);int offset=0;
    auto &ids=resident_ids[page];ids.reserve(count);
    for(uint64_t i=start;i<start+count;i++) {
        auto id=ordered[i];
        slots[id]=offset/stride;ids.push_back(id);
        const auto &t=placements.at(id);std::copy(t.begin(),t.end(),buffer.ptrw()+offset);
        buffer[offset+3]-=key.x*32;buffer[offset+7]-=key.y*32;buffer[offset+11]-=key.z*32;
        if(appearance_fade) {
            auto inserted=appearance_birth.emplace(id,birth);
            buffer[offset+12]=inserted.first->second;
            buffer[offset+13]=1.0f;buffer[offset+14]=0;buffer[offset+15]=0;
        }
        offset+=stride;
    }
    multi->set_instance_count(count);multi->set_buffer(buffer);
    instance->set_cast_shadows_setting(page_casts_shadows(page)?GeometryInstance3D::SHADOW_CASTING_SETTING_ON:GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
    instance->set_position(Vector3(key.x*32,key.y*32,key.z*32));
    instance->set_visible(true);
    batches.emplace(page,instance);
    render_bytes+=count*render_stride_bytes();render_uploaded_bytes+=count*render_stride_bytes();++uploads;
}
bool NativeStaticBatch::configure_render_streaming(bool enabled,double radius,int64_t batch_limit,int64_t byte_limit,int64_t uploads_per_tick,int64_t bytes_per_tick) {
    if(world_render_owner)return false;
    if(admission||collection_retirement)return false;
    if(!std::isfinite(radius)||radius<0||radius>16384||batch_limit<1||batch_limit>4096||
       byte_limit<render_stride_bytes()||byte_limit>8000000||uploads_per_tick<1||uploads_per_tick>64||
       bytes_per_tick<render_stride_bytes()||bytes_per_tick>4800000)return false;
    // Reconfiguration evicts immediately, so lower budgets cannot leave a stale
    // over-budget frame. Authored placements, proxies and journals are unchanged.
    while(!batches.empty())release_batch(batches.begin()->first);
    drain_render_retirement(0);
    render_pending.clear();render_streaming=enabled;render_radius=radius;
    render_batch_limit=int(batch_limit);render_byte_limit=uint64_t(byte_limit);
    render_upload_limit=int(uploads_per_tick);render_tick_bytes=uint64_t(bytes_per_tick);
    render_dirty=true;render_candidates=render_blocked=0;set_process(enabled);
    if(!enabled)for(const auto &group:groups)upload_batch({group.first,0});
    return true;
}
bool NativeStaticBatch::set_render_radius(double radius) {
    if(!std::isfinite(radius)||radius<0||radius>16384)return false;
    if(render_radius!=radius){render_radius=radius;render_dirty=true;}
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
            RenderKey key{candidate.key,page};uint64_t cost=render_page_size(key)*render_stride_bytes();
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
    for(auto key:evict)release_batch(key,true);
    for(auto &entry:batches)entry.second->set_cast_shadows_setting(page_casts_shadows(entry.first)?GeometryInstance3D::SHADOW_CASTING_SETTING_ON:GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
    render_pending.clear();
    for(auto it=ordered.rbegin();it!=ordered.rend();++it)
        if(!batches.count(*it)||resident_ids.at(*it).size()!=render_page_size(*it))render_pending.push_back(*it);
}
void NativeStaticBatch::_process(double) {
    const uint64_t started=Time::get_singleton()->get_ticks_usec();
    render_process_us=render_selection_us=render_cleanup_us=render_upload_us=0;
    drain_render_retirement(350);
    render_cleanup_us=Time::get_singleton()->get_ticks_usec()-started;
    render_process_us=render_cleanup_us;
    if(collection_retirement)return; // Retired GPU pages count against the collection budget.
    if(collision_only||world_render_owner)return;
    if(!render_streaming||!is_inside_tree())return;
    const uint64_t selection_started=Time::get_singleton()->get_ticks_usec();
    if(render_dirty)select_render_batches();
    render_selection_us=Time::get_singleton()->get_ticks_usec()-selection_started;
    const uint64_t upload_started=Time::get_singleton()->get_ticks_usec();
    uint64_t uploaded=0;int count=0;
    while(!render_pending.empty()&&count<render_upload_limit) {
        RenderKey key=render_pending.back();uint64_t cost=render_page_size(key)*render_stride_bytes();
        if(uploaded+cost>render_tick_bytes)break;
        const auto existing=resident_ids.find(key);
        const uint64_t replaced=existing==resident_ids.end()?0:existing->second.size()*render_stride_bytes();
        if(render_bytes+retired_render_bytes-replaced+cost>render_byte_limit||
           (existing==resident_ids.end()&&batches.size()+retired_render_pages.size()>=size_t(render_batch_limit)))break;
        render_pending.pop_back();upload_batch(key);uploaded+=cost;++count;
    }
    render_upload_us=Time::get_singleton()->get_ticks_usec()-upload_started;
    render_process_us=Time::get_singleton()->get_ticks_usec()-started;
}
Dictionary NativeStaticBatch::render_frame_profile() const {
    Dictionary result;result["process_us"]=int64_t(render_process_us);result["selection_us"]=int64_t(render_selection_us);
    result["cleanup_us"]=int64_t(render_cleanup_us);result["upload_us"]=int64_t(render_upload_us);return result;
}
bool NativeStaticBatch::configure_appearance_fade() {
    // Opt-in before data admission; default static props retain their 48-byte layout.
    if(collection_retirement||!placements.empty()||!unloaded_regions.empty()||!batches.empty()||admission||render_tick_bytes<64||render_byte_limit<64)return false;
    appearance_fade=true;return true;
}
bool NativeStaticBatch::page_casts_shadows(RenderKey key) const {
    if(!casts_shadows)return false;
    if(shadow_distance==0)return true;
    auto found=render_bounds.find(key.first);if(found==render_bounds.end())return false;
    const AABB &box=found->second;const Vector3 end=box.position+box.size;
    const double dx=render_focus.x-std::clamp(render_focus.x,box.position.x,end.x);
    const double dz=render_focus.z-std::clamp(render_focus.z,box.position.z,end.z);
    return dx*dx+dz*dz<=(shadow_distance+4)*(shadow_distance+4);
}
bool NativeStaticBatch::set_shadow_distance(double radius) {
    if(!std::isfinite(radius)||radius<0||radius>16384)return false;
    shadow_distance=radius;render_dirty=true;
    set_casts_shadows(casts_shadows);return true;
}
void NativeStaticBatch::set_casts_shadows(bool enabled) {
    casts_shadows=enabled;
    for(auto &entry:batches)entry.second->set_cast_shadows_setting(page_casts_shadows(entry.first)?GeometryInstance3D::SHADOW_CASTING_SETTING_ON:GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
}
bool NativeStaticBatch::is_render_region_ready(const AABB &world_bounds) const {
    if(!world_bounds.position.is_finite()||!world_bounds.size.is_finite()||
       world_bounds.size.x<=0||world_bounds.size.y<=0||world_bounds.size.z<=0)return false;
    if(collision_only)return true;
    const Transform3D transform=is_inside_tree()?get_global_transform():get_transform();
    const double determinant=transform.basis.determinant();
    if(!transform.is_finite()||!std::isfinite(determinant)||std::abs(determinant)<1e-9)return false;
    const AABB local=transform.affine_inverse().xform(world_bounds);
    if(!local.position.is_finite()||!local.get_end().is_finite())return false;
    // Missing metadata has no pending upload yet. Traverse its existing spatial
    // hierarchy, pruning whole subtrees outside the requested arrival region.
    const auto overlaps=[&](const auto &self,const ModelBoundsIndex::Node *node)->bool {
        if(!node||!node->bounds.intersects(local))return false;
        return node->box.intersects(local)||self(self,node->left.get())||self(self,node->right.get());
    };
    if(overlaps(overlaps,unloaded_bounds.root()))return false;
    // Require whole intersecting origin groups, conservatively including their
    // edge pages. Work scales with bounded resident groups/pages, not instances.
    for(const auto &group:render_bounds) {
        if(!group.second.intersects(local))continue;
        const auto ids=render_ids.find(group.first);
        if(ids==render_ids.end()||ids->second.empty())continue;
        if(!is_inside_tree()||retirement_locks(group.first))return false;
        const uint64_t pages=(ids->second.size()+render_page_capacity()-1)/render_page_capacity();
        for(uint64_t page=0;page<pages;++page) {
            RenderKey key{group.first,uint32_t(page)};
            const auto resident=resident_ids.find(key);
            if(!batches.count(key)||resident==resident_ids.end()||resident->second.size()!=render_page_size(key))return false;
        }
    }
    return true;
}
Dictionary NativeStaticBatch::render_stats() const {
    Dictionary timing;timing["validation_us"]=int64_t(removal_validation_us);timing["records_us"]=int64_t(removal_records_us);timing["render_us"]=int64_t(removal_render_us);
    Dictionary d;d["enabled"]=render_streaming;d["shadow_distance"]=shadow_distance;
    d["removal_timing"]=timing;
    d["pooled_empty_batches"]=int64_t(render_pool.size());
    int shadow_pages=0;for(const auto &entry:batches)if(entry.second->get_cast_shadows_setting()!=GeometryInstance3D::SHADOW_CASTING_SETTING_OFF)++shadow_pages;d["shadow_batches"]=shadow_pages;d["casts_shadows"]=casts_shadows;d["radius"]=render_radius;
    d["batch_limit"]=render_batch_limit;d["byte_limit"]=int64_t(render_byte_limit);
    d["uploads_per_tick"]=render_upload_limit;d["bytes_per_tick"]=int64_t(render_tick_bytes);
    d["resident_batches"]=int(batches.size());d["resident_instances"]=int(slots.size());
    d["retired_batches"]=int64_t(retired_render_pages.size()+(collection_retirement?collection_retirement->old_batches.size():0));
    d["retired_render_bytes"]=int64_t(retired_render_bytes+(collection_retirement?collection_retirement->render_bytes:0));
    d["retained_render_bytes"]=int64_t(render_bytes+retired_render_bytes+(collection_retirement?collection_retirement->render_bytes:0));
    d["resident_transform_bytes"]=int64_t(render_bytes);d["authored_groups"]=int(groups.size());
    d["candidate_batches"]=render_candidates;d["budget_deferred"]=render_blocked;
    d["pending_batches"]=int(render_pending.size());d["selection_pending"]=render_dirty;
    d["selection_queries"]=int64_t(render_queries);d["evictions"]=int64_t(render_evictions);
    d["uploaded_transform_bytes"]=int64_t(render_uploaded_bytes);
    d["page_capacity"]=int(render_page_capacity());
    d["instance_stride_bytes"]=int(render_stride_bytes());
    d["appearance_records"]=int(appearance_birth.size());
    uint64_t indexed=0,index_capacity=0;
    for(const auto &group:render_ids) {indexed+=group.second.size();index_capacity+=group.second.capacity()*sizeof(int64_t);}
    d["indexed_instances"]=int64_t(indexed);d["index_capacity_bytes"]=int64_t(index_capacity);
    return d;
}
}
