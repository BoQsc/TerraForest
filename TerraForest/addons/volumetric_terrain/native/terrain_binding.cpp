// SPDX-License-Identifier: 0BSD
#include "core.h"
#include "survey_map.hpp"
#include "terrain_planner.hpp"
#include "road_profile.hpp"
#include "terrain_collision.hpp"
#include "terrain_region_store.hpp"
#include "terrain_capture.hpp"
#include "terrain_residency.hpp"
#include "generation_bake_progress.hpp"
#include "geometry_content_key.hpp"
#include "experimental/snapshot_worker.hpp"
#include "experimental/godot_surface_mesh.hpp"
#include "experimental/mesh_partition.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <optional>
#include <cstdlib>
#include <atomic>
#include <mutex>
#include <chrono>
#include <memory>

namespace terraforest {
godot::PackedByteArray render_generation_map(const godot::PackedByteArray &,const godot::Array &,const godot::Array &,const godot::PackedByteArray &);
godot::Dictionary plan_regional_route(const World &,godot::Vector3,godot::Vector3,const godot::Array &);
godot::Dictionary fit_generated_road_network(const World &,const godot::Array &,const godot::Array &);
godot::Dictionary plan_region_network(const World &,const godot::Array &,const godot::Array &,bool,int,int64_t,const godot::Array &);
godot::Dictionary plan_settlement_lots(const World &,godot::Vector3,const godot::Array &,const godot::Array &,bool);
godot::Dictionary plan_street_network(const World &,const godot::Array &,const godot::PackedVector3Array &);
godot::Dictionary normalize_generated_roads(const World &,const godot::Array &,const godot::Array &);
godot::Dictionary fit_generated_lakes(const World &,const godot::Array &);
godot::Dictionary survey_generated_lake_surfaces(const World &,const godot::Array &);
class TerrainCore : public godot::RefCounted {
    GDCLASS(TerrainCore, godot::RefCounted)
    BuildControl control_;
    World world_;
    std::unique_ptr<TerrainResidency> residency_;
    GenerationBakeProgress generation_progress_;
    uint64_t storage_epoch_=1;
    godot::PackedInt32Array saved_keys_;
    godot::PackedInt64Array saved_versions_;
    godot::PackedByteArray storage_reference_;
    bool storage_load_pending_=false;
    uint32_t storage_load_checksum_=0;
    int storage_load_revision_=0;

    std::mutex mutex_;
    std::atomic<int64_t> active_command_{-1};
    std::atomic<u64> snapshot_epoch_{0};
    std::optional<experimental::SnapshotWorker> snapshot_worker_;
    struct SubmitTiming{int64_t token=-1;bool accepted=false;double total_ms=0,world_lock_ms=0,startup_ms=0,world_unlock_ms=0;experimental::SnapshotWorker::SubmitTiming worker;};
    SubmitTiming last_submit_;
    std::mutex submit_timing_mutex_;
    static godot::PackedByteArray reply(uint32_t command, uint32_t status, uint32_t value=0, bool include_value=false) {
        godot::PackedByteArray result;
        result.resize(include_value ? 16 : 12);
        result.encode_u32(0,REPLY_MAGIC); result.encode_u32(4,command); result.encode_u32(8,status);
        if(include_value)result.encode_u32(12,value);
        return result;
    }
protected:
    static void _bind_methods() {
        godot::ClassDB::bind_method(godot::D_METHOD("execute","packet"), &TerrainCore::execute);
        godot::ClassDB::bind_method(godot::D_METHOD("capture_storage_snapshot"),&TerrainCore::capture_storage_snapshot);
        godot::ClassDB::bind_method(godot::D_METHOD("commit_storage_snapshot","capture","checkpoint"),&TerrainCore::commit_storage_snapshot);
        godot::ClassDB::bind_method(godot::D_METHOD("configure_storage_checkpoint","checkpoint","checksum"),&TerrainCore::configure_storage_checkpoint);
        godot::ClassDB::bind_method(godot::D_METHOD("mount_storage_checkpoint","directory","checkpoint","resident_limit"),&TerrainCore::mount_storage_checkpoint,DEFVAL(MAX_PAGES));
        godot::ClassDB::bind_method(godot::D_METHOD("residency_stats"),&TerrainCore::residency_stats);

        godot::ClassDB::bind_method(godot::D_METHOD("plan_regional_route","start","finish","reservations"), &TerrainCore::plan_route);
        godot::ClassDB::bind_method(godot::D_METHOD("plan_region_network","districts","reservations","loops","trails","seed","streets"), &TerrainCore::plan_network,DEFVAL(godot::Array()));
        godot::ClassDB::bind_method(godot::D_METHOD("render_plan_map","pixels","roads","lots","water"), &TerrainCore::render_plan_map,DEFVAL(godot::PackedByteArray()));
        godot::ClassDB::bind_method(godot::D_METHOD("plan_lots","center","lots","roads","default_streets"), &TerrainCore::plan_lots);
        godot::ClassDB::bind_method(godot::D_METHOD("fit_generated_lakes","records"), &TerrainCore::fit_lakes);
        godot::ClassDB::bind_method(godot::D_METHOD("plan_streets","roads","junctions"), &TerrainCore::plan_streets);
        godot::ClassDB::bind_method(godot::D_METHOD("normalize_roads","roads","protected_areas"), &TerrainCore::normalize_roads);
        godot::ClassDB::bind_method(godot::D_METHOD("fit_road_network","roads","protected_areas"), &TerrainCore::fit_road_network);
        godot::ClassDB::bind_method(godot::D_METHOD("survey_overview","size"), &TerrainCore::survey_overview);
        godot::ClassDB::bind_method(godot::D_METHOD("survey_water_visibility","points"), &TerrainCore::survey_water_visibility);
        godot::ClassDB::bind_method(godot::D_METHOD("bake_generated_earthworks","packets"), &TerrainCore::bake_generated_earthworks);
        godot::ClassDB::bind_method(godot::D_METHOD("bake_generated_earthworks_staged","packets","directory","resident_limit","checkpoint_commands","expected_epoch","test_stop_at_checkpoint"), &TerrainCore::bake_generated_earthworks_staged,DEFVAL(MAX_PAGES),DEFVAL(64),DEFVAL(-1),DEFVAL(-1));
        godot::ClassDB::bind_method(godot::D_METHOD("generation_bake_progress"),&TerrainCore::generation_bake_progress);
        godot::ClassDB::bind_method(godot::D_METHOD("survey_generated_lake_surfaces","records"), &TerrainCore::survey_generated_lake_surfaces);
        godot::ClassDB::bind_method(godot::D_METHOD("survey_patch","size","x","z","width","height"), &TerrainCore::survey_patch);
        godot::ClassDB::bind_method(godot::D_METHOD("measure_material_surface","x","z","size","y_begin","y_end"), &TerrainCore::measure_material_surface);
        godot::ClassDB::bind_method(godot::D_METHOD("material_box","solid","minimum","maximum","add","solid_revision","material_revision"), &TerrainCore::material_box, DEFVAL(-1));
        godot::ClassDB::bind_method(godot::D_METHOD("geometry_cache_key","x","z","size","step"), &TerrainCore::geometry_cache_key);
        godot::ClassDB::bind_method(godot::D_METHOD("build_owned_region","x","z","size","step","y_begin","y_end","epoch"), &TerrainCore::build_owned_region);
        godot::ClassDB::bind_method(godot::D_METHOD("supports_isolated_worlds"), &TerrainCore::supports_isolated_worlds);
        godot::ClassDB::bind_method(godot::D_METHOD("build_variant"), &TerrainCore::build_variant);
        godot::ClassDB::bind_method(godot::D_METHOD("executing_command"), &TerrainCore::executing_command);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_submit","x","z","size","token","revision"), &TerrainCore::experimental_snapshot_submit);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_submit_brick","x","z","size","token","revision","y_begin","y_end"), &TerrainCore::experimental_snapshot_submit_brick);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_poll"), &TerrainCore::experimental_snapshot_poll);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_stop"), &TerrainCore::experimental_snapshot_stop);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_submit_timing"), &TerrainCore::experimental_snapshot_submit_timing);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_create_mesh","packet"), &TerrainCore::experimental_snapshot_create_mesh);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_encode","packet","x","z","size"), &TerrainCore::experimental_snapshot_encode);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_encode_brick","packet","x","z","size"), &TerrainCore::experimental_snapshot_encode_brick);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_partition_mesh","packet"), &TerrainCore::experimental_partition_mesh);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_partition_mesh_budgeted","packet","workspace_bytes","output_bytes","expected_epoch"), &TerrainCore::experimental_partition_mesh_budgeted);
    }
