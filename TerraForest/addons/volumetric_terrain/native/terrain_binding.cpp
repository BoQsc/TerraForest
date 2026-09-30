// SPDX-License-Identifier: 0BSD
#include "core.h"
#include "terrain_planner.hpp"
#include "terrain_collision.hpp"
#include "experimental/snapshot_worker.hpp"
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
        godot::ClassDB::bind_method(godot::D_METHOD("supports_isolated_worlds"), &TerrainCore::supports_isolated_worlds);
        godot::ClassDB::bind_method(godot::D_METHOD("build_variant"), &TerrainCore::build_variant);
        godot::ClassDB::bind_method(godot::D_METHOD("executing_command"), &TerrainCore::executing_command);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_submit","x","z","size","token","revision"), &TerrainCore::experimental_snapshot_submit);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_poll"), &TerrainCore::experimental_snapshot_poll);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_stop"), &TerrainCore::experimental_snapshot_stop);
    }
public:
    TerrainCore() {world_.build_control=&control_; tr_oom=false; world_.init();}
    ~TerrainCore() {snapshot_worker_.reset();world_.release();}
    bool experimental_snapshot_submit(int64_t x,int64_t z,int64_t size,int64_t token,int64_t revision){
        if(x<0||z<0||x>WORLD||z>WORLD||size<1||size>32||token<0||revision<0)return false;
        std::lock_guard<std::mutex> lock(mutex_);
        if(revision!=world_.revision)return false;
        if(!snapshot_worker_)snapshot_worker_.emplace(3*1024*1024,32*1024*1024);
        return snapshot_worker_->submit(world_,int(x),int(z),int(size),snapshot_epoch_.load(),u64(token));
    }
    godot::Array experimental_snapshot_poll(){
        std::lock_guard<std::mutex> lock(mutex_);godot::Array rows;
        if(!snapshot_worker_)return rows;
        const u64 epoch=snapshot_epoch_.load();
        snapshot_worker_->consume_surface(epoch,world_.revision,[&](u64 token,u64 captured,int revision,bool stale,const experimental::Result&r,const experimental::NormalResult&n){
            godot::Dictionary row;row["token"]=int64_t(token);row["epoch"]=int64_t(captured);row["revision"]=revision;row["stale"]=stale;
            row["validated_revision"]=stale?-1:world_.revision;
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
