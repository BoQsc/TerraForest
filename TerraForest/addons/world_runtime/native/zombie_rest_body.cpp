// SPDX-License-Identifier: 0BSD
#include "zombie_rest_body.hpp"
#include <godot_cpp/core/class_db.hpp>
using namespace godot;
namespace terraforest {
namespace {
void integrate_rest(PhysicsDirectBodyState3D *state,bool &resting){
    if(!resting||!state)return;
    // A verified resting island may receive tiny constraint corrections,
    // especially far from the world origin. Resolve sleep in its own physics
    // callback. Real impacts and explicit damage restore ordinary simulation.
    if(state->get_linear_velocity().length_squared()>.4*.4||state->get_angular_velocity().length_squared()>4*4){resting=false;return;}
    state->set_linear_velocity(Vector3());state->set_angular_velocity(Vector3());state->set_sleep_state(true);
}
}
void NativeZombiePhysicalBone::_bind_methods(){
    ClassDB::bind_method(D_METHOD("set_resting","value"),&NativeZombiePhysicalBone::set_resting);
    ClassDB::bind_method(D_METHOD("is_resting"),&NativeZombiePhysicalBone::is_resting);
}
void NativeZombiePhysicalBone::_integrate_forces(PhysicsDirectBodyState3D *state){integrate_rest(state,resting_);}
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
