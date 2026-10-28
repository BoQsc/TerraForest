// SPDX-License-Identifier: 0BSD
#include "zombie_rest_body.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/classes/character_body3d.hpp>
using namespace godot;
namespace terraforest {
bool ragdoll_contact_valid(PhysicsDirectBodyState3D *state,int contact){
    uint64_t identity=state->get_contact_collider_id(contact);
    return state->get_contact_collider(contact).is_valid()&&(!identity||ObjectDB::get_instance(identity));
}
bool ragdoll_player_load(PhysicsDirectBodyState3D *state,int contact){
    auto *body=Object::cast_to<CharacterBody3D>(state->get_contact_collider_object(contact));
    return body&&(body->get_collision_layer()&2)&&state->get_contact_local_normal(contact).y<-.25&&std::abs(body->get_velocity().y)<1.;
}
bool ragdoll_rest_impact(PhysicsDirectBodyState3D *state){
    if(!state)return false;
    bool player_load=false;
    auto *server=PhysicsServer3D::get_singleton();
    for(int contact=0;contact<state->get_contact_count();contact++){
        if(!ragdoll_contact_valid(state,contact))continue;
        if(ragdoll_player_load(state,contact)){player_load=true;continue;}
        if(server->body_get_collision_layer(state->get_contact_collider(contact))&(1<<18))continue;
        if(state->get_contact_collider_velocity_at_position(contact).length_squared()>.1*.1)return true;
    }
    return !player_load&&(state->get_linear_velocity().length_squared()>.1*.1||state->get_angular_velocity().length_squared()>1.0);
}
namespace {
void integrate_rest(PhysicsDirectBodyState3D *state,bool &resting){
    if(!resting||!state)return;
    if(ragdoll_rest_impact(state)){resting=false;return;}
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
        server->body_set_state(get_rid(),PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY,Vector3());
        server->body_set_state(get_rid(),PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY,Vector3());
        server->body_set_enable_continuous_collision_detection(get_rid(),false);
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
    if(value){
        continuous_=is_using_continuous_collision_detection();custom_=is_using_custom_integrator();
        set_linear_velocity(Vector3());set_angular_velocity(Vector3());
        set_use_continuous_collision_detection(false);
    }else{set_use_continuous_collision_detection(continuous_);set_use_custom_integrator(custom_);}
    resting_=value;
}
void NativeZombieRigidPart::_integrate_forces(PhysicsDirectBodyState3D *state){
    bool before=resting_;integrate_rest(state,resting_);
    if(before&&!resting_){set_use_continuous_collision_detection(continuous_);set_use_custom_integrator(custom_);}
}
}
