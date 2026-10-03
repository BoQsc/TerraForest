#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <cstdint>
#include <memory>
#include <unordered_map>
#include <functional>

namespace terraforest {
// Dense iteration with generation-checked handles; no scene node per entity.
// Kinematics only: contacts, vehicle dynamics and networking are separate systems.
class NativeEntityStore : public godot::RefCounted {
    GDCLASS(NativeEntityStore, godot::RefCounted)
    struct Cell {
        real_t x,y,z;
        bool operator==(const Cell &other) const {return x==other.x&&y==other.y&&z==other.z;}
    };
    struct CellHash {size_t operator()(const Cell &c) const {
        return std::hash<real_t>{}(c.x)^(std::hash<real_t>{}(c.y)<<1)^(std::hash<real_t>{}(c.z)<<2);
    }};
    static Cell cell_for(const godot::Vector3 &p);
    std::unordered_map<Cell,uint32_t,CellHash> cell_heads_;
    struct Slot {
        godot::Vector3 position;
        godot::Vector3 velocity;
        uint64_t persistent_id = 0;
        uint32_t generation = 0;
        uint32_t dense_index = 0;
        bool active = false;
        uint32_t previous=UINT32_MAX,next=UINT32_MAX;
    };
    std::unique_ptr<Slot[]> slots_;
    std::unique_ptr<uint32_t[]> dense_;
    std::unique_ptr<uint32_t[]> free_;
    uint32_t capacity_ = 0, count_ = 0, free_count_ = 0;
    uint32_t next_generation_ = 1;
    uint64_t ticks_ = 0;
    uint64_t next_persistent_id_ = 1;
    std::unordered_map<uint64_t, uint32_t> identity_slots_;
    Slot *resolve(int64_t id) const;
    int64_t spawn_unchecked(const godot::Vector3 &position, const godot::Vector3 &velocity, uint64_t persistent_id = 0);
    void index_insert(uint32_t index);
    void index_remove(uint32_t index);
protected:
    static void _bind_methods();
public:
    bool configure(int64_t capacity);
    int64_t spawn(const godot::Vector3 &position, const godot::Vector3 &velocity);
    godot::PackedInt64Array spawn_grid(int64_t count, const godot::Vector3 &origin, double spacing, const godot::Vector3 &velocity);
    bool despawn(int64_t id);
    bool contains(int64_t id) const;
    int64_t persistent_id(int64_t handle) const;
    int64_t resolve_identity(int64_t identity) const;
    godot::Vector3 get_position(int64_t id) const;
    bool set_velocity(int64_t id, const godot::Vector3 &velocity);
    bool step(double seconds);
    godot::PackedFloat32Array multimesh_transforms() const;
    godot::Dictionary statistics() const;
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &data);
    godot::Dictionary query_sphere(const godot::Vector3 &center,double radius,int result_limit=256,int candidate_budget=4096) const;
};
}
