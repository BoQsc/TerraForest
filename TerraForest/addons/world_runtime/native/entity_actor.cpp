// SPDX-License-Identifier: 0BSD
#include "entity_actor.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeEntityActor::_bind_methods() {
    ClassDB::bind_method(D_METHOD("bind_entity","store","handle"),&NativeEntityActor::bind_entity);
    ClassDB::bind_method(D_METHOD("tick","target","delta","collision_ready"),&NativeEntityActor::tick);
}
bool NativeEntityActor::bind_entity(const Ref<NativeEntityStore> &store,int64_t handle) {
    if(!is_inside_tree()||store.is_null()||!store->contains(handle))return false;
    store_=store;handle_=handle;set_global_position(store_->get_position(handle));
    set_velocity(Vector3());store_->set_velocity(handle_,Vector3());return true;
}
bool NativeEntityActor::tick(const Vector3 &target,double delta,bool collision_ready) {
    if(!is_inside_tree()||store_.is_null()||!store_->contains(handle_)||!target.is_finite()||
       !std::isfinite(delta)||delta<=0||delta>0.1)return false;
    if(!collision_ready){set_velocity(Vector3());return false;}
    // External authority corrections must be reflected before the next collision step.
    set_global_position(store_->get_position(handle_));
    Vector3 direction=target-get_global_position();direction.y=0;
    const real_t distance=direction.length();
    Vector3 velocity;
    if(distance>0.15)velocity=direction/distance*real_t(std::min(2.5,double(distance)/delta));
    velocity.y=is_on_floor()?0:get_velocity().y-real_t(20.0*delta);
    set_velocity(velocity);move_and_slide();
    // The body owns integration while active, preventing a second kinematic store tick.
    return store_->set_position(handle_,get_global_position());
}
}
