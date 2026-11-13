// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
namespace terraforest {
// Surface extraction only. Finite quantities and terrain connectivity belong to
// the authoritative water body, never to this render adapter.
class NativeImplicitWaterSurface : public godot::RefCounted {
    GDCLASS(NativeImplicitWaterSurface,godot::RefCounted)
protected:
    static void _bind_methods();
public:
    godot::Dictionary extract(const godot::PackedFloat32Array &samples,int64_t cells,double spacing) const;
};
}
