// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <algorithm>

using namespace godot;
namespace terraforest {
void NativeWaterLocalEdit::_bind_methods(){
    ClassDB::bind_method(D_METHOD("prepare","patches","prepare_render"),&NativeWaterLocalEdit::prepare,DEFVAL(false));
    ClassDB::bind_method(D_METHOD("set_field","groups","bounds","solids","revision","epoch"),&NativeWaterLocalEdit::set_field);
    ClassDB::bind_method(D_METHOD("cancel"),&NativeWaterLocalEdit::cancel);
}

Ref<NativeWaterLocalEdit> NativeRegionalWater::capture_local_edit(bool wide) const {
    if(fill.running||batch_active||publish_pending||!publication_enabled||wide==wide_edit_bounds.empty()||
       local_edit_regions.empty()||local_edit_regions.size()>(wide?2048:512)||!relaxation_before.empty()||
       !wet_frontier.entries.empty())return {};
    Vector3i low(500,64,500),high(0,0,0);
    for(Key k:local_edit_regions){const auto p=position(k);low=low.min(p);high=high.max(p);}
    // The finite donor belt is three columns, followed by one changed-owner
    // ring and one complete reconstruction halo. Include the sea mask collar.
    for(Key k:urgent_meshes){const auto p=position(k);low=low.min(p);high=high.max(p);}
    for(const auto &[lo,hi]:wide_edit_bounds){low=low.min(lo);high=high.max(hi);}
    low=(low-Vector3i(5,3,5)).max(Vector3i());
    high=(high+Vector3i(5,3,5)).min(Vector3i(499,63,499));
    auto size=high-low+Vector3i(1,1,1);
    if(int64_t(size.x)*size.y*size.z>(wide?32768:8192))return {};
    Ref<NativeWaterLocalEdit> edit;edit.instantiate();edit->store.instantiate();
    edit->owner=get_instance_id();edit->revision=map_revision;edit->survey=survey_revision;edit->publication=batch_id;
    auto &s=*edit->store.ptr();
    s.western_ocean=western_ocean;s.surrounding_ocean=surrounding_ocean;
    s.publication_enabled=true;s.total=total;s.solid_cache_bytes=solid_cache_bytes;
    s.local_edit_regions=local_edit_regions;s.local_receiver_regions=local_receiver_regions;
    s.local_occupancy_regions=local_occupancy_regions;s.urgent_meshes=urgent_meshes;
    s.wide_edit_bounds=wide_edit_bounds;
    edit->receiver_slots=MAX_REGIONS-regions.size();
    s.mesh_set=urgent_meshes;s.meshes.assign(s.mesh_set.begin(),s.mesh_set.end());
    constexpr uint64_t limit=48*1024*1024;
    uint64_t bytes=0;
    for(int x=low.x;x<=high.x;++x)for(int y=low.y;y<=high.y;++y){
        const Key first=key({x,y,low.z}),end=key({x,y,high.z})+1;
        if(wide){
            auto deferred=deferred_regions.lower_bound(first);
            auto cached=ocean_cache.lower_bound(first);
            if((deferred!=deferred_regions.end()&&deferred->first<end)||
               (cached!=ocean_cache.end()&&cached->first<end))return {};
        }
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
            s.published_surfaces.try_emplace(it->first).first->second.render_digest=it->second.render_digest;
    }
    return edit;
}

bool NativeWaterLocalEdit::set_field(const Array &groups,const AABB &bounds,const Dictionary &solids,int64_t rev,int64_t epoch){
    if(started.load()||store.is_null()||store->wide_edit_bounds.empty()||groups.is_empty()||groups.size()>9||
       !bounds.has_volume()||!bounds.position.is_finite()||!bounds.size.is_finite()||rev<0||epoch<0)return false;
    for(int i=0;i<groups.size();++i){
        if(groups[i].get_type()!=Variant::DICTIONARY)return false;
        Dictionary entry=groups[i];Ref<RefCounted> core=entry.get("core",Variant());
        if(core.is_null()||(!core->is_class("TerrainFieldReader")&&!core->is_class("TerrainCore"))||
           entry.get("bounds",Variant()).get_type()!=Variant::RECT2I)return false;
    }
    field_groups=groups;field_bounds=bounds;solid_hulls=solids;field_revision=rev;field_epoch=epoch;
    return true;
}

// Capture pins the sparse owner metadata and the terrain revision once. The
// game thread never constructs a patch or polls a frame per group of 64.
bool NativeWaterLocalEdit::sample_edit_occupancy(Array &patches){
    struct Input {Vector3i coordinate;Ref<RefCounted> core;Array hulls;Ref<NativeWaterTerrainPatch> patch;};
    std::vector<Input> inputs;
    for(auto k:store->requests){
        const auto coord=store->position(k);
        const Rect2i area(coord.x*4,coord.z*4,4,4);
        const AABB region(Vector3(coord)*4,Vector3(4,4,4));
        if(!field_bounds.encloses(region))continue;
        if(solid_hulls.has(coord)&&solid_hulls[coord].get_type()!=Variant::ARRAY)return false;
        Ref<RefCounted> reader;
        for(int margin:{0,29}){
            for(int i=0;i<field_groups.size();++i){
                const Dictionary group=field_groups[i];
                if(Rect2i(group["bounds"]).grow(margin).encloses(area)){reader=group["core"];break;}
            }
            if(reader.is_valid())break;
        }
        if(reader.is_null())continue;
        if(inputs.size()>=2048)return false;
        inputs.push_back({coord,reader,solid_hulls.get(coord,Array()),{}});
    }
    struct Sampling{
        std::vector<Input> &inputs;
        NativeWaterLocalEdit &edit;
        std::atomic<bool> failed{false};
        std::atomic<uint64_t> bytes{0};
    } sampling{inputs,*this};
    auto run=[](void *data,uint32_t i){
        auto &work=*static_cast<Sampling*>(data);auto &entry=work.inputs[i];auto &edit=work.edit;
        if(work.failed.load()||edit.cancelled.load())return;
        entry.patch.instantiate();
        if(!entry.patch->configure(entry.coordinate)||(!entry.hulls.is_empty()&&!entry.patch->set_structure_hulls(entry.hulls))){
            work.failed.store(true);return;
        }
        int64_t status=0;
        while(status==0&&!edit.cancelled.load()&&!work.failed.load())
            status=entry.patch->sample_terrain(entry.core.ptr(),2048,edit.field_revision,edit.field_epoch);
        const auto &p=*entry.patch.ptr();
        const uint64_t charge=sizeof(p)+(p.contacts?p.contacts->bytes:0)+(p.structures?p.structures->bytes:0);
        if(status!=1||work.bytes.fetch_add(charge)+charge>48*1024*1024)work.failed.store(true);
    };
    auto *pool=WorkerThreadPool::get_singleton();
    auto task=inputs.size()>=12?pool->add_native_group_task(run,&sampling,int(inputs.size()),3,true,"Edited water occupancy"):-1;
    if(task>=0)pool->wait_for_group_task_completion(task);
    else for(size_t i=0;i<inputs.size()&&!sampling.failed.load();++i)run(&sampling,i);
    if(sampling.failed.load()||cancelled.load())return false;
    for(const auto &input:inputs)patches.push_back(input.patch);
    return true;
}

void NativeWaterLocalEdit::prepare(const Array &patches,bool prepare_render){
    bool expected=false;
    if(!started.compare_exchange_strong(expected,true))return;
    auto build=[&](){
        if(store.is_null())return false;
        auto &s=*store.ptr();
        Array occupancy=patches;
        if(!field_groups.is_empty()){
            occupancy=Array();
            if(!sample_edit_occupancy(occupancy)){result["fallback"]="edit field occupancy";return false;}
        }
        for(int i=0;i<occupancy.size();++i){
            if(cancelled.load())return false;
            Ref<NativeWaterTerrainPatch> patch=occupancy[i];
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
            if(!field_groups.is_empty()){
                if(!job->set_edit_field(field_groups,field_bounds,solid_hulls,field_revision,field_epoch)){
                    result["fallback"]="immutable field unavailable";return false;
                }
                job->receiver_slots=std::min(job->receiver_slots,receiver_slots);
            }
            job->prepare();
            if(cancelled.load()||!job->success||!job->required.empty()){result["fallback"]=job->required.empty()?job->reason:String("receiving region required");return false;}
            new_receivers=job->prepared_receivers;
            changed_regions.insert(job->changed_regions.begin(),job->changed_regions.end());
            result=s.finish_equilibrium(job);
            if(!bool(result.get("ok",false)))return false;
        }else{result["ok"]=true;result["local_response"]=true;}
        if(s.urgent_meshes.empty())return true;
        const uint64_t began=Time::get_singleton()->get_ticks_usec();
        uint64_t packet_bytes=0,upload_us=0,mesh_us=0;
        while(!s.publish_pending){
            if(cancelled.load())return false;
            Dictionary next=s.next_mesh_batch(true,true,false,true);
            if(next.is_empty()||next.has("failure")){result["fallback"]=next.get("failure","incomplete mesh halo");return false;}
            if(next.has("job")){
                const auto start=Time::get_singleton()->get_ticks_usec();
                Ref<NativeWaterMeshJob> mesh=next["job"];mesh->prepare();
                mesh_us+=Time::get_singleton()->get_ticks_usec()-start;
            }else if(bool(next.get("pending",false))){result["fallback"]="mesh reservation";return false;}
            if(next.has("coordinate")){
                const Array arrays=next["render_arrays"];
                const PackedVector3Array vertices=arrays[Mesh::ARRAY_VERTEX];
                const PackedInt32Array indices=arrays[Mesh::ARRAY_INDEX];
                packet_bytes+=vertices.size()*(sizeof(Vector3)*2+sizeof(Vector2)+sizeof(Color))+indices.size()*sizeof(int32_t);
                if(packet_bytes>48*1024*1024){result["fallback"]="render packet budget";return false;}
                if(prepare_render&&!indices.is_empty()){
                    const Vector3i coordinate=next["coordinate"];
                    const auto old=s.published_surfaces.find(s.key(coordinate));
                    const Dictionary faces=next["faces"];
                    const PackedByteArray digest=faces.get("render_digest",PackedByteArray());
                    if(digest.is_empty()||old==s.published_surfaces.end()||old->second.render_digest!=digest){
                        auto start=Time::get_singleton()->get_ticks_usec();
                        Ref<ArrayMesh> geometry;geometry.instantiate();
                        geometry->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,arrays);
                        if(geometry->get_surface_count()!=1){result["fallback"]="render resource preparation";return false;}
                        next["render_mesh"]=geometry;
                        upload_us+=Time::get_singleton()->get_ticks_usec()-start;
                    }
                }
                packets.push_back(next);
            }
        }
        result["detail_prepare_us"]=int64_t(Time::get_singleton()->get_ticks_usec()-began);
        result["detail_build_us"]=int64_t(mesh_us);result["render_upload_us"]=int64_t(upload_us);
        result["render_packet_bytes"]=int64_t(packet_bytes);result["render_packets"]=packets.size();
        return true;
    };
    complete=build();ready.store(true,std::memory_order_release);
}

