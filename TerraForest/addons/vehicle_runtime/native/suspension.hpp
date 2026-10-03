// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/classes/ray_cast3d.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
namespace terraforest {
class NativeVehicleSuspension : public godot::RefCounted {
    GDCLASS(NativeVehicleSuspension,godot::RefCounted)
protected:
    static void _bind_methods();
public:
    godot::PackedFloat32Array sample_and_apply(godot::RigidBody3D *body,const godot::TypedArray<godot::RayCast3D> &rays) const;
};
}
