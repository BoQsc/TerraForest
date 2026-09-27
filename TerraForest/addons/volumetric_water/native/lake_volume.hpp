#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <memory>

namespace terraforest {
// Builder is worker-owned until ready. Published volumes are immutable.
// Discrete conservative occupancy, not a pressure/flow solver.
class NativeLakeVolume : public godot::RefCounted {
    GDCLASS(NativeLakeVolume, godot::RefCounted)
    godot::Vector3 origin_, seed_;
    godot::Vector3i size_;
    float spacing_ = 1, level_ = 0;
    uint32_t count_ = 0, node_count_ = 0, sampled_ = 0, wet_count_ = 0;
    int status_ = -1;
    std::unique_ptr<float[]> density_;
    std::unique_ptr<uint8_t[]> wet_;
    std::unique_ptr<uint32_t[]> queue_;
    uint32_t index(int x, int y, int z) const;
    uint32_t node(int x, int y, int z) const;
    bool eligible(int x, int y, int z) const;
    int finish();
protected:
    static void _bind_methods();
public:
    bool configure(const godot::Vector3 &origin, const godot::Vector3i &cells,
        double spacing, double fill_level, const godot::Vector3 &seed);
    int bake_density(const godot::PackedFloat32Array &density);
    int sample_terrain(godot::Object *core, int64_t budget, int64_t revision, int64_t epoch);
    bool contains(const godot::Vector3 &point) const;
    double depth_at(const godot::Vector3 &point) const;
    godot::Array surface_arrays() const;
    godot::Dictionary statistics() const;
    godot::AABB bounds() const;
};
}
