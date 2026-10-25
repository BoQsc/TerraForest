// SPDX-License-Identifier: 0BSD
#include "zombie_rest_body.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
using namespace godot;
namespace terraforest {
bool ragdoll_rest_impact(PhysicsDirectBodyState3D *state){
    if(!state)return false;
    if(state->get_linear_velocity().length_squared()>.1*.1||state->get_angular_velocity().length_squared()>1.0)return true;
    auto *server=PhysicsServer3D::get_singleton();
    for(int contact=0;contact<state->get_contact_count();contact++){
        if(server->body_get_collision_layer(state->get_contact_collider(contact))&(1<<18))continue;
        if(state->get_contact_collider_velocity_at_position(contact).length_squared()>.1*.1)return true;
    }
    return false;
}
namespace {
void integrate_rest(PhysicsDirectBodyState3D *state,bool &resting){
    if(!resting||!state)return;
    if(ragdoll_rest_impact(state)){resting=false;return;}
    state->set_linear_velocity(Vector3());state->set_angular_velocity(Vector3());state->set_sleep_state(true);
}
}
void NativeZombiePhysicalBone::_bind_methods(){
    ClassDB::bind_method(D_METHOD("set_resting","value"),&NativeZombiePhysicalBone::set_resting);
    ClassDB::bind_method(D_METHOD("is_resting"),&NativeZombiePhysicalBone::is_resting);
}
void NativeZombiePhysicalBone::set_resting(bool value){
    if(resting_==value)return;
    auto *server=PhysicsServer3D::get_singleton();
    if(value){
        continuous_=server->body_is_continuous_collision_detection_enabled(get_rid());custom_=is_using_custom_integrator();
        server->body_set_enable_continuous_collision_detection(get_rid(),false);set_use_custom_integrator(true);
    }else{server->body_set_enable_continuous_collision_detection(get_rid(),continuous_);set_use_custom_integrator(custom_);}
    resting_=value;
}
void NativeZombiePhysicalBone::_integrate_forces(PhysicsDirectBodyState3D *state){
    bool before=resting_;integrate_rest(state,resting_);
    if(before&&!resting_){PhysicsServer3D::get_singleton()->body_set_enable_continuous_collision_detection(get_rid(),continuous_);set_use_custom_integrator(custom_);}
}
void NativeZombieRigidPart::_bind_methods(){
    ClassDB::bind_method(D_METHOD("set_resting","value"),&NativeZombieRigidPart::set_resting);
    ClassDB::bind_method(D_METHOD("is_resting"),&NativeZombieRigidPart::is_resting);
}
void NativeZombieRigidPart::set_resting(bool value){
    if(resting_==value)return;
    // A verified resting piece needs neither swept collision nor another
    // gravity correction against its support. Collision impulses and ordinary
    // motion integration remain active, so impacts can restore full dynamics.
    if(value){
        continuous_=is_using_continuous_collision_detection();custom_=is_using_custom_integrator();
        set_use_continuous_collision_detection(false);set_use_custom_integrator(true);
    }else{set_use_continuous_collision_detection(continuous_);set_use_custom_integrator(custom_);}
    resting_=value;
}
void NativeZombieRigidPart::_integrate_forces(PhysicsDirectBodyState3D *state){
    bool before=resting_;integrate_rest(state,resting_);
    if(before&&!resting_){set_use_continuous_collision_detection(continuous_);set_use_custom_integrator(custom_);}
}
}
