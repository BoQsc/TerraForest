// SPDX-License-Identifier: 0BSD
#include "core.h"
#include "terrain_planner.hpp"
#include "terrain_collision.hpp"
#include "geometry_content_key.hpp"
#include "experimental/snapshot_worker.hpp"
#include "experimental/godot_surface_mesh.hpp"
#include "experimental/mesh_partition.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <optional>
#include <cstdlib>
#include <atomic>
#include <mutex>

namespace terraforest {
class TerrainCore : public godot::RefCounted {
    GDCLASS(TerrainCore, godot::RefCounted)
    BuildControl control_;
    World world_;
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
        return terraforest::geometry_content_key(world_,int(x),int(z),int(size),int(step));
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
        std::lock_guard<std::mutex> lock(mutex_);
        // Load/reset may reuse revision values; invalidate even a failed attempt.
        if(command==5||command==6)snapshot_epoch_.fetch_add(1);
        tr_oom=false;
        Bytes bytes;
        const int previous_revision=world_.revision;
        active_command_.store(command,std::memory_order_relaxed);
        process_request(world_,packet.ptr(),int(packet.size()),bytes);
        if(command==2){
            if(bytes.n>=52&&bytes.p[8]==0){
                Reader bounds{bytes.p,bytes.n,28};V3 lo=bounds.vec(),hi=bounds.vec();
                if(snapshot_worker_&&bounds.good)snapshot_worker_->observe_density_edit(previous_revision,world_.revision,lo,hi);
            }else{
                // Failed edits can have partially modified pages before returning
                // without a revision increment. Never certify those snapshots.
                snapshot_epoch_.fetch_add(1);
            }
        }
        active_command_.store(-1,std::memory_order_relaxed);
        godot::PackedByteArray result;
        if(result.resize(bytes.n)==godot::OK && bytes.n)copy_bytes(result.ptrw(),bytes.p,size_t(bytes.n));
        bytes.release();
        return result;
    }
};
}

static void initialize(godot::ModuleInitializationLevel level) {
    if(level!=godot::MODULE_INITIALIZATION_LEVEL_SCENE)return;
    // Installed once before any instance exists; thereafter immutable across workers.
    tr_alloc=std::malloc; tr_realloc=std::realloc; tr_free=std::free;
    GDREGISTER_CLASS(terraforest::TerrainCore);
    GDREGISTER_CLASS(terraforest::NativeTerrainPlanner);
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
