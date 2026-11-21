// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <algorithm>
#include <cstring>

using namespace godot;
namespace terraforest {
bool NativeWaterEquilibriumJob::set_edit_field(const Array &groups,const AABB &bounds,const Dictionary &solids,int64_t rev,int64_t epoch){
    if(started.load()||frozen.is_null()||wide_edit_bounds.empty()||groups.is_empty()||groups.size()>9||
       !bounds.position.is_finite()||!bounds.size.is_finite()||!bounds.has_volume()||rev<0||epoch<0)return false;
    std::vector<FieldReader> readers;
    for(int i=0;i<groups.size();++i){
        if(groups[i].get_type()!=Variant::DICTIONARY)return false;
        Dictionary group=groups[i];
        if(!group.has("core")||!group.has("bounds")||group["bounds"].get_type()!=Variant::RECT2I)return false;
        FieldReader reader{group["bounds"],group["core"]};
        if(reader.core.is_null()||!reader.core->is_class("TerrainCore")||!reader.bounds.has_area())return false;
        readers.push_back(reader);
    }
    clear_structure_bounds=bounds;structure_hulls=solids;field_revision=rev;field_epoch=epoch;field_readers=std::move(readers);
    return true;
}

bool NativeWaterEquilibriumJob::prepare_receivers(){
    using W=NativeRegionalWater;
    auto defer=[&](const char *reason){receiver_fallback=reason;return false;};
    if(required.empty()||field_readers.empty()||cancelled.load())return defer(field_readers.empty()?"no field reader":"receiver admission");
    // Read-only preflight for the whole wave. In particular, a dry receiver
    // may bring another resident donor into the next capture's one-face halo.
    const Vector3i steps[]={{0,-1,0},{0,1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1}};
    struct Input {uint64_t key;Vector3i coord;Object *core;Array hulls;W::Region region;};
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
    // Prepare privately. Only validated geometry can be handed to the final
    // solve. A failed wave leaves the original dependency request intact.
    std::map<uint64_t,W::Region> staged;
    auto sample=[&](Input &input){
        PackedByteArray request;request.resize(24);request.encode_u32(0,48);
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
            // Terrain triangles are extracted in world coordinates. Preserve
            // absolute Y (the clipper evaluates millimetres in that frame).
            // X/Z are consumed relative to this owner by every contact path.
            for(uint32_t v=0;v<vertices;++v)for(int axis:{0,2}){
                const int offset=28+12*v+4*axis;
                identity.encode_float(offset,packet.decode_float(offset)-float(4*input.coord[axis]));
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
    frozen->regions.merge(staged);
    for(auto k:neighbours){
        auto node=receiver_neighbours.extract(k);
        for(auto ml:static_cast<const W::Region &>(node.mapped()).water)frozen->total+=ml;
        node.mapped().settle_pending=true;
        frozen->regions.insert(std::move(node));existing_outside.erase(k);
    }
    for(const auto &input:wave)prepared_receivers.push_back(input.key);
    required.clear();++private_rounds;
    return true;
}
}
