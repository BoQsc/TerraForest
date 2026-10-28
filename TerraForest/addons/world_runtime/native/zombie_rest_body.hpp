// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/physical_bone3d.hpp>
#include <godot_cpp/classes/rigid_body3d.hpp>
#include <godot_cpp/classes/physics_direct_body_state3d.hpp>
namespace terraforest {
bool ragdoll_rest_impact(godot::PhysicsDirectBodyState3D *state);
bool ragdoll_player_load(godot::PhysicsDirectBodyState3D *state,int contact);
bool ragdoll_contact_valid(godot::PhysicsDirectBodyState3D *state,int contact);
class NativeZombiePhysicalBone : public godot::PhysicalBone3D {
    GDCLASS(NativeZombiePhysicalBone,godot::PhysicalBone3D)
    bool resting_=false;
    bool continuous_=false;
    bool custom_=false;
protected:
    static void _bind_methods();
public:
    void set_resting(bool value);
    bool is_resting() const{return resting_;}
    void _integrate_forces(godot::PhysicsDirectBodyState3D *state) override;
};
class NativeZombieRigidPart : public godot::RigidBody3D {
    GDCLASS(NativeZombieRigidPart,godot::RigidBody3D)
    bool resting_=false;
    bool continuous_=false;
    bool custom_=false;
protected:
    static void _bind_methods();
public:
    void set_resting(bool value);
    bool is_resting() const{return resting_;}
    void _integrate_forces(godot::PhysicsDirectBodyState3D *state) override;
};
}
