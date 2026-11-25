// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include "water_terrain_class.hpp"
#include "water_edit_stencil.hpp"
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
    ClassDB::bind_method(D_METHOD("set_terrain_writes","writes","prior_field","ticket"),&NativeWaterLocalEdit::set_terrain_writes);
    ClassDB::bind_method(D_METHOD("cancel"),&NativeWaterLocalEdit::cancel);
}

bool NativeRegionalWater::owns_edit_input(const Ref<NativeWaterLocalEdit> &edit) const {
    return edit.is_valid()&&edit->owner==get_instance_id()&&edit->base_revision==map_revision&&
        edit->base_survey==survey_revision&&edit->publication==batch_id;
}

Ref<NativeWaterLocalEdit> NativeRegionalWater::capture_local_edit(bool wide,const Array &planned) const {
    if(fill.running||batch_active||publish_pending||!publication_enabled||!relaxation_before.empty()||
       !wet_frontier.entries.empty())return {};
    Vector3i low(500,64,500),high(0,0,0);
    std::vector<AABB> areas;
    if(!planned.is_empty()){
        if(planned.size()>4||!wide_edit_bounds.empty()||!local_edit_regions.empty())return {};
        wide=false;
        for(int i=0;i<planned.size();++i){
            if(planned[i].get_type()!=Variant::AABB)return {};
            AABB box=planned[i];
            if(!box.has_volume()||!box.position.is_finite()||!box.size.is_finite())return {};
            areas.push_back(box);
            auto start=position(region_key(cell(box.position-Vector3(.5,.5,.5)).clamp(Vector3i(),Vector3i(3999,511,3999))));
            auto end=position(region_key(cell(box.get_end()+Vector3(.5,.5,.5)).clamp(Vector3i(),Vector3i(3999,511,3999))));
            const auto span=end-start+Vector3i(1,1,1);
            wide|=int64_t(span.x)*span.y*span.z>512;
            low=low.min(start);high=high.max(end);
            if(surrounding_ocean&&box.position.y<=40&&box.get_end().y>=40){
                low=low.min(Vector3i(start.x-1,7,start.z-1));high=high.max(Vector3i(end.x+1,10,end.z+1));
            }
            // Private settlement must see the same region creation and cache
            // restoration as the live owner. Defer cold evictions to that owner.
            for(int x=start.x;x<=end.x;++x)for(int y=start.y;y<=end.y;++y){
                const auto first=key({x,y,start.z}),last=key({x,y,end.z});
                auto cold=ocean_cache.lower_bound(first);auto deferred=deferred_regions.lower_bound(first);
                if((cold!=ocean_cache.end()&&cold->first<=last)||(deferred!=deferred_regions.end()&&deferred->first<=last))return {};
            }
        }
    }else if(wide==wide_edit_bounds.empty()||local_edit_regions.empty())return {};
    if(local_edit_regions.size()>(wide?2048:512))return {};
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
    edit->base_revision=map_revision;edit->base_survey=survey_revision;
    edit->planned_settlement=std::move(areas);
    auto &s=*edit->store.ptr();
    s.map_revision=map_revision;s.survey_revision=survey_revision;
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
    if(started.load()||store.is_null()||groups.is_empty()||groups.size()>9||
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

void NativeWaterLocalEdit::set_terrain_writes(const Array &writes,int64_t from,int64_t ticket){
    if(started.load())return;
    terrain_writes=Array();write_ticket=-1;
    if(field_revision<0||from<0||ticket<0||writes.is_empty()||writes.size()>4)return;
    int64_t revision=from;
    for(int i=0;i<writes.size();++i){
        if(writes[i].get_type()!=Variant::PACKED_BYTE_ARRAY)return;
        const PackedByteArray bytes=writes[i];
        if(bytes.size()<12||bytes.size()>12+262144*8||bytes.decode_u32(0)!=1||
                int64_t(bytes.decode_u32(4))!=revision)return;
        const int64_t next=bytes.decode_u32(8);
        if(next<revision||next>revision+1||(next==revision&&bytes.size()>12))return;
        revision=next;
    }
    if(revision!=field_revision)return;
    terrain_writes=writes;write_ticket=ticket;
}

// Capture pins the sparse owner metadata and the terrain revision once. The
// game thread never constructs a patch or polls a frame per group of 64.
bool NativeWaterLocalEdit::sample_edit_occupancy(Array &patches){
    struct Input {
        Vector3i coordinate;Ref<RefCounted> core;Array hulls;Ref<NativeWaterTerrainPatch> patch;
        uint8_t uniform=0;int representative=-1;bool retained=false;
    };
    std::vector<Input> inputs;
    const bool compact=store->wide_edit_bounds.empty();
    std::vector<uint64_t> selected;
    if(compact){
        // Include the same reconstruction collar as the live shoreline
        // operation. Leave unrelated streaming requests with their owner.
        Array coordinates=store->pending_edit_patches();
        for(int i=0;i<coordinates.size();++i)selected.push_back(store->key(coordinates[i]));
    }else selected.assign(store->requests.begin(),store->requests.end());
    for(auto k:selected){
        const auto coord=store->position(k);
        const Rect2i area(coord.x*4,coord.z*4,4,4);
        const AABB region(Vector3(coord)*4,Vector3(4,4,4));
        if(!field_bounds.encloses(region)){if(compact)return false;continue;}
        if(solid_hulls.has(coord)&&solid_hulls[coord].get_type()!=Variant::ARRAY)return false;
        Ref<RefCounted> reader;
        for(int margin:{0,29}){
            for(int i=0;i<field_groups.size();++i){
                const Dictionary group=field_groups[i];
                if(Rect2i(group["bounds"]).grow(margin).encloses(area)){reader=group["core"];break;}
            }
            if(reader.is_valid())break;
        }
        if(reader.is_null()){if(compact)return false;continue;}
        if(inputs.size()>=2048)return false;
        inputs.push_back({coord,reader,solid_hulls.get(coord,Array()),{}});
    }
    int retained_count=0;
    if(!terrain_writes.is_empty()&&!inputs.empty()){
        Vector3i lo=inputs.front().coordinate,hi=lo;
        for(const auto &input:inputs){lo=lo.min(input.coordinate);hi=hi.max(input.coordinate);}
        WaterEditStencil stencil;
        bool valid=stencil.begin({lo.x,lo.y,lo.z},{hi.x,hi.y,hi.z});
        for(int i=0;valid&&i<terrain_writes.size();++i){
            const PackedByteArray bytes=terrain_writes[i];
            valid=stencil.records(bytes.ptr()+12,size_t(bytes.size()-12));
        }
        if(valid){
            stencil.seal();
            for(auto &input:inputs){
                const auto p=input.coordinate;
                const auto &r=store->regions.at(store->key(p));
                if(r.valid_before_edit==write_ticket&&r.has_density&&r.occupancy_version==13&&
                   !stencil.changed({p.x,p.y,p.z})){input.retained=true;++retained_count;}
            }
        }
        terrain_writes=Array();
    }
    // A changed brick and a newly reached receiver read the same sealed field.
    // Only share geometry proved identical throughout the extraction stencil.
    // Each owner keeps its own quantity, old revision and changed-face mask.
    int uniform_count=0,layer_count=0;
    for(int group=0;group<field_groups.size();++group){
        Dictionary entry=field_groups[group];Ref<RefCounted> reader=entry["core"];
        if(!reader->has_method("classify_water_bricks"))continue;
        PackedInt32Array origins;std::vector<int> rows;
        for(size_t i=0;i<inputs.size();++i)if(!inputs[i].retained&&inputs[i].core==reader&&inputs[i].hulls.is_empty()){
            rows.push_back(int(i));
            for(int axis=0;axis<3;++axis)origins.push_back(inputs[i].coordinate[axis]*4);
        }
        if(rows.empty())continue;
        PackedByteArray certificates=classify_edit_bricks(reader.ptr(),origins,field_revision,field_epoch);
        if(certificates.size()!=17*int64_t(rows.size()))return false;
        std::map<WaterSectionSignature,int> representatives;
        for(size_t n=0;n<rows.size();++n){
            const auto *record=certificates.ptr()+17*n;
            auto &input=inputs[rows[n]];
            if(record[0]==0)continue;
            if(record[0]<=2){input.uniform=record[0];++uniform_count;continue;}
            if(record[0]!=3&&record[0]!=4)return false;
            auto [it,first]=representatives.emplace(water_section_signature(record,input.coordinate.y),rows[n]);
            if(!first){input.representative=it->second;++layer_count;}
        }
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
        if(entry.retained){
            auto &p=*entry.patch.ptr();p.retained_edit=edit.write_ticket;p.status=1;
            if(work.bytes.fetch_add(sizeof(p))+sizeof(p)>48*1024*1024)work.failed.store(true);
            return;
        }
        if(entry.representative>=0)return;
        if(entry.uniform){
            auto &p=*entry.patch.ptr();
            const bool clear=entry.uniform==1;
            p.floor.fill(clear?0:500);p.ceiling.fill(500);p.density.fill(clear?1.f:-1.f);
            p.brick_geometry=clear?WaterBrickGeometry::air:WaterBrickGeometry::solid;
            p.revision=edit.field_revision;p.epoch=edit.field_epoch;p.status=1;
            if(work.bytes.fetch_add(sizeof(p))+sizeof(p)>48*1024*1024)work.failed.store(true);
            return;
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
    for(const auto &input:inputs){
        if(input.representative>=0){
            auto &p=*input.patch.ptr();
            const auto &model=*inputs[input.representative].patch.ptr();
            const size_t charge=sizeof(p)+(model.contacts?model.contacts->bytes:0)+(model.structures?model.structures->bytes:0);
            if(model.status!=1||sampling.bytes.fetch_add(charge)+charge>48*1024*1024)return false;
            p.floor=model.floor;p.ceiling=model.ceiling;p.density=model.density;
            p.contacts=model.contacts;p.structures=model.structures;p.brick_geometry=model.brick_geometry;
            p.revision=field_revision;p.epoch=field_epoch;p.status=1;
        }
        patches.push_back(input.patch);
    }
    result["uniform_edit_patches"]=uniform_count;
    result["unchanged_contact_bricks"]=retained_count;
    result["shared_layer_edit_patches"]=layer_count;
    return true;
}

void NativeWaterLocalEdit::prepare(const Array &patches,bool prepare_render){
    bool expected=false;
    if(!started.compare_exchange_strong(expected,true))return;
    auto build=[&](){
        if(store.is_null())return false;
        auto &s=*store.ptr();
        const uint64_t start=Time::get_singleton()->get_ticks_usec();
        if(!planned_settlement.empty()){
            const auto original=s.regions.size();
            for(const auto &area:planned_settlement)s.settle_after_edit(area);
            if(s.regions.size()-original>receiver_slots||s.local_edit_regions.empty()||
               s.local_edit_regions.size()>(s.wide_edit_bounds.empty()?512:2048)){
                result["fallback"]="resident settlement extent";return false;
            }
            receiver_slots-=s.regions.size()-original;
            revision=s.map_revision;survey=s.survey_revision;
            result["sealed_field_dispatch"]=true;
        }
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
        const uint64_t sampled_us=Time::get_singleton()->get_ticks_usec()-start;
        if(!s.settling.empty()){
            auto job=s.begin_equilibrium(0,true);
            if(job.is_null()){result["fallback"]="outstanding occupancy";return false;}
            if(!field_groups.is_empty()&&!s.wide_edit_bounds.empty()){
                if(!job->set_edit_field(field_groups,field_bounds,solid_hulls,field_revision,field_epoch)){
                    result["fallback"]="immutable field unavailable";return false;
                }
            }
            job->prepare();
            if(cancelled.load()||!job->success||!job->required.empty()){result["fallback"]=job->required.empty()?job->reason:String("receiving region required");return false;}
            const auto explored=job->prepared_receivers.size();
            job->retain_receiver_halo(s);
            result["dry_survey_only_regions"]=int64_t(explored-job->prepared_receivers.size());
            if(job->prepared_receivers.size()>receiver_slots){result["fallback"]="resident wet footprint capacity";return false;}
            new_receivers=job->prepared_receivers;
            changed_regions.insert(job->changed_regions.begin(),job->changed_regions.end());
            result.merge(s.finish_equilibrium(job),true);
            if(!bool(result.get("ok",false)))return false;
        }else{result["ok"]=true;result["local_response"]=true;}
        result["occupancy_sample_us"]=int64_t(sampled_us);
        result["occupancy_regions"]=occupancy.size();
        if(s.urgent_meshes.empty())return true;
        const uint64_t began=Time::get_singleton()->get_ticks_usec();
        uint64_t packet_bytes=0,upload_us=0,mesh_us=0;
        uint64_t reconstruction_us=0,boundary_us=0,topology_us=0;
        int open_sheets=0,level_sections=0,monotone_cells=0,oblique_cells=0,general_packets=0;
        while(!s.publish_pending){
            if(cancelled.load())return false;
            Dictionary next=s.advance_mesh_batch(true,true,false,true,true);
            if(next.is_empty()||next.has("failure")){result["fallback"]=next.get("failure","incomplete mesh halo");return false;}
            if(next.has("job")){
                const auto start=Time::get_singleton()->get_ticks_usec();
                Ref<NativeWaterMeshJob> mesh=next["job"];mesh->prepare();
                mesh_us+=Time::get_singleton()->get_ticks_usec()-start;
            }else if(bool(next.get("pending",false))){result["fallback"]="mesh reservation";return false;}
            if(next.has("coordinate")){
                const Dictionary faces=next["faces"];
                open_sheets+=bool(faces.get("open_sheet",false));level_sections+=bool(faces.get("level_section",false));
                general_packets+=faces.has("boundary_us");
                reconstruction_us+=int64_t(faces.get("reconstruct_us",0));
                boundary_us+=int64_t(faces.get("boundary_us",0));topology_us+=int64_t(faces.get("topology_pack_us",0));
                monotone_cells+=int(faces.get("monotone_cells",0));oblique_cells+=int(faces.get("oblique_cells",0));
                const Array arrays=next["render_arrays"];
                const PackedVector3Array vertices=arrays[Mesh::ARRAY_VERTEX];
                const PackedInt32Array indices=arrays[Mesh::ARRAY_INDEX];
                packet_bytes+=vertices.size()*(sizeof(Vector3)*2+sizeof(Vector2)+sizeof(Color))+indices.size()*sizeof(int32_t);
                if(packet_bytes>48*1024*1024){result["fallback"]="render packet budget";return false;}
                if(prepare_render&&!indices.is_empty()){
                    const Vector3i coordinate=next["coordinate"];
                    const auto old=s.published_surfaces.find(s.key(coordinate));
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
        // Summed CPU work for published packets; detail_build_us is elapsed wall time.
        result["detailed_cpu_us"]=Vector3i(reconstruction_us,boundary_us,topology_us);
        result["sheet_level_general_packets"]=Vector3i(open_sheets,level_sections,general_packets);
        result["monotone_cells"]=monotone_cells;result["oblique_cells"]=oblique_cells;
        int64_t extracted=0,bytes=0,contacts=0,meshes=0,parallel_contacts=0,connected=0,indexed=0;
        for(int i=0;i<field_groups.size();++i){
            Dictionary group=field_groups[i];Ref<RefCounted> core=group["core"];
            if(!core->has_method("surface_column_stats"))continue;
            Dictionary stats=core->call("surface_column_stats");
            extracted+=int64_t(stats.get("columns",0));bytes+=int64_t(stats.get("bytes",0));
            contacts+=int64_t(stats.get("contacts",0));meshes+=int64_t(stats.get("meshes",0));
            parallel_contacts+=int64_t(stats.get("parallel_contact_packets",0));
            connected+=int64_t(stats.get("connected_columns",0));indexed+=int64_t(stats.get("indexed_contacts",0));
        }
        result["shared_surface_columns"]=extracted;result["shared_surface_bytes"]=bytes;
        result["shared_contact_reads"]=contacts;result["shared_mesh_reads"]=meshes;
        result["parallel_contact_packets"]=parallel_contacts;
        result["connected_terrain_columns"]=connected;result["indexed_contact_packets"]=indexed;
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
