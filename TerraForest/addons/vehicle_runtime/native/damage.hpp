// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/transform3d.hpp>
namespace terraforest {
class NativeVehicleDamage : public godot::RefCounted {
    GDCLASS(NativeVehicleDamage,godot::RefCounted)
protected:
    static void _bind_methods();
public:
    godot::Ref<godot::ArrayMesh> dent(const godot::Ref<godot::Mesh> &source,godot::Transform3D transform,godot::Vector3 point,godot::Vector3 direction,double radius,double depth) const;
};
}
