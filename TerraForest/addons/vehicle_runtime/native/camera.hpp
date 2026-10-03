// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/classes/sphere_shape3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
namespace terraforest {
class NativeVehicleCamera : public godot::RefCounted {
    GDCLASS(NativeVehicleCamera,godot::RefCounted)
    godot::Ref<godot::SphereShape3D> shape;
    godot::Ref<godot::PhysicsShapeQueryParameters3D> query;
protected:
    static void _bind_methods();
public:
    NativeVehicleCamera();
    bool update(godot::RigidBody3D *body,godot::Camera3D *camera,double delta);
};
}