Dictionary NativeRegionalWater::accept_local_edit(const Ref<NativeWaterLocalEdit> &edit){
    if(edit.is_null()||!edit->ready.load(std::memory_order_acquire)||edit->consumed||
       edit->owner!=get_instance_id())return {};
    edit->consumed=true;
    if(edit->cancelled.load()||edit->revision!=map_revision||edit->survey!=survey_revision||edit->publication!=batch_id||
       fill.running||batch_active||publish_pending)return {};
    if(!edit->complete){Dictionary deferred;deferred["fallback"]=edit->result.get("fallback","incomplete edit");return deferred;}
    auto &s=*edit->store.ptr();
    int64_t delta=0;
    for(const auto &[key,surface]:s.staged_surfaces){
        delta+=int64_t(surface.bytes());
        if(auto old=published_surfaces.find(key);old!=published_surfaces.end())delta-=int64_t(old->second.bytes());
    }
    if(int64_t(query_cache_bytes)+delta>int64_t(MAX_SURFACE_CACHE_BYTES))return {};
    if(regions.size()+edit->new_receivers.size()>MAX_REGIONS)return {};
    std::unordered_set<Key> incoming(edit->new_receivers.begin(),edit->new_receivers.end());
    for(auto k:incoming)if(regions.count(k)||deferred_regions.count(k)||ocean_cache.count(k)||!s.regions.count(k))return {};
    for(auto k:edit->changed_regions)if(!s.regions.count(k)||(!incoming.count(k)&&!regions.count(k)))return {};
    // Every failing check precedes the first live write. The old immersion
    // and raycast cache stays installed until the joint terrain handoff.
    for(auto k:incoming)regions.insert(s.regions.extract(k));
    for(auto k:edit->changed_regions)if(!incoming.count(k))regions.at(k)=std::move(s.regions.at(k));
    for(auto k:edit->sampled_regions){request_set.erase(k);if(restored_cache.count(k))++cache_rebuilds;}
    requests.erase(std::remove_if(requests.begin(),requests.end(),[&](Key k){return !request_set.count(k);}),requests.end());
    for(auto k:s.settling)if(settling_set.insert(k).second)settling.push_back(k);
    local_edit_regions=std::move(s.local_edit_regions);local_receiver_regions=std::move(s.local_receiver_regions);
    local_occupancy_regions=std::move(s.local_occupancy_regions);equilibrium_dependencies.clear();
    wide_edit_bounds=std::move(s.wide_edit_bounds);
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
    result["prepared_publication"]=s.publish_pending;
    return result;
}
}
