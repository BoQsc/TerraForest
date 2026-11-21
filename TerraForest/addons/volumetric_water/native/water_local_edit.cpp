// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>

using namespace godot;
namespace terraforest {
void NativeWaterLocalEdit::_bind_methods(){
    ClassDB::bind_method(D_METHOD("prepare","patches"),&NativeWaterLocalEdit::prepare);
}

Ref<NativeWaterLocalEdit> NativeRegionalWater::capture_local_edit() const {
    if(fill.running||batch_active||publish_pending||!publication_enabled||!wide_edit_bounds.empty()||
       local_edit_regions.empty()||local_edit_regions.size()>512||!relaxation_before.empty())return {};
    Vector3i low(500,64,500),high(0,0,0);
    for(Key k:local_edit_regions){const auto p=position(k);low=low.min(p);high=high.max(p);}
    // The finite donor belt is three columns, followed by one changed-owner
    // ring and one complete reconstruction halo. Include the sea mask collar.
    for(Key k:urgent_meshes){const auto p=position(k);low=low.min(p);high=high.max(p);}
    low=(low-Vector3i(5,3,5)).max(Vector3i());
    high=(high+Vector3i(5,3,5)).min(Vector3i(499,63,499));
    auto size=high-low+Vector3i(1,1,1);
    if(int64_t(size.x)*size.y*size.z>8192)return {};
    Ref<NativeWaterLocalEdit> edit;edit.instantiate();edit->store.instantiate();
    edit->owner=get_instance_id();edit->revision=map_revision;edit->survey=survey_revision;edit->publication=batch_id;
    auto &s=*edit->store.ptr();
    s.western_ocean=western_ocean;s.surrounding_ocean=surrounding_ocean;
    s.publication_enabled=true;s.total=total;s.solid_cache_bytes=solid_cache_bytes;
    s.local_edit_regions=local_edit_regions;s.local_receiver_regions=local_receiver_regions;
    s.local_occupancy_regions=local_occupancy_regions;s.urgent_meshes=urgent_meshes;
    s.mesh_set=urgent_meshes;s.meshes.assign(s.mesh_set.begin(),s.mesh_set.end());
    constexpr uint64_t limit=48*1024*1024;
    uint64_t bytes=0;
    for(int x=low.x;x<=high.x;++x)for(int y=low.y;y<=high.y;++y){
        const Key first=key({x,y,low.z}),end=key({x,y,high.z})+1;
        for(auto it=regions.lower_bound(first);it!=regions.end()&&it->first<end;++it){
            const Key k=it->first;const auto &r=it->second;
            bytes+=2*(sizeof(Region)+Region::payload_bytes+r.vacancies.size()*sizeof(uint32_t))+
                (r.contacts?r.contacts->bytes:0)+(r.structures?r.structures->bytes:0);
            if(bytes>limit)return {};
            s.regions.emplace(k,r);
            if(settling_set.count(k)){s.settling_set.insert(k);s.settling.push_back(k);}
            if(request_set.count(k))s.request(k);
            if(published_regions.count(k))s.published_regions.insert(k);
            if(auto old=published_occupancy.find(k);old!=published_occupancy.end())s.published_occupancy.emplace(k,old->second);
        }
        // The builder only needs to know whether an empty replacement retires
        // an old mesh. Keep the heavy old query triangles in the live world.
        for(auto it=published_surfaces.lower_bound(first);it!=published_surfaces.end()&&it->first<end;++it)
            s.published_surfaces.try_emplace(it->first);
    }
    return edit;
}

void NativeWaterLocalEdit::prepare(const Array &patches){
    bool expected=false;
    if(!started.compare_exchange_strong(expected,true))return;
    auto build=[&](){
        if(store.is_null())return false;
        auto &s=*store.ptr();
        for(int i=0;i<patches.size();++i){
            Ref<NativeWaterTerrainPatch> patch=patches[i];
            if(patch.is_null()||!s.accept_patch(patch)){result["fallback"]="invalid occupancy patch";return false;}
            const auto k=s.key(patch->coord);
            sampled_regions.push_back(k);changed_regions.insert(k);
        }
        for(auto k:s.local_edit_regions){
            auto found=s.regions.find(k);
            if(found==s.regions.end()||!found->second.valid){
                result["fallback"]="unfinished edit occupancy";return false;
            }
        }
        if(!s.settling.empty()){
            auto job=s.begin_equilibrium(0,true);
            if(job.is_null()){result["fallback"]="outstanding occupancy";return false;}
            job->prepare();
            if(!job->success||!job->required.empty()){result["fallback"]=job->required.empty()?job->reason:String("receiving region required");return false;}
            changed_regions.insert(job->changed_regions.begin(),job->changed_regions.end());
            result=s.finish_equilibrium(job);
            if(!bool(result.get("ok",false)))return false;
        }else{result["ok"]=true;result["local_response"]=true;}
        if(s.urgent_meshes.empty())return true;
        const uint64_t began=Time::get_singleton()->get_ticks_usec();
        uint64_t packet_bytes=0;
        while(!s.publish_pending){
            Dictionary next=s.next_mesh_batch(true,true,false,true);
            if(next.is_empty()||next.has("failure")){result["fallback"]=next.get("failure","incomplete mesh halo");return false;}
            if(next.has("job")){
                Ref<NativeWaterMeshJob> mesh=next["job"];mesh->prepare();
            }else if(bool(next.get("pending",false))){result["fallback"]="mesh reservation";return false;}
            if(next.has("coordinate")){
                const Array arrays=next["render_arrays"];
                const PackedVector3Array vertices=arrays[Mesh::ARRAY_VERTEX];
                const PackedInt32Array indices=arrays[Mesh::ARRAY_INDEX];
                packet_bytes+=vertices.size()*(sizeof(Vector3)*2+sizeof(Vector2)+sizeof(Color))+indices.size()*sizeof(int32_t);
                if(packet_bytes>48*1024*1024){result["fallback"]="render packet budget";return false;}
                packets.push_back(next);
            }
        }
        result["detail_prepare_us"]=int64_t(Time::get_singleton()->get_ticks_usec()-began);
        return true;
    };
    complete=build();ready.store(true,std::memory_order_release);
}

Dictionary NativeRegionalWater::accept_local_edit(const Ref<NativeWaterLocalEdit> &edit){
    if(edit.is_null()||!edit->ready.load(std::memory_order_acquire)||edit->consumed||
       edit->owner!=get_instance_id())return {};
    edit->consumed=true;
    if(edit->revision!=map_revision||edit->survey!=survey_revision||edit->publication!=batch_id||
       fill.running||batch_active||publish_pending)return {};
    if(!edit->complete){Dictionary deferred;deferred["fallback"]=edit->result.get("fallback","incomplete edit");return deferred;}
    auto &s=*edit->store.ptr();
    int64_t delta=0;
    for(const auto &[key,surface]:s.staged_surfaces){
        delta+=int64_t(surface.bytes());
        if(auto old=published_surfaces.find(key);old!=published_surfaces.end())delta-=int64_t(old->second.bytes());
    }
    if(int64_t(query_cache_bytes)+delta>int64_t(MAX_SURFACE_CACHE_BYTES))return {};
    for(auto k:edit->changed_regions)if(!s.regions.count(k)||!regions.count(k))return {};
    // Every failing check precedes the first live write. The old immersion
    // and raycast cache stays installed until the joint terrain handoff.
    for(auto k:edit->changed_regions)regions.at(k)=std::move(s.regions.at(k));
    for(auto k:edit->sampled_regions){request_set.erase(k);if(restored_cache.count(k))++cache_rebuilds;}
    requests.erase(std::remove_if(requests.begin(),requests.end(),[&](Key k){return !request_set.count(k);}),requests.end());
    for(auto k:s.settling)if(settling_set.insert(k).second)settling.push_back(k);
    local_edit_regions=std::move(s.local_edit_regions);local_receiver_regions=std::move(s.local_receiver_regions);
    local_occupancy_regions=std::move(s.local_occupancy_regions);equilibrium_dependencies.clear();
    sampled+=s.sampled;changes+=s.changes;total=s.total;solid_cache_bytes=s.solid_cache_bytes;
    for(auto k:s.mesh_set)if(mesh_set.insert(k).second)meshes.push_back(k);
    for(auto k:s.batch_owners){mesh_set.erase(k);urgent_meshes.erase(k);}
    meshes.erase(std::remove_if(meshes.begin(),meshes.end(),[&](Key k){return !mesh_set.count(k);}),meshes.end());
    if(s.publish_pending){
        batch_owners=std::move(s.batch_owners);staged_ready=std::move(s.staged_ready);
        staged_surfaces=std::move(s.staged_surfaces);staged_occupancy=std::move(s.staged_occupancy);
        staged_surface_bytes=s.staged_surface_bytes;staged_surface_delta=delta;
        batch_urgent=true;publish_pending=true;++batch_id;
    }
    mesh_worker_us=s.mesh_worker_us;max_mesh_worker_us=std::max(max_mesh_worker_us,s.max_mesh_worker_us);
    invalidate_snapshot();
    auto result=edit->result;
    result["resident_transaction"]=true;result["batch"]=int64_t(batch_id);result["packets"]=edit->packets;
    return result;
}
}
