// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include "water_terrain_class.hpp"
#include "water_packet.hpp"
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
#include <cstring>

using namespace godot;
namespace terraforest {
// The old water head bounds discovery, not permanent residency. A deep cut
// can traverse thousands of dry cubes on the way to the new pool. After a
// successful solve, only wet quantities and their complete surface stencil
// require new owners. Other empty terrain is recoverable from the field.
void NativeWaterEquilibriumJob::retain_receiver_halo(const NativeRegionalWater &before){
    using W=NativeRegionalWater;
    if(!success||column_rooms==0||prepared_receivers.size()<32)return;
    std::unordered_set<uint64_t> keep;
    auto add_halo=[&](uint64_t k){
        const auto b=W::position(k);
        // The first dry cell above a wet column can own a reconstructed
        // face in its own mesh. Keep its one-brick halo too.
        for(int z=std::max(0,b.z-1);z<=std::min(499,b.z+1);++z)
            for(int y=std::max(0,b.y-1);y<=std::min(63,b.y+2);++y)
                for(int x=std::max(0,b.x-1);x<=std::min(499,b.x+1);++x)keep.insert(W::key({x,y,z}));
    };
    auto wet=[](const W::Region &r){
        return !r.water.is_initial_zero()&&std::any_of(r.water.begin(),r.water.end(),[](uint64_t ml){return ml!=0;});
    };
    std::unordered_set<uint64_t> sources;
    for(const auto &[k,r]:frozen->regions)if(wet(r))sources.insert(k);
    for(const auto &[k,r]:before.regions)if(wet(r))sources.insert(k);
    for(const auto &[k,surface]:before.published_surfaces)sources.insert(k);
    for(auto k:sources)add_halo(k);
    keep.insert(changed_regions.begin(),changed_regions.end());
    prepared_receivers.erase(std::remove_if(prepared_receivers.begin(),prepared_receivers.end(),[&](uint64_t k){
        const auto &r=frozen->regions.at(k);const auto b=W::position(k);
        // Missing coastal owners can supply reservoir water procedurally.
        if(r.structures||r.ocean_state||r.settle_pending||!r.vacancies.empty()||
                (before.surrounding_ocean&&std::min({b.x,b.z,499-b.x,499-b.z})<35))return false;
        return !keep.count(k);
    }),prepared_receivers.end());
}
bool NativeWaterEquilibriumJob::set_edit_field(const Array &groups,const AABB &bounds,const Dictionary &solids,int64_t rev,int64_t epoch){
    if(started.load()||frozen.is_null()||wide_edit_bounds.empty()||groups.is_empty()||groups.size()>9||
       !bounds.position.is_finite()||!bounds.size.is_finite()||!bounds.has_volume()||rev<0||epoch<0)return false;
    std::vector<FieldReader> readers;
    for(int i=0;i<groups.size();++i){
        if(groups[i].get_type()!=Variant::DICTIONARY)return false;
        Dictionary group=groups[i];
        if(!group.has("core")||!group.has("bounds")||group["bounds"].get_type()!=Variant::RECT2I)return false;
        FieldReader reader{group["bounds"],group["core"]};
        if(reader.core.is_null()||(!reader.core->is_class("TerrainFieldReader")&&!reader.core->is_class("TerrainCore"))||
           !reader.bounds.has_area())return false;
        readers.push_back(reader);
    }
    clear_structure_bounds=bounds;structure_hulls=solids;field_revision=rev;field_epoch=epoch;field_readers=std::move(readers);
    return true;
}

bool NativeWaterEquilibriumJob::prepare_receivers(){
    using W=NativeRegionalWater;
    const uint64_t start=Time::get_singleton()->get_ticks_usec();
    auto defer=[&](const char *reason){receiver_fallback=reason;return false;};
    if(required.empty()||field_readers.empty()||cancelled.load())return defer(field_readers.empty()?"no field reader":"receiver admission");
    expand_air_frontier();
    // Read-only preflight for the whole wave. In particular, a dry receiver
    // may bring another resident donor into the next capture's one-face halo.
    const Vector3i steps[]={{0,-1,0},{0,1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1}};
    struct Input {
        uint64_t key;Vector3i coord;Object *core;Array hulls;W::Region region;
        bool resolved=false;int representative=-1;
    };
    std::vector<Input> wave;wave.reserve(required.size());
    std::unordered_set<uint64_t> neighbours;
    for(uint64_t key:required){
        const auto p=W::position(key);
        if(frozen->regions.count(key))continue;
        const bool resident=receiver_neighbours.count(key)>0;
        if(existing_outside.count(key)&&!resident)return defer("external receiver");
        for(auto step:steps){
            const auto q=p+step;
            if(q.x<0||q.x>=500||q.z<0||q.z>=500||q.y<0||q.y>=64)continue;
            const auto n=W::key(q);
            if(receiver_neighbours.count(n))neighbours.insert(n);
            else if(existing_outside.count(n))return defer("external neighbour");
        }
        if(resident){neighbours.insert(key);continue;}
        if(!clear_structure_bounds.encloses(AABB(Vector3(p)*4,Vector3(4,4,4))))return defer("structure survey extent");
        // Unsurveyed sea is a reservoir. The normal ocean admission restores
        // its boundary quantities and stored holes.
        if(frozen->surrounding_ocean&&p.y>=7&&p.y<=10&&std::min({p.x,p.z,499-p.x,499-p.z})<35)return false;
        const Rect2i footprint(p.x*4,p.z*4,4,4);
        // capture_contact_core pins 32 m beyond its owners. Leave three
        // metres untouched on each side for the extraction stencil.
        auto owner=std::find_if(field_readers.begin(),field_readers.end(),[&](const FieldReader &r){return r.bounds.encloses(footprint);});
        if(owner==field_readers.end())owner=std::find_if(field_readers.begin(),field_readers.end(),[&](const FieldReader &r){return r.bounds.grow(29).encloses(footprint);});
        if(owner==field_readers.end())return defer("terrain field extent");
        if(structure_hulls.has(p)&&structure_hulls[p].get_type()!=Variant::ARRAY)return defer("paged structure occupancy");
        wave.push_back({key,p,owner->core.ptr(),structure_hulls.get(p,Array()),{}});
    }
    const size_t fixed=sizeof(W::Region)+W::Region::payload_bytes+512*sizeof(Vector3i)+128;
    if(wave.size()+prepared_receivers.size()>receiver_slots||wave.size()*fixed>=hierarchy_cell_limit*1024)return false;
    // One call per pinned field classifies a wave of previously absent receivers.
    // Both uniform regions retain the exact same water profile at every corner
    // and face. Mixed bricks and placed objects keep their actual terrain data.
    // No template contains quantity, and later edits detach their own ledger.
    std::map<LayerSignature,int> new_layers;
    for(const auto &field:field_readers){
        if(!field.core->has_method("classify_water_bricks"))continue;
        std::vector<int> indices;
        PackedInt32Array origins;
        for(size_t i=0;i<wave.size();++i){
            const auto &input=wave[i];
            if(input.core!=field.core.ptr()||!input.hulls.is_empty())continue;
            indices.push_back(int(i));
        }
        if(indices.empty())continue;
        std::vector<ReceiverClass> classes(indices.size());
        std::vector<size_t> missing;
        for(size_t j=0;j<indices.size();++j){
            auto cached=receiver_classes.find(wave[indices[j]].key);
            if(cached!=receiver_classes.end())classes[j]=cached->second;
            else missing.push_back(j);
        }
        for(size_t start=0;start<missing.size();start+=2048){
            const int count=int(std::min<size_t>(2048,missing.size()-start));
            if(origins.resize(3*count)!=OK)return false;
            auto *p=origins.ptrw();
            for(int i=0;i<count;++i){
                const auto &coord=wave[indices[missing[start+i]]].coord;
                for(int axis=0;axis<3;++axis)*p++=coord[axis]*4;
            }
            PackedByteArray result=classify_edit_bricks(field.core.ptr(),origins,field_revision,field_epoch);
            if(result.size()!=17*count)return defer("changed receiver field");
            const uint8_t *data=result.ptr();
            for(int i=0;i<count;++i)std::memcpy(classes[missing[start+i]].data(),data+17*i,17);
        }
        for(size_t j=0;j<indices.size();++j){
            const auto *record=classes[j].data();
            auto &input=wave[indices[j]];uint8_t type=record[0];
            if(!type)continue;
            if(type==3||type==4){
                auto signature=water_section_signature(record,input.coord.y);
                if(auto old=layered_receivers.find(signature);old!=layered_receivers.end()){
                    input.region=old->second;input.resolved=true;++reused_layered_receivers;
                }else if(new_layers.size()+layered_receivers.size()<512){
                    auto [entry,first]=new_layers.emplace(signature,indices[j]);
                    if(!first){input.representative=entry->second;++reused_layered_receivers;}
                }
                continue;
            }
            if(type>2)return defer("invalid receiver class");
            auto &model=homogeneous_receivers[type-1];
            if(!model.valid){
                std::array<uint16_t,512> floor,ceiling;std::array<float,729> density;
                floor.fill(type==1?0:500);ceiling.fill(500);density.fill(type==1?1.f:-1.f);
                model.floor=floor;model.ceiling=ceiling;model.density=density;
                model.has_density=true;model.valid=true;model.settle_pending=true;
                model.brick_geometry=type==1?WaterBrickGeometry::air:WaterBrickGeometry::solid;
            }
            input.resolved=true;input.region=model;++classified_receivers;
        }
    }
    // Prepare privately. Only validated geometry can be handed to the final
    // solve. A failed wave leaves the original dependency request intact.
    std::map<uint64_t,W::Region> staged;
    auto sample=[&](Input &input){
        if(input.resolved||input.representative>=0)return true;
        PackedByteArray request;request.resize(24);request.encode_u32(0,input.core->is_class("TerrainFieldReader")?49:48);
        request.encode_u32(4,field_revision);request.encode_u32(8,field_epoch);
        for(int axis=0;axis<3;++axis)request.encode_u32(12+4*axis,input.coord[axis]*4);
        PackedByteArray packet=input.core->call("execute",request);
        if(packet.size()<28||packet.decode_u32(8)||packet.decode_u32(12)!=field_revision||
           packet.decode_u32(16)!=field_epoch)return false;
        PackedByteArray identity;uint64_t hash=1469598103934665603ULL;
        const uint32_t opcode=packet.decode_u32(4),vertices=packet.decode_u32(20);
        if(input.hulls.is_empty()&&packet.size()<=32768&&(opcode==43||opcode==48)&&
           int64_t(vertices)*12<=packet.size()-28){
            identity=packet;
            auto *normalized=identity.ptrw();
            // Terrain triangles are extracted in world coordinates. Preserve
            // absolute Y (the clipper evaluates millimetres in that frame).
            // X/Z are consumed relative to this owner by every contact path.
            for(uint32_t v=0;v<vertices;++v)for(int axis:{0,2}){
                const int offset=28+12*v+4*axis;
                water_store_f32(normalized+offset,water_f32(normalized+offset)-float(4*input.coord[axis]));
            }
            const int height=opcode==43?input.coord.y:(input.coord.y==0?0:(input.coord.y==63?63:1));
            identity.push_back(height);
            const uint8_t *data=identity.ptr();int offset=0;
            for(;offset+8<=identity.size();offset+=8){
                uint64_t word;std::memcpy(&word,data+offset,8);hash=(hash^word)*1099511628211ULL;
            }
            for(;offset<identity.size();++offset)hash=(hash^data[offset])*1099511628211ULL;
            std::lock_guard<std::mutex> lock(template_mutex);
            auto range=receiver_templates.equal_range(hash);
            for(auto it=range.first;it!=range.second;++it)if(it->second.input==identity){
                input.region=it->second.region;++template_hits;return true;
            }
        }
        Ref<NativeWaterTerrainPatch> patch;patch.instantiate();
        if(!patch->configure(input.coord)||(!input.hulls.is_empty()&&!patch->set_structure_hulls(input.hulls)))return false;
        int64_t result;
        do{
            if(cancelled.load())return false;
            result=patch->sample_boundary(input.core,2048,field_revision,field_epoch,&packet);
        }while(result==0);
        if(result!=1)return false;
        auto &region=input.region;
        region.floor=patch->floor;region.ceiling=patch->ceiling;region.density=patch->density;
        region.contacts=patch->contacts;region.structures=patch->structures;
        region.has_density=true;region.valid=true;region.settle_pending=true;
        region.brick_geometry=patch->brick_geometry;
        region.index_intervals();
        if(!identity.is_empty()){
            std::lock_guard<std::mutex> lock(template_mutex);
            const size_t bytes=identity.size()+sizeof(ReceiverTemplate)+64;
            // Payloads are already charged to the prepared receiver retained
            // for this job. Charge the additional dictionary and its keys.
            if(template_bytes+bytes<=1024*1024){
                receiver_templates.emplace(hash,ReceiverTemplate{identity,region});template_bytes+=bytes;
            }
        }
        return true;
    };
    struct Work{
        decltype(sample) &sample_one;
        std::vector<Input> &inputs;
        uint64_t bytes_limit,solid_limit;
        std::atomic<uint64_t> bytes{0},solid{0};
        std::atomic<bool> failed{false};
    } work{sample,wave,hierarchy_cell_limit*1024-wave.size()*fixed,receiver_solid_limit-receiver_solid_bytes};
    auto run=[](void *data,uint32_t i){
        auto &group=*static_cast<Work*>(data);
        if(group.failed.load())return;
        if(!group.sample_one(group.inputs[i])){group.failed.store(true);return;}
        const auto &r=group.inputs[i].region;
        const uint64_t solids=r.structures?r.structures->bytes:0,bytes=solids+(r.contacts?r.contacts->bytes:0);
        if(group.bytes.fetch_add(bytes)+bytes>=group.bytes_limit||
           group.solid.fetch_add(solids)+solids>group.solid_limit)group.failed.store(true);
    };
    auto *pool=WorkerThreadPool::get_singleton();
    int64_t task=wave.size()>=12?pool->add_native_group_task(run,&work,int(wave.size()),3,true,"Terrain water receivers"):-1;
    if(task>=0)pool->wait_for_group_task_completion(task);
    else for(size_t i=0;i<wave.size()&&!work.failed.load();++i)run(&work,i);
    if(work.failed.load()||cancelled.load())return false;
    // The first brick of each stratum went through the full extractor, taking
    // its actual triangle intersections, contact ledger and density samples.
    // Identical inputs share only geometry. Their finite quantities are private.
    for(auto &input:wave)if(input.representative>=0)input.region=wave[input.representative].region;
    uint64_t extra=0,solid=0;
    for(auto &input:wave){
        const auto &r=input.region;
        extra+=fixed+(r.contacts?r.contacts->bytes:0)+(r.structures?r.structures->bytes:0);
        solid+=r.structures?r.structures->bytes:0;
        if(extra>=hierarchy_cell_limit*1024||receiver_solid_bytes+solid>receiver_solid_limit)return false;
        staged.emplace(input.key,std::move(input.region));
    }
    receiver_bytes+=extra;receiver_solid_bytes+=solid;
    hierarchy_cell_limit-=(extra+1023)/1024;
    cell_limit=std::min(cell_limit,4*hierarchy_cell_limit);
    for(const auto &[signature,index]:new_layers)layered_receivers.emplace(signature,staged.at(wave[index].key));
    frozen->regions.merge(staged);
    for(auto k:neighbours){
        auto node=receiver_neighbours.extract(k);
        for(auto ml:static_cast<const W::Region &>(node.mapped()).water)frozen->total+=ml;
        node.mapped().settle_pending=true;
        frozen->regions.insert(std::move(node));existing_outside.erase(k);
    }
    for(const auto &input:wave)prepared_receivers.push_back(input.key);
    required.clear();++private_rounds;
    receiver_us+=Time::get_singleton()->get_ticks_usec()-start;
    return true;
}
}
