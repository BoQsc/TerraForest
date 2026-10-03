// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector2.hpp>
namespace terraforest {
class NativeDrivingPolicy : public godot::RefCounted {
    GDCLASS(NativeDrivingPolicy,godot::RefCounted)
    double fraction_=0,angle_=0,sign_=0,cap_=0.4537856055185257;
protected:
    static void _bind_methods();
public:
    void reset();
    godot::Vector3 steering(double input,double speed,double delta);
    godot::Vector2 speed(double previous,double throttle,double reverse_brake,bool parked,double boost,double delta) const;
};
}
