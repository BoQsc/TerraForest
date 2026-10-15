// SPDX-License-Identifier: 0BSD
#pragma once
#include "entity_store.hpp"
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/kinematic_collision3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/navigation_agent3d.hpp>
namespace terraforest {
// One near-field collision proxy. Distant records remain in the store without bodies.
// Caller owns activation/readiness and calls tick once per physics step, never store.step.
class NativeEntityActor : public godot::CharacterBody3D {
    GDCLASS(NativeEntityActor,godot::CharacterBody3D)
    godot::Ref<NativeEntityStore> store_;
    int64_t handle_=0;
    godot::Ref<godot::KinematicCollision3D> step_collision_;
    godot::Ref<godot::PhysicsRayQueryParameters3D> step_support_;
    uint64_t step_frame_=0;
    bool stepped_before_=false;
    godot::NavigationAgent3D *avoidance_=nullptr;
    godot::Vector3 safe_velocity_;
    uint64_t safe_frame_=0;
    bool crowd_active_=false,safe_valid_=false;
    void avoidance_velocity(const godot::Vector3 &velocity);
    bool step_grounded(const godot::Vector3 &velocity,double delta);
protected:
    static void _bind_methods();
public:
    bool profile_tick=false;
    bool stairs_enabled=false;
    double arrival_distance=.15;
    uint64_t transform_us=0,motion_us=0,store_us=0;
    bool bind_entity(const godot::Ref<NativeEntityStore> &store,int64_t handle);
    int64_t entity_handle(const godot::Ref<NativeEntityStore> &store) const;
    void set_crowd_active(bool active);
    bool tick(const godot::Vector3 &target,double delta,bool collision_ready);
};
}
