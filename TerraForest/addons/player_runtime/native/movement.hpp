// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/kinematic_collision3d.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <cmath>
#include <algorithm>
namespace terraforest {
// Velocity policy and bounded stair queries, called by the scene's physics tick.
class NativePlayerMovement : public godot::RefCounted {
    GDCLASS(NativePlayerMovement,godot::RefCounted)
    godot::Ref<godot::KinematicCollision3D> step_collision_;
    godot::Ref<godot::PhysicsRayQueryParameters3D> step_support_;
    static bool valid(double delta,const godot::Vector3 &v) {
        return std::isfinite(delta)&&delta>0&&delta<=0.25&&v.is_finite();
    }
protected:
    static void _bind_methods();
public:
    bool move_grounded(godot::CharacterBody3D *body,double delta);
    godot::Vector3 swimming_velocity(godot::Vector3 direction,godot::Vector3 previous,double vertical,double depth,double delta,bool sprint) const {
        if(!valid(delta,direction)||!previous.is_finite()||!std::isfinite(vertical)||!std::isfinite(depth)||depth<=0)return {};
        direction.y=0;
        if(direction.length_squared()>1)direction.normalize();
        const double speed=sprint?4.5:3.0;
        vertical=std::clamp(vertical,-1.0,1.0);
        // Relax toward a bounded swim velocity. Passive buoyancy keeps the
        // chest sample just below the surface without bypassing collision.
        const double rise=vertical!=0?vertical*speed:std::clamp((depth-0.15)*2.0,-0.5,1.0);
        godot::Vector3 target(direction.x*speed,rise,direction.z*speed);
        if(target.length_squared()>speed*speed)target=target.normalized()*godot::real_t(speed);
        return previous.lerp(target,godot::real_t(1.0-std::exp(-8.0*delta)));
    }
    godot::Vector3 walking_velocity(godot::Vector3 direction,godot::Vector3 previous,double delta,bool sprint,bool grounded,bool jump) const {
        if(!valid(delta,direction)||!previous.is_finite())return {};
        direction.y=0;
        if(direction.length_squared()>1)direction.normalize();
        const double speed=sprint?9.9:5.5;
        return {godot::real_t(direction.x*speed),godot::real_t(grounded?(jump?7.0:0.0):previous.y-20.0*delta),godot::real_t(direction.z*speed)};
    }
    godot::Vector3 flight_displacement(godot::Vector3 direction,double vertical,double delta,bool sprint) const {
        if(!valid(delta,direction)||!std::isfinite(vertical))return {};
        direction.y+=godot::real_t(vertical<-1?-1:(vertical>1?1:vertical));
        return direction.normalized()*godot::real_t((sprint?40.0:14.0)*delta);
    }
};
}