public:
    godot::Dictionary fit_road_network(const godot::Array &roads,const godot::Array &protected_areas){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=fit_generated_road_network(world_,roads,protected_areas);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary normalize_roads(const godot::Array &roads,const godot::Array &protected_areas){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=normalize_generated_roads(world_,roads,protected_areas);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary plan_network(const godot::Array &districts,const godot::Array &reservations,bool loops,int trails,int64_t seed,const godot::Array &streets=godot::Array()){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=plan_region_network(world_,districts,reservations,loops,trails,seed,streets);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary fit_lakes(const godot::Array &records){std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=fit_generated_lakes(world_,records);return tr_oom?godot::Dictionary():result;}
    godot::Dictionary plan_route(godot::Vector3 start,godot::Vector3 finish,const godot::Array &reservations){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=plan_regional_route(world_,start,finish,reservations);return tr_oom?godot::Dictionary():result;
    }
    godot::PackedByteArray render_plan_map(const godot::PackedByteArray &pixels,const godot::Array &roads,const godot::Array &lots,const godot::PackedByteArray &water=godot::PackedByteArray()){return render_generation_map(pixels,roads,lots,water);}
    godot::Dictionary plan_lots(godot::Vector3 center,const godot::Array &lots,const godot::Array &roads,bool default_streets){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=plan_settlement_lots(world_,center,lots,roads,default_streets);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary plan_streets(const godot::Array &roads,const godot::PackedVector3Array &junctions){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=plan_street_network(world_,roads,junctions);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary survey_water_visibility(const godot::PackedVector3Array &points){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=terraforest_survey_water_visibility(world_,points);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary survey_patch(int64_t size,int64_t x,int64_t z,int64_t width,int64_t height){
        if(size<64||size>512||x<0||z<0||x>=size||z>=size||width<1||height<1||width>4||height>4)return {};
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=terraforest_survey_patch(world_,int(size),int(x),int(z),int(width),int(height));return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary survey_overview(int64_t size){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=terraforest_survey_map(world_,size);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary measure_material_surface(int64_t x,int64_t z,int64_t size,int64_t y_begin,int64_t y_end){
        godot::Dictionary result;result["valid"]=false;
        if(x<0||x>WORLD||z<0||z>WORLD||size<1||size>32||y_begin<1||y_end>255||y_end<=y_begin||y_end-y_begin>32)return result;
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;
        double integral=0;int triangles=0;bool closed=false;
        if(!::measure_material_surface(world_,int(x),int(z),int(size),int(y_begin),int(y_end),integral,triangles,closed))return result;
        result["valid"]=true;result["signed_integral_m3"]=integral;result["closed"]=closed;
        result["triangles"]=triangles;result["revision"]=world_.revision;
        // An open patch's origin-dependent integral is not its physical volume.
        if(closed)result["volume_m3"]=integral<0?-integral:integral;
        return result;
    }
    godot::Dictionary material_box(const godot::Ref<TerrainCore>&solid,godot::Vector3 minimum,godot::Vector3 maximum,bool add,int64_t solid_revision,int64_t material_revision=-1){
        godot::Dictionary result;result["accepted"]=false;result["changes"]=0;
        if(solid.is_null()||solid.ptr()==this)return result;
        // A single lock transaction prevents terrain changes between exclusion and commit.
        std::scoped_lock lock(mutex_,solid->mutex_);
        if(solid_revision!=solid->world_.revision||(material_revision>=0&&material_revision!=world_.revision))return result;
        tr_oom=false;V3 lo,hi;int changes=0;
        bool ok=world_.material_box(solid->world_,{float(minimum.x),float(minimum.y),float(minimum.z)},
            {float(maximum.x),float(maximum.y),float(maximum.z)},add,lo,hi,changes);
        if(changes)snapshot_epoch_.fetch_add(1);
        result["accepted"]=ok;result["changes"]=changes;result["revision"]=world_.revision;
        result["solid_revision"]=solid->world_.revision;
        if(ok){result["minimum"]=godot::Vector3(lo.x,lo.y,lo.z);result["maximum"]=godot::Vector3(hi.x,hi.y,hi.z);}
        return result;
    }
    godot::PackedByteArray build_owned_region(int64_t x,int64_t z,int64_t size,int64_t step,int64_t y_begin,int64_t y_end,int64_t epoch){
        if(x<0||z<0||x>=2048||z>=2048||size<16||size>64||step<1||step>8||y_begin<0||y_end>WORLD_Y||epoch<0||epoch>0xffffffffLL)return {};
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;
        Mesh mesh;Bytes bytes;godot::PackedByteArray result;
        if(::build_owned_region(world_,int(x),int(z),int(size),int(step),int(y_begin),int(y_end),mesh,u32(epoch))){
            encode_mesh(mesh,int(x),int(z),int(size),int(step),bytes);
            if(!tr_oom&&terrain_build_epoch(&world_)==u32(epoch)){
                result.resize(bytes.n);if(bytes.n)copy_bytes(result.ptrw(),bytes.p,bytes.n);
            }
        }
        mesh.release();bytes.release();return result;
    }
    godot::Dictionary geometry_cache_key(int64_t x,int64_t z,int64_t size,int64_t step) {
        if(x<0||z<0||x>=2048||z>=2048||size<16||size>256||step<1||step>8)return {};
        std::lock_guard<std::mutex> lock(mutex_);
        tr_oom=false;auto result=terraforest::geometry_content_key(world_,int(x),int(z),int(size),int(step));return tr_oom?godot::Dictionary():result;
    }
    TerrainCore() {world_.build_control=&control_; tr_oom=false; world_.init();}
    ~TerrainCore() {snapshot_worker_.reset();world_.release();}
    godot::Dictionary experimental_partition_mesh_budgeted(const godot::PackedByteArray&packet,int64_t workspace,int64_t output,int64_t expected){
        godot::Dictionary result;result["packets"]=godot::Array();result["workspace_peak"]=0;result["denied"]=0;result["cancelled"]=false;
        if(workspace<1||workspace>128*1024*1024||output<1||output>128*1024*1024||expected<0||expected>0xffffffffLL)return result;
        struct Context{BuildControl*control;u32 epoch;}context{&control_,u32(expected)};
        experimental::PartitionLimits limits;limits.workspace_bytes=size_t(workspace);limits.output_bytes=size_t(output);limits.context=&context;
        limits.cancelled=[](void*p){auto*c=static_cast<Context*>(p);return __atomic_load_n(&c->control->epoch,__ATOMIC_RELAXED)!=c->epoch;};
        experimental::PartitionStats stats;
        result["packets"]=experimental::partition_mesh(packet,limits,&stats);result["workspace_peak"]=int64_t(stats.workspace_peak);result["denied"]=int64_t(stats.denied);result["cancelled"]=stats.cancelled;return result;
    }
    godot::Array experimental_partition_mesh(const godot::PackedByteArray&packet){
        return experimental_partition_mesh_budgeted(packet,128*1024*1024,128*1024*1024,__atomic_load_n(&control_.epoch,__ATOMIC_RELAXED))["packets"];
    }
    godot::PackedByteArray experimental_snapshot_encode(const godot::Dictionary&packet,int64_t x,int64_t z,int64_t size){
        // The legacy column codec adds full-height blocks and owns a column.
        // Bounded surfaces must not be published through it as complete columns.
        if(int64_t(packet.get("y_begin",0))!=0||int64_t(packet.get("y_end",WORLD_Y))!=WORLD_Y)return {};
        return encode_snapshot_surface(packet,x,z,size,0,WORLD_Y);
    }
    godot::Dictionary experimental_snapshot_encode_brick(const godot::Dictionary&packet,int64_t x,int64_t z,int64_t size){
        for(const char*key:{"y_begin","y_end"})if(!packet.has(key)||godot::Variant(packet[key]).get_type()!=godot::Variant::INT)return {};
        int64_t begin=packet["y_begin"],end=packet["y_end"];
        if(begin<0||begin>=end||end>WORLD_Y)return {};
        auto bytes=encode_snapshot_surface(packet,x,z,size,int(begin),int(end));if(bytes.is_empty())return {};
        godot::Dictionary result;result["packet"]=bytes;
        result["origin"]=godot::Vector3i(int(x),int(begin),int(z));result["extent"]=godot::Vector3i(int(size),int(end-begin),int(size));
        result["epoch"]=packet["epoch"];result["revision"]=packet["validated_revision"];return result;
    }
private:
    godot::PackedByteArray encode_snapshot_surface(const godot::Dictionary&packet,int64_t x,int64_t z,int64_t size,int y_begin,int y_end){
        if(x<0||z<0||(size!=16&&size!=32)||x>WORLD-size||z>WORLD-size)return {};
        for(const char*key:{"status","epoch","validated_revision","source_id"})
            if(!packet.has(key)||godot::Variant(packet[key]).get_type()!=godot::Variant::INT)return {};
        if(int64_t(packet["status"])!=0||bool(packet.get("stale",true))||int64_t(packet["source_id"])!=int64_t(get_instance_id()))return {};
        auto arrays=experimental::surface_arrays(packet);if(arrays.is_empty())return {};
        godot::PackedVector3Array positions=arrays[godot::Mesh::ARRAY_VERTEX],normals=arrays[godot::Mesh::ARRAY_NORMAL];
        godot::PackedInt32Array indices=arrays[godot::Mesh::ARRAY_INDEX];
        std::lock_guard<std::mutex> lock(mutex_);
        if(int64_t(packet["validated_revision"])!=world_.revision||int64_t(packet["epoch"])<0||u64(int64_t(packet["epoch"]))!=snapshot_epoch_.load())return {};
        const u32 build_epoch=terrain_build_epoch(&world_);tr_oom=false;
        Mesh mesh;mesh.v.resize(int(positions.size()));mesh.i.resize(int(indices.size()));
        if(tr_oom){mesh.release();return {};}
        for(int at=0;at<positions.size();at++){
            auto p=positions[at],n=normals[at];
            if(p.x<x||p.x>x+size||p.z<z||p.z>z+size||p.y<y_begin||p.y>y_end){mesh.release();return {};}
            mesh.v[at].p={float(p.x),float(p.y),float(p.z)};mesh.v[at].n={float(n.x),float(n.y),float(n.z)};
        }
        for(int at=0;at<indices.size();at++)mesh.i[at]=u32(indices[at]);
        add_blocks(world_,int(x),int(z),int(size),mesh,y_begin,y_end);
        if(!tr_oom)shade_mesh(world_,mesh,build_epoch);
        Bytes encoded;
        if(!tr_oom&&build_epoch==terrain_build_epoch(&world_))encode_mesh(mesh,int(x),int(z),int(size),1,encoded);
        godot::PackedByteArray result;
        if(!tr_oom&&u64(int64_t(packet["epoch"]))==snapshot_epoch_.load()&&result.resize(encoded.n)==godot::OK&&encoded.n)copy_bytes(result.ptrw(),encoded.p,encoded.n);
        mesh.release();encoded.release();return result;
    }
public:
    godot::Ref<godot::ArrayMesh> experimental_snapshot_create_mesh(const godot::Dictionary&packet){
        for(const char*key:{"status","epoch","validated_revision","source_id"})
            if(!packet.has(key)||godot::Variant(packet[key]).get_type()!=godot::Variant::INT)return {};
        if(int64_t(packet["status"])!=0||bool(packet.get("stale",true))||int64_t(packet["source_id"])!=int64_t(get_instance_id()))return {};
        const int64_t revision=packet["validated_revision"],epoch=packet["epoch"];
        {std::lock_guard<std::mutex> lock(mutex_);if(revision!=world_.revision||epoch<0||u64(epoch)!=snapshot_epoch_.load())return {};}
        auto mesh=experimental::make_surface_mesh(packet);
        // Engine allocation/upload is outside the authoritative-world mutex.
        {std::lock_guard<std::mutex> lock(mutex_);if(revision!=world_.revision||u64(epoch)!=snapshot_epoch_.load())return {};}
        return mesh;
    }
    bool experimental_snapshot_submit(int64_t x,int64_t z,int64_t size,int64_t token,int64_t revision){
        return experimental_snapshot_submit_brick(x,z,size,token,revision,0,WORLD_Y);
    }
    bool experimental_snapshot_submit_brick(int64_t x,int64_t z,int64_t size,int64_t token,int64_t revision,int64_t y_begin,int64_t y_end){
        if(x<0||z<0||x>WORLD||z>WORLD||size<1||size>32||token<0||revision<0||y_begin<0||y_begin>=y_end||y_end>WORLD_Y)return false;
        using Clock=std::chrono::steady_clock;auto begin=Clock::now();
        std::unique_lock<std::mutex> lock(mutex_);
        SubmitTiming timing;timing.token=token;
        timing.world_lock_ms=std::chrono::duration<double,std::milli>(Clock::now()-begin).count();
        if(revision==world_.revision){
            auto startup=Clock::now();
            if(!snapshot_worker_)snapshot_worker_.emplace(3*1024*1024,32*1024*1024);
            timing.startup_ms=std::chrono::duration<double,std::milli>(Clock::now()-startup).count();
            timing.accepted=snapshot_worker_->submit(world_,int(x),int(z),int(size),snapshot_epoch_.load(),u64(token),&timing.worker,int(y_begin),int(y_end));
        }
        auto unlocking=Clock::now();lock.unlock();
        timing.world_unlock_ms=std::chrono::duration<double,std::milli>(Clock::now()-unlocking).count();
        timing.total_ms=std::chrono::duration<double,std::milli>(Clock::now()-begin).count();
        {std::lock_guard<std::mutex> timing_lock(submit_timing_mutex_);last_submit_=timing;}
        return timing.accepted;
    }
    godot::Dictionary experimental_snapshot_submit_timing(){
        SubmitTiming timing;{std::lock_guard<std::mutex> lock(submit_timing_mutex_);timing=last_submit_;}
        godot::Dictionary row;
        row["token"]=timing.token;row["accepted"]=timing.accepted;row["total_ms"]=timing.total_ms;
        row["world_lock_ms"]=timing.world_lock_ms;row["startup_ms"]=timing.startup_ms;
        row["worker_lock_ms"]=timing.worker.lock_ms;row["capture_ms"]=timing.worker.capture_ms;
        row["handoff_ms"]=timing.worker.handoff_ms;row["world_unlock_ms"]=timing.world_unlock_ms;return row;
    }
    godot::Array experimental_snapshot_poll(){
        std::lock_guard<std::mutex> lock(mutex_);godot::Array rows;
        if(!snapshot_worker_)return rows;
        const u64 epoch=snapshot_epoch_.load();
        snapshot_worker_->consume_surface(epoch,world_.revision,[&](u64 token,u64 captured,int revision,bool stale,const experimental::Result&r,const experimental::NormalResult&n){
            godot::Dictionary row;row["token"]=int64_t(token);row["epoch"]=int64_t(captured);row["revision"]=revision;row["stale"]=stale;
            row["source_id"]=int64_t(get_instance_id());
            row["validated_revision"]=stale?-1:world_.revision;
            row["y_begin"]=r.y_begin;row["y_end"]=r.y_end;
            int status=int(r.status);godot::PackedByteArray positions,indices,normals;
            if(r.status==experimental::MeshStatus::ok){
                static_assert(sizeof(V3)==12);
                if(n.status!=experimental::MeshStatus::ok||n.values.size()!=r.p.size()){
                    status=int(experimental::MeshStatus::internal_error);
                }else if(positions.resize(r.p.size()*sizeof(V3))!=godot::OK||indices.resize(r.indices.size()*sizeof(u32))!=godot::OK||normals.resize(n.values.size()*sizeof(V3))!=godot::OK){
                    positions.clear();indices.clear();normals.clear();status=int(experimental::MeshStatus::allocation_failed);
                }else{
                    if(!r.p.empty())copy_bytes(positions.ptrw(),r.p.data(),r.p.size()*sizeof(V3));
                    if(!r.indices.empty())copy_bytes(indices.ptrw(),r.indices.data(),r.indices.size()*sizeof(u32));
                    if(!n.values.empty())copy_bytes(normals.ptrw(),n.values.data(),n.values.size()*sizeof(V3));
                }
            }
            row["status"]=status;row["positions"]=positions;row["indices"]=indices;row["normals"]=normals;rows.push_back(row);
        });
        // Command 12 can invalidate concurrently without acquiring the world lock.
        if(snapshot_epoch_.load()!=epoch)for(int i=0;i<rows.size();i++){
            godot::Dictionary row=rows[i];row["stale"]=true;row["status"]=int(experimental::MeshStatus::cancelled);
            row["validated_revision"]=-1;
            row["positions"]=godot::PackedByteArray();row["indices"]=godot::PackedByteArray();row["normals"]=godot::PackedByteArray();
        }
        return rows;
    }
    void experimental_snapshot_stop(){std::lock_guard<std::mutex> lock(mutex_);if(snapshot_worker_)snapshot_worker_->stop();}
    bool supports_isolated_worlds() const {return true;}
    int64_t executing_command() const {return active_command_.load(std::memory_order_relaxed);}
    godot::String build_variant() const {
#ifdef DEBUG_ENABLED
        return "template_debug";
#else
        return "template_release";
#endif
    }
    // Offline new-world admission only. Apply the exact ordinary command28
    // sequence once, before any mesh/collision or immutable snapshot is exposed.
    godot::Dictionary bake_generated_earthworks(const godot::Array &packets) {
        godot::Dictionary result;result["ok"]=false;result["completed"]=0;
        if(packets.is_empty()||packets.size()>4096){result["reason"]="Invalid generation command count";return result;}
        int64_t total=0;
        std::vector<godot::PackedByteArray> commands;
        for(int64_t i=0;i<packets.size();++i){
            if(packets[i].get_type()!=godot::Variant::PACKED_BYTE_ARRAY)return result;
            godot::PackedByteArray packet=packets[i];total+=packet.size();
            if(packet.size()<44||packet.size()>1080||packet.decode_u32(0)!=28||total>4*1024*1024)return result;
            commands.push_back(packet);
        }
        std::lock_guard<std::mutex> lock(mutex_);
        if(world_.revision||world_.edits||world_.pages.n||world_.blocks.n||snapshot_worker_){result["reason"]="Generation requires a pristine unpublished world";return result;}
        const int seed=world_.seed;const auto generator=world_.generator_id;
        const auto started=std::chrono::steady_clock::now();
        snapshot_epoch_.fetch_add(1);active_command_.store(28,std::memory_order_relaxed);
        int completed=0;bool good=true;
        for(const auto &packet:commands){
            tr_oom=false;Bytes response;process_request(world_,packet.ptr(),int(packet.size()),response);
            good=!tr_oom&&response.n>=12&&response.p[8]==0;response.release();
            if(!good)break;++completed;
        }
        active_command_.store(-1,std::memory_order_relaxed);
        if(!good){
            // No published state exists. Discard every partial edit on rejection.
            tr_oom=false;world_.release();world_=World{};world_.build_control=&control_;world_.init(seed,generator);
            result["reason"]="Generation command rejected; unpublished edits discarded";return result;
        }
        result["ok"]=true;result["completed"]=completed;result["revision"]=world_.revision;
        result["worker_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count();return result;
    }
    // Unpublished generation only. Durable private checkpoints make clean pages
    // evictable without publishing a compound-world root or losing prior edits.
    godot::Dictionary generation_bake_progress()const{return generation_progress_.read();}
    godot::Dictionary bake_generated_earthworks_staged(const godot::Array &packets,const godot::String &directory,int64_t limit=MAX_PAGES,int64_t batch=64,int64_t expected_epoch=-1,int64_t test_stop_at_checkpoint=-1){
        godot::Dictionary result;result["ok"]=false;result["completed"]=0;
        if(packets.is_empty()||packets.size()>4096||limit<8||limit>MAX_PAGES||batch<1||batch>256||expected_epoch< -1||expected_epoch>0xffffffffll||test_stop_at_checkpoint< -1||test_stop_at_checkpoint>8193||!directory.is_absolute_path()){
            result["reason"]="Invalid staged generation bounds";return result;
        }
        std::vector<godot::PackedByteArray> commands;int64_t total=0;
        for(int64_t i=0;i<packets.size();++i){
            if(packets[i].get_type()!=godot::Variant::PACKED_BYTE_ARRAY)return result;
            godot::PackedByteArray packet=packets[i];total+=packet.size();
            if(packet.size()<44||packet.size()>1080||packet.decode_u32(0)!=28||total>4*1024*1024)return result;
            commands.push_back(packet);
        }
        std::lock_guard<std::mutex> lock(mutex_);
        if(expected_epoch>=0&&terrain_build_epoch(&world_)!=uint32_t(expected_epoch)){result["reason"]="Generation cancelled before staging";return result;}
        if(world_.revision||world_.edits||world_.pages.n||world_.blocks.n||snapshot_worker_||residency_||!storage_reference_.is_empty()){
            result["reason"]="Generation requires a pristine unpublished world";return result;
        }
        if(godot::DirAccess::dir_exists_absolute(directory)||godot::FileAccess::file_exists(directory)){
            result["reason"]="Generation staging directory already exists";return result;
        }
        godot::Ref<NativeTerrainRegionStore> store;store.instantiate();
        if(!store->open_store(directory,true)){result["reason"]="Cannot create private terrain staging store";return result;}
        const int seed=world_.seed;const auto generator=world_.generator_id;
        const u32 epoch=expected_epoch>=0?uint32_t(expected_epoch):terrain_build_epoch(&world_);const auto started=std::chrono::steady_clock::now();
        godot::PackedByteArray reference;int completed=0,checkpoints=0,retries=0,checkpoint_revision=-1;
        int64_t capture_high=0;
        generation_progress_.publish(GenerationBakeProgress::RUNNING,GenerationBakeProgress::APPLYING,completed,int(commands.size()),checkpoints);
        auto checkpoint=[&](){
            if(terrain_build_epoch(&world_)!=epoch)return false;
            if(checkpoint_revision==world_.revision)return true;
            generation_progress_.publish(GenerationBakeProgress::RUNNING,GenerationBakeProgress::CHECKPOINT,completed,int(commands.size()),checkpoints);
            auto capture=capture_storage_snapshot_locked();if(capture.is_null())return false;
            capture_high=std::max(capture_high,int64_t(capture->stats()["sample_bytes"]));
            auto next=store->publish_capture(capture,reference,checkpoints==test_stop_at_checkpoint?(checkpoints==0?0:1):-1);
            if(next.size()!=40||terrain_build_epoch(&world_)!=epoch||!commit_storage_snapshot_locked(capture,next))return false;
            reference=next;checkpoint_revision=world_.revision;++checkpoints;
            generation_progress_.publish(GenerationBakeProgress::RUNNING,GenerationBakeProgress::APPLYING,completed,int(commands.size()),checkpoints);return true;
        };
        snapshot_epoch_.fetch_add(1);active_command_.store(28,std::memory_order_relaxed);
        bool good=checkpoint()&&mount_storage_checkpoint_locked(directory,reference,limit);
        for(const auto &packet:commands){
            if(!good||terrain_build_epoch(&world_)!=epoch){good=false;break;}
            bool retryable=false;
            auto apply=[&](){
                tr_oom=false;Bytes response;process_request(world_,packet.ptr(),int(packet.size()),response);
                bool ok=!tr_oom&&response.n>=12&&response.p[8]==0;retryable=response.n>=12&&response.p[8]==2;response.release();return ok;
            };
            good=apply();
            // Ordinary edits roll back exactly on failed admission. Checkpoint
            // earlier commands once, then retry; an indivisible oversized edit
            // still rejects rather than raising the resident limit.
            if(!good&&retryable&&world_.revision!=checkpoint_revision&&terrain_build_epoch(&world_)==epoch){
                ++retries;good=checkpoint()&&apply();
            }
            if(!good)break;
            ++completed;
            generation_progress_.publish(GenerationBakeProgress::RUNNING,GenerationBakeProgress::APPLYING,completed,int(commands.size()),checkpoints);
            if(completed%batch==0)good=checkpoint();
        }
        if(good)good=checkpoint()&&terrain_build_epoch(&world_)==epoch;
        active_command_.store(-1,std::memory_order_relaxed);
        result["completed"]=completed;result["checkpoints"]=checkpoints;result["admission_retries"]=retries;
        result["capture_sample_bytes_high"]=capture_high;result["resident_limit"]=limit;
        result["resident_high"]=residency_?residency_->resident_high():0;
        result["worker_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count();
        result["storage"]=store->stats();
        if(!good){
            generation_progress_.publish(terrain_build_epoch(&world_)!=epoch?GenerationBakeProgress::CANCELLED:GenerationBakeProgress::FAILED,GenerationBakeProgress::NONE,completed,int(commands.size()),checkpoints);
            // Only immutable staging products may remain. No canonical root was
            // published; invalidate captures and discard every partial world edit.
            tr_oom=false;world_.release();residency_.reset();world_=World{};world_.build_control=&control_;world_.init(seed,generator);
            saved_keys_=godot::PackedInt32Array();saved_versions_=godot::PackedInt64Array();storage_reference_=godot::PackedByteArray();
            storage_load_pending_=false;++storage_epoch_;snapshot_epoch_.fetch_add(1);
            result["reason"]="Staged generation rejected or cancelled; unpublished edits discarded";return result;
        }
        generation_progress_.publish(GenerationBakeProgress::COMPLETE,GenerationBakeProgress::NONE,completed,int(commands.size()),checkpoints);
        result["ok"]=true;result["revision"]=world_.revision;result["checkpoint"]=reference;return result;
    }
    godot::Dictionary survey_generated_lake_surfaces(const godot::Array &records){std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=terraforest::survey_generated_lake_surfaces(world_,records);return tr_oom?godot::Dictionary():result;}
    godot::Ref<NativeTerrainCapture> capture_storage_snapshot(){
        std::lock_guard<std::mutex> lock(mutex_);
        return capture_storage_snapshot_locked();
    }
    godot::Ref<NativeTerrainCapture> capture_storage_snapshot_locked(){
        tr_oom=false;int count=world_.pages.n;if(count<0||count>MAX_AUTHORED_PAGES)return {};
        const int32_t *saved=saved_keys_.ptr();const int64_t *versions=saved_versions_.ptr();
        auto dirty=[&](int i){return i>=saved_keys_.size()||saved[i]!=int32_t(world_.pages[i].key)||uint64_t(versions[i])!=world_.pages[i].storage_version;};
        int changed=0;for(int i=0;i<count;i++)changed+=dirty(i);
        uint64_t bytes=256+uint64_t(count)*12+uint64_t(changed)*(PAGE_SAMPLES*3+4)+uint64_t(world_.blocks.n)*8;
        constexpr uint64_t limit=256*1024*1024;
        uint64_t previous=NativeTerrainCapture::pending_bytes_.load();
        do{if(bytes>limit||previous>limit-bytes)return {};}
        while(!NativeTerrainCapture::pending_bytes_.compare_exchange_weak(previous,previous+bytes));
        godot::Ref<NativeTerrainCapture> capture;capture.instantiate();if(capture.is_null()){NativeTerrainCapture::pending_bytes_.fetch_sub(bytes);return {};}capture->reserved_=bytes;
        if(capture->keys_.resize(count)!=godot::OK||capture->versions_.resize(count)!=godot::OK||capture->changed_.resize(changed)!=godot::OK||capture->samples_.resize(int64_t(changed)*PAGE_SAMPLES*3)!=godot::OK||capture->blocks_.resize(int64_t(world_.blocks.n)*8)!=godot::OK)return {};
        auto *keys=capture->keys_.ptrw();auto *stamps=capture->versions_.ptrw();auto *indices=capture->changed_.ptrw();auto *samples=capture->samples_.ptrw();
        int next=0;
        for(int i=0;i<count;i++){
            const auto &page=world_.pages[i];keys[i]=page.key;stamps[i]=int64_t(page.storage_version);
            if(dirty(i)){if(!world_.resident_page(i))return {};indices[next]=i;copy_bytes(samples+int64_t(next)*PAGE_SAMPLES*3,page.d,PAGE_SAMPLES*2);copy_bytes(samples+int64_t(next)*PAGE_SAMPLES*3+PAGE_SAMPLES*2,page.mat,PAGE_SAMPLES);++next;}
        }
        int64_t at=0;auto *blocks=capture->blocks_.ptrw();
        for(int i=0;i<world_.blocks.cap;i++)if(world_.blocks.p[i].key&&world_.blocks.p[i].key!=0xffffffffu){
            uint32_t key=world_.blocks.p[i].key,value=world_.blocks.p[i].value;copy_bytes(blocks+at,&key,4);copy_bytes(blocks+at+4,&value,4);at+=8;
        }
        if(at!=capture->blocks_.size())return {};
        capture->owner_=get_instance_id();capture->epoch_=storage_epoch_;capture->seed_=world_.seed;capture->generator_=world_.generator_id;capture->revision_=world_.revision;capture->edits_=world_.edits;
        capture->source_=storage_reference_;capture->expected_=storage_reference_;capture->sealed_=true;return capture;
    }
    bool configure_storage_checkpoint(const godot::PackedByteArray &reference,int64_t checksum){
        std::lock_guard<std::mutex> lock(mutex_);
        if(!storage_load_pending_||world_.revision!=storage_load_revision_||checksum<0||checksum>0xffffffffll||uint32_t(checksum)!=storage_load_checksum_||reference.size()!=40||reference.slice(0,4).get_string_from_ascii()!="TFTR"||reference.decode_u32(4)!=1)return false;
        godot::PackedInt32Array keys;godot::PackedInt64Array versions;
        if(keys.resize(world_.pages.n)!=godot::OK||versions.resize(world_.pages.n)!=godot::OK)return false;
        for(int i=0;i<world_.pages.n;i++){keys.set(i,world_.pages[i].key);versions.set(i,int64_t(world_.pages[i].storage_version));}
        saved_keys_=keys;saved_versions_=versions;storage_reference_=reference;storage_load_pending_=false;return true;
    }
    bool commit_storage_snapshot(const godot::Ref<NativeTerrainCapture> &capture,const godot::PackedByteArray &reference){
        std::lock_guard<std::mutex> lock(mutex_);return commit_storage_snapshot_locked(capture,reference);
    }
    bool commit_storage_snapshot_locked(const godot::Ref<NativeTerrainCapture> &capture,const godot::PackedByteArray &reference){
        if(capture.is_null())return false;std::lock_guard<std::mutex> publication(capture->publication_mutex_);
        if(!capture->sealed_||capture->owner_!=get_instance_id()||capture->epoch_!=storage_epoch_||capture->source_!=storage_reference_||capture->published_!=reference||reference.size()!=40||capture->keys_.size()>world_.pages.n)return false;
        for(int i=0;i<capture->keys_.size();i++)if(uint32_t(capture->keys_[i])!=world_.pages[i].key)return false;
        // Newer edits keep their newer page stamps and remain dirty.
        saved_keys_=capture->keys_;saved_versions_=capture->versions_;storage_reference_=reference;storage_load_pending_=false;
        for(int i=0;i<capture->keys_.size();i++)world_.pages[i].clean_version=uint64_t(capture->versions_[i]);
        if(residency_)residency_->checkpoint(reference);return true;
    }
    bool mount_storage_checkpoint(const godot::String &directory,const godot::PackedByteArray &reference,int64_t limit=MAX_PAGES){
        std::lock_guard<std::mutex> lock(mutex_);return mount_storage_checkpoint_locked(directory,reference,limit);
    }
    bool mount_storage_checkpoint_locked(const godot::String &directory,const godot::PackedByteArray &reference,int64_t limit){
        if(limit<8||limit>MAX_PAGES)return false;
        godot::Ref<NativeTerrainRegionStore> store;store.instantiate();if(!store->open_store(directory,false))return false;
        godot::Dictionary description=store->describe_snapshot(reference);if(!bool(description.get("ok",false)))return false;
        godot::PackedInt32Array keys;godot::PackedInt64Array versions;int64_t count=description["pages"];
        if(keys.resize(count)!=godot::OK||versions.resize(count)!=godot::OK)return false;
        auto residency=std::make_unique<TerrainResidency>(store,reference,int(limit));
        tr_oom=false;if(!store->mount_world(world_,reference))return false;
        snapshot_worker_.reset(); // Old immutable jobs must not survive the new owner epoch.
        residency_=std::move(residency);world_.page_access=residency_.get();
        ++storage_epoch_;snapshot_epoch_.fetch_add(1);storage_load_pending_=false;storage_reference_=reference;
        for(int i=0;i<world_.pages.n;i++){keys.set(i,world_.pages[i].key);versions.set(i,int64_t(world_.pages[i].storage_version));}
        saved_keys_=keys;saved_versions_=versions;
        return true;
    }
    godot::Dictionary residency_stats(){std::lock_guard<std::mutex> lock(mutex_);godot::Dictionary d;if(residency_)d=residency_->stats(world_);else{d["active"]=false;d["catalog_pages"]=world_.pages.n;d["resident_pages"]=world_.pages.n;d["resident_limit"]=MAX_PAGES;}d["generator"]=world_.generator_id;d["seed"]=world_.seed;return d;}
    godot::PackedByteArray execute(const godot::PackedByteArray &packet) {
        if(packet.size()<4 || packet.size()>512LL*1024*1024)return reply(0,1);
        const uint32_t command=packet.decode_u32(0);
        // Cancellation must remain nonblocking while a worker owns world state.
        // Access owner storage directly: reset/load may replace World concurrently.
        if(command==12 || command==13) {
            if(packet.size()!=4)return reply(command,1);
            if(command==12)snapshot_epoch_.fetch_add(1);
            const uint32_t epoch=command==12 ? __atomic_add_fetch(&control_.epoch,1u,__ATOMIC_RELAXED)
                                           : __atomic_load_n(&control_.epoch,__ATOMIC_RELAXED);
            return reply(command,0,epoch,true);
        }
        godot::PackedByteArray result;
        const int expected_reply=fixed_edit_reply_size(command);
        const bool edit_reply=expected_reply>0;
        if(edit_reply&&result.resize(expected_reply)!=godot::OK)return {};
        std::lock_guard<std::mutex> lock(mutex_);
        // Load/reset may reuse revision values; invalidate even a failed attempt.
        if(command==5||command==6){snapshot_epoch_.fetch_add(1);++storage_epoch_;saved_keys_=godot::PackedInt32Array();saved_versions_=godot::PackedInt64Array();storage_reference_=godot::PackedByteArray();storage_load_pending_=false;}
        tr_oom=false;
        Bytes bytes;
        const int previous_revision=world_.revision;
        active_command_.store(command,std::memory_order_relaxed);
        process_request(world_,packet.ptr(),int(packet.size()),bytes);
        if(tr_oom&&bytes.n>=12)bytes.p[8]=2;
        if((command==5||command==6)&&bytes.n>=12&&bytes.p[8]==0){
            generation_progress_.reset();
            residency_.reset();world_.page_access=nullptr;
            storage_load_pending_=command==5;storage_load_checksum_=command==5?packet.decode_u32(packet.size()-4):0;storage_load_revision_=world_.revision;
        }

        if(command==2){
            if(bytes.n>=52&&bytes.p[8]==0){
                Reader bounds{bytes.p,bytes.n,28};V3 lo=bounds.vec(),hi=bounds.vec();
                if(snapshot_worker_&&bounds.good)snapshot_worker_->observe_density_edit(previous_revision,world_.revision,lo,hi);
            }else{
                // Rejected edits retain the field; invalidate outstanding
                // admission tokens conservatively before another attempt.
                snapshot_epoch_.fetch_add(1);
            }
        }
        active_command_.store(-1,std::memory_order_relaxed);
        if(edit_reply&&bytes.n>EDIT_REPLY_CAPACITY){bytes.release();return {};}
        bool ready=edit_reply&&bytes.n==expected_reply;
        if(!ready)ready=result.resize(bytes.n)==godot::OK;
        if(ready&&bytes.n)copy_bytes(result.ptrw(),bytes.p,size_t(bytes.n));
        bytes.release();
        return result;
    }
};
}

static void initialize(godot::ModuleInitializationLevel level) {
    if(level!=godot::MODULE_INITIALIZATION_LEVEL_SCENE)return;
    // Installed once before any instance exists; thereafter immutable across workers.
    tr_alloc=std::malloc; tr_realloc=std::realloc; tr_free=std::free;
    GDREGISTER_CLASS(terraforest::NativeTerrainCapture);
    GDREGISTER_CLASS(terraforest::TerrainCore);
    GDREGISTER_CLASS(terraforest::NativeTerrainRegionStore);
    GDREGISTER_CLASS(terraforest::NativeTerrainPlanner);
    GDREGISTER_CLASS(terraforest::NativeRoadProfile);
    GDREGISTER_CLASS(terraforest::NativeTerrainCollisionPiece);
    GDREGISTER_CLASS(terraforest::NativeTerrainCollision);
}
static void terminate(godot::ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT terrain_library_init(
    GDExtensionInterfaceGetProcAddress address, GDExtensionClassLibraryPtr library,
    GDExtensionInitialization *initialization) {
    godot::GDExtensionBinding::InitObject init(address,library,initialization);
    init.register_initializer(initialize); init.register_terminator(terminate);
    init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
