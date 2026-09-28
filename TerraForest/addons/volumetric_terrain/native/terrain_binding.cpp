// SPDX-License-Identifier: 0BSD
#include "core.h"
#include "terrain_planner.hpp"
#include "terrain_collision.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
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
    }
public:
    TerrainCore() {world_.build_control=&control_; tr_oom=false; world_.init();}
    ~TerrainCore() {world_.release();}
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
            const uint32_t epoch=command==12 ? __atomic_add_fetch(&control_.epoch,1u,__ATOMIC_RELAXED)
                                           : __atomic_load_n(&control_.epoch,__ATOMIC_RELAXED);
            return reply(command,0,epoch,true);
        }
        std::lock_guard<std::mutex> lock(mutex_);
        tr_oom=false;
        Bytes bytes;
        active_command_.store(command,std::memory_order_relaxed);
        process_request(world_,packet.ptr(),int(packet.size()),bytes);
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
