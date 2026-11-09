#include "block_horizon.hpp"
#include <godot_cpp/classes/array_mesh.hpp>
#include <chrono>
#include <cstring>

namespace terraforest {
BlockHorizon::~BlockHorizon() {
    ++serial;
    if(read_ticket&&archive.is_valid())archive->discard_survey_region_read(read_ticket);
    {std::lock_guard<std::mutex> lock(mutex);stopping=true;}
    wake.notify_all();if(worker.joinable())worker.join();
}
void BlockHorizon::erase(BlockKey key) {
    auto found=visuals.find(key);if(found==visuals.end())return;
    bytes-=found->second.bytes;memdelete(found->second.instance);visuals.erase(found);
}
void BlockHorizon::reset() {
    ++serial;
    if(read_ticket&&archive.is_valid())archive->discard_survey_region_read(read_ticket);
    read_ticket=0;regions.clear();failed=0;blocked=0;
    while(!visuals.empty())erase(visuals.begin()->first);
    seen_mutation=UINT64_MAX;wake.notify_all();
}
void BlockHorizon::set_enabled(bool value) {
    if(enabled==value)return;
    enabled=value;reset();
    if(enabled&&!root){root=memnew(Node3D);root->set_name("DistantBuildings");world.add_child(root);}
}
void BlockHorizon::set_archive(const Ref<NativeRegionWorldArchive> &value,const PackedByteArray &pin) {
    if(archive!=value) {
        if(read_ticket&&archive.is_valid())archive->discard_survey_region_read(read_ticket);
        read_ticket=0;archive=value;
    }
    checkpoint=pin;
}
void BlockHorizon::invalidate(BlockKey key) {
    if(!enabled)return;
    auto &region=regions[NativeBlockWorld::region_for(key)];++region.version;region.ready=false;region.retry=0;
    if(!world.chunks.count(key)&&!world.unloaded_regions.count(NativeBlockWorld::region_for(key)))erase(key);
    seen_mutation=UINT64_MAX;
}
void BlockHorizon::near_changed(BlockKey key) {
    auto found=visuals.find(key);if(found!=visuals.end())found->second.instance->set_visible(!world.visuals.count(key));
}
void BlockHorizon::retain(BlockKey key,const BlockVisual &visual) {
    if(!enabled||visuals.count(key)||!world.chunks.count(key)&&!world.unloaded_regions.count(NativeBlockWorld::region_for(key)))return;
    if(bytes+visual.payload_bytes>BYTE_LIMIT){++blocked;return;}
    auto *instance=memnew(MeshInstance3D);instance->set_mesh(visual.mesh->get_mesh());
    instance->set_position(visual.mesh->get_position());instance->set_lod_bias(.01f);root->add_child(instance);
    visuals[key]={instance,visual.payload_bytes,visual.lod_min_triangles};bytes+=visual.payload_bytes;
}
void BlockHorizon::sync() {
    if(seen_epoch!=world.storage_epoch){reset();seen_epoch=world.storage_epoch;}
    if(seen_mutation==world.mutation_revision)return;
    seen_mutation=world.mutation_revision;
    std::set<BlockKey> logical;
    for(const auto &entry:world.chunks)logical.insert(NativeBlockWorld::region_for(entry.first));
    for(const auto &entry:world.unloaded_regions)logical.insert(entry.first);
    for(auto key:logical)regions.try_emplace(key);
    for(auto iterator=regions.begin();iterator!=regions.end();) {
        if(logical.count(iterator->first)){++iterator;continue;}
        const BlockKey key=iterator->first;iterator=regions.erase(iterator);
        for(int depth=0;depth<4;++depth)for(int height=0;height<4;++height)for(int width=0;width<4;++width)
            erase({key.x*4+width,key.y*4+height,key.z*4+depth});
    }
}
void BlockHorizon::start(std::map<BlockKey,BlockChunk> &&chunks,std::shared_ptr<const BlockMapRegionData> packet) {
    if(!worker.joinable())worker=std::thread(&BlockHorizon::run,this);
    {std::lock_guard<std::mutex> lock(mutex);source=std::move(chunks);decoded=std::move(packet);pending=true;}
    active=true;wake.notify_all();
}
bool BlockHorizon::deliver(BlockBake &&bake,bool last,uint64_t ticket,const std::set<BlockKey> &keys) {
    const uint64_t charge=bake.payload_bytes()+keys.size()*sizeof(BlockKey);
    std::unique_lock<std::mutex> lock(mutex);
    // Bounded lookahead decouples native baking from the display frame rate.
    // One legal chunk is always admissible; subsequent results share the quota.
    wake.wait(lock,[&]{return stopping||(!last&&ticket!=serial)||(completed.size()<RESULT_LIMIT&&(completed.empty()||result_bytes+charge<=RESULT_BYTES));});
    if(stopping||(!last&&ticket!=serial))return false;
    completed.push_back({std::move(bake),last,keys,charge});result_bytes+=charge;
    peak_results=std::max(peak_results,completed.size());peak_result_bytes=std::max(peak_result_bytes,result_bytes);
    wake.notify_all();return true;
}
void BlockHorizon::run() {
    for(;;) {
        std::map<BlockKey,BlockChunk> chunks;std::shared_ptr<const BlockMapRegionData> packet;BlockKey region;uint64_t ticket;
        {
            std::unique_lock<std::mutex> lock(mutex);wake.wait(lock,[&]{return stopping||pending;});if(stopping)return;
            chunks=std::move(source);packet=std::move(decoded);region=active_region;ticket=active_serial;pending=false;
        }
        const auto &cells=packet?packet->chunks:chunks;
        std::set<BlockKey> keys;
        for(const auto &entry:cells) {
            const auto key=entry.first,owner=NativeBlockWorld::region_for(key);
            if(owner<region||region<owner)continue;
            if(ticket!=serial)break;
            keys.insert(key);std::array<uint16_t,5832> halo{};
            for(int depth=-1;depth<=16;++depth)for(int height=-1;height<=16;++height)for(int width=-1;width<=16;++width) {
                const int cell_x=key.x*16+width,cell_y=key.y*16+height,cell_z=key.z*16+depth;
                auto found=cells.find(NativeBlockWorld::key_for(cell_x,cell_y,cell_z));
                if(found!=cells.end())halo[width+1+18*(height+1+18*(depth+1))]=found->second.cells[NativeBlockWorld::index(cell_x,cell_y,cell_z)];
            }
            BlockBake bake=NativeBlockWorld::bake(key,ticket,halo);bake_block_lods(bake);
            if(!bake.lods.empty())bake.indices=std::move(bake.lods.back().indices);
            bake.lods.clear();
            std::vector<BlockVertex> original=std::move(bake.vertices);std::vector<int32_t> remap(original.size(),-1);
            for(auto &index:bake.indices){if(remap[index]<0){remap[index]=int32_t(bake.vertices.size());bake.vertices.push_back(original[index]);}index=remap[index];}
            if(!deliver(std::move(bake),false,ticket))break;
        }
        BlockBake finish;finish.revision=ticket;if(!deliver(std::move(finish),true,ticket,keys))return;
    }
}
void BlockHorizon::publish(BlockBake &&bake) {
    const uint64_t payload=bake.payload_bytes();auto old=visuals.find(bake.key);
    if(bytes-(old==visuals.end()?0:old->second.bytes)+payload>BYTE_LIMIT){++blocked;regions[active_region].retry=ticks+600;return;}
    erase(bake.key);if(bake.indices.empty())return;
    world.ensure_material();
    for(const auto &vertex:bake.vertices)if((int(vertex.material)&15)>=4){if(!world.ensure_appearances())return;break;}
    PackedVector3Array vertices,normals;PackedVector2Array uv,uv2;PackedInt32Array indices;
    vertices.resize(bake.vertices.size());normals.resize(bake.vertices.size());uv.resize(bake.vertices.size());uv2.resize(bake.vertices.size());
    for(size_t index=0;index<bake.vertices.size();++index){const auto &vertex=bake.vertices[index];vertices.set(index,Vector3(vertex.x,vertex.y,vertex.z));normals.set(index,Vector3(vertex.nx,vertex.ny,vertex.nz));uv.set(index,Vector2(vertex.u,vertex.v));uv2.set(index,Vector2(vertex.material,0));}
    indices.resize(bake.indices.size());std::memcpy(indices.ptrw(),bake.indices.data(),bake.indices.size()*sizeof(int32_t));
    Array arrays;arrays.resize(Mesh::ARRAY_MAX);arrays[Mesh::ARRAY_VERTEX]=vertices;arrays[Mesh::ARRAY_NORMAL]=normals;arrays[Mesh::ARRAY_TEX_UV]=uv;arrays[Mesh::ARRAY_TEX_UV2]=uv2;arrays[Mesh::ARRAY_INDEX]=indices;
    Ref<ArrayMesh> mesh;mesh.instantiate();mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,arrays);mesh->surface_set_material(0,world.material);
    auto *instance=memnew(MeshInstance3D);instance->set_mesh(mesh);instance->set_position(Vector3(bake.key.x*16,bake.key.y*16,bake.key.z*16));root->add_child(instance);
    visuals[bake.key]={instance,payload,int(bake.indices.size()/3)};bytes+=payload;++published;near_changed(bake.key);
}
void BlockHorizon::step() {
    ++ticks;if(enabled)sync();
    const auto began=std::chrono::steady_clock::now();last_step_uploads=0;
    // Keep a small main-thread upload slice; consume ready work instead of
    // forcing every individual worker result to wait for another whole frame.
    for(int slot=0;slot<4;++slot) {
        Completion item;
        {
            std::lock_guard<std::mutex> lock(mutex);
            if(completed.empty())break;
            item=std::move(completed.front());completed.pop_front();result_bytes-=item.charge;
        }
        wake.notify_all();auto region=regions.find(active_region);
        const bool valid=enabled&&item.bake.revision==serial&&region!=regions.end()&&region->second.version==active_version;
        if(valid) {
            if(item.last) {
                for(int depth=0;depth<4;++depth)for(int height=0;height<4;++height)for(int width=0;width<4;++width){BlockKey key{active_region.x*4+width,active_region.y*4+height,active_region.z*4+depth};if(!item.keys.count(key))erase(key);}
                region->second.ready=region->second.retry==0;
            } else {
                const auto begin=std::chrono::steady_clock::now();publish(std::move(item.bake));++last_step_uploads;
                upload_max_ms=std::max(upload_max_ms,std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count());
            }
        } else ++rejected;
        if(item.last){active=false;break;}
        if(std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-began).count()>=1000)break;
    }
    max_step_uploads=std::max(max_step_uploads,last_step_uploads);
    if(!enabled||active)return;
    if(read_ticket) {
        Dictionary response=archive->take_survey_region_read(read_ticket);if(response.is_empty())return;read_ticket=0;
        auto region=regions.find(active_region);auto unloaded=world.unloaded_regions.find(active_region);
        if(active_serial!=serial||region==regions.end()||region->second.version!=active_version||unloaded==world.unloaded_regions.end()||unloaded->second!=read_digest){++rejected;return;}
        Ref<NativeBlockMapRegion> packet=response.get("survey",Variant());
        if(!bool(response.get("ok",false))||packet.is_null()){++failed;region->second.retry=ticks+600;return;}
        start({},packet->data_);return;
    }
    auto selected=regions.end();double closest=1e300;
    for(auto iterator=regions.begin();iterator!=regions.end();++iterator) {
        if(iterator->second.ready||iterator->second.retry>ticks)continue;
        if(world.unloaded_regions.count(iterator->first)&&archive.is_null())continue;
        const auto key=iterator->first;const double distance=Vector3(key.x*64+32,key.y*64+32,key.z*64+32).distance_squared_to(world.focus);
        if(distance<closest){closest=distance;selected=iterator;}
    }
    if(selected==regions.end())return;
    active_region=selected->first;active_version=selected->second.version;active_serial=serial;selected->second.retry=0;
    auto unloaded=world.unloaded_regions.find(active_region);
    if(unloaded!=world.unloaded_regions.end()) {
        read_digest=unloaded->second;
        read_ticket=archive->request_survey_region_read(Vector3i(active_region.x,active_region.y,active_region.z),read_digest,checkpoint,int64_t(active_serial));return;
    }
    std::map<BlockKey,BlockChunk> captured;
    for(int depth=-1;depth<=4;++depth)for(int height=-1;height<=4;++height)for(int width=-1;width<=4;++width){BlockKey key{active_region.x*4+width,active_region.y*4+height,active_region.z*4+depth};auto found=world.chunks.find(key);if(found!=world.chunks.end())captured.emplace(key,found->second);}
    start(std::move(captured));
}
Dictionary BlockHorizon::stats() const {
    int complete=0,visible=0,triangles=0;for(const auto &entry:regions)complete+=entry.second.ready;
    for(const auto &entry:visuals){visible+=entry.second.instance->is_visible();triangles+=entry.second.triangles;}
    Dictionary out;out["enabled"]=enabled;out["regions"]=int(regions.size());out["ready_regions"]=complete;out["ready"]=enabled&&seen_mutation==world.mutation_revision&&complete==int(regions.size())&&!active&&!read_ticket;
    out["mesh_chunks"]=int(visuals.size());out["visible_chunks"]=visible;out["triangles"]=triangles;out["mesh_bytes"]=int64_t(bytes);out["byte_limit"]=int64_t(BYTE_LIMIT);
    {std::lock_guard<std::mutex> lock(mutex);out["queued_results"]=int(completed.size());out["queued_bytes"]=int64_t(result_bytes);out["peak_queued_results"]=int(peak_results);out["peak_queued_bytes"]=int64_t(peak_result_bytes);}
    out["queue_result_limit"]=int(RESULT_LIMIT);out["queue_byte_limit"]=int64_t(RESULT_BYTES);out["last_step_uploads"]=last_step_uploads;out["max_step_uploads"]=max_step_uploads;
    out["worker_active"]=active;out["read_pending"]=read_ticket!=0;out["published_chunks"]=int64_t(published);out["stale_results"]=int64_t(rejected);out["failed_reads"]=int64_t(failed);out["budget_rejections"]=int64_t(blocked);out["upload_max_ms"]=upload_max_ms;return out;
}
void NativeBlockWorld::set_distant_rendering_enabled(bool enabled) {
    if(!horizon)horizon=new BlockHorizon(*this);horizon->set_enabled(enabled);set_process(true);
}
Dictionary NativeBlockWorld::distant_rendering_stats() const {
    if(horizon)return horizon->stats();Dictionary out;out["enabled"]=false;out["ready"]=false;return out;
}
void NativeBlockWorld::set_distant_archive(const Ref<NativeRegionWorldArchive> &archive,const PackedByteArray &checkpoint) {
    if(horizon)horizon->set_archive(archive,checkpoint);
}
}
