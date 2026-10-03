// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/aabb.hpp>
namespace terraforest {
class NativeDrivingPolicy : public godot::RefCounted {
    GDCLASS(NativeDrivingPolicy,godot::RefCounted)
    double fraction_=0,angle_=0,sign_=0,cap_=0.4537856055185257;
protected:
    static void _bind_methods();
public:
    godot::AABB travel_bounds(godot::Vector3 position,godot::Vector3 velocity,double delta) const;
    void reset();
    godot::Vector3 steering(double input,double speed,double delta);
    godot::Vector2 speed(double previous,double throttle,double reverse_brake,bool parked,double boost,double delta) const;
    double apply_grounded(godot::RigidBody3D *body,godot::Vector3 up,double speed) const;
    void apply_free(godot::RigidBody3D *body,godot::Vector3 up,double throttle,double reverse_brake,bool handbrake,bool parked,bool supported) const;
    double stabilize(godot::RigidBody3D *body,godot::Vector3 up,bool supported,int loaded_wheels) const;
};
}
