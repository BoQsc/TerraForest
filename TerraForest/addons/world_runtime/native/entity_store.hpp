#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <cstdint>
#include <memory>

namespace terraforest {
// Dense iteration with generation-checked handles; no scene node per entity.
// Kinematics only: contacts, vehicle dynamics and networking are separate systems.
class NativeEntityStore : public godot::RefCounted {
    GDCLASS(NativeEntityStore, godot::RefCounted)
    struct Slot {
        godot::Vector3 position;
        godot::Vector3 velocity;
        uint32_t generation = 0;
        uint32_t dense_index = 0;
        bool active = false;
    };
    std::unique_ptr<Slot[]> slots_;
    std::unique_ptr<uint32_t[]> dense_;
    std::unique_ptr<uint32_t[]> free_;
    uint32_t capacity_ = 0, count_ = 0, free_count_ = 0;
    uint32_t next_generation_ = 1;
    uint64_t ticks_ = 0;
    Slot *resolve(int64_t id) const;
    int64_t spawn_unchecked(const godot::Vector3 &position, const godot::Vector3 &velocity);
protected:
    static void _bind_methods();
public:
    bool configure(int64_t capacity);
    int64_t spawn(const godot::Vector3 &position, const godot::Vector3 &velocity);
    godot::PackedInt64Array spawn_grid(int64_t count, const godot::Vector3 &origin, double spacing, const godot::Vector3 &velocity);
    bool despawn(int64_t id);
    bool contains(int64_t id) const;
    godot::Vector3 get_position(int64_t id) const;
    bool set_velocity(int64_t id, const godot::Vector3 &velocity);
    bool step(double seconds);
    godot::PackedFloat32Array multimesh_transforms() const;
    godot::Dictionary statistics() const;
};
}
