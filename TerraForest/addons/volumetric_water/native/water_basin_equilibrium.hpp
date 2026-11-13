// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
namespace terraforest {
// Bounded reference for one closed connected basin. This is deliberately not
// the streaming-world spill solver: an open boundary returns a pending result.
class NativeWaterBasinEquilibrium : public godot::RefCounted {
    GDCLASS(NativeWaterBasinEquilibrium,godot::RefCounted)
protected:
    static void _bind_methods();
public:
    godot::Dictionary solve(const godot::PackedFloat32Array &terrain,int64_t cells,
        double spacing,int64_t quantity_ml,double maximum_head) const;
};
}
