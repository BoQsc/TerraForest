// SPDX-License-Identifier: 0BSD
#include "entity_actor.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
using namespace godot;
namespace terraforest {
void NativeEntityActor::_bind_methods() {
    ClassDB::bind_method(D_METHOD("bind_entity","store","handle"),&NativeEntityActor::bind_entity);
    ClassDB::bind_method(D_METHOD("tick","target","delta","collision_ready"),&NativeEntityActor::tick);
    ClassDB::bind_method(D_METHOD("entity_handle","store"),&NativeEntityActor::entity_handle);
}
int64_t NativeEntityActor::entity_handle(const Ref<NativeEntityStore> &store) const {
    // The hit proxy already owns identity. Never infer it from position or
    // expose a recycled handle, detached proxy or another world's store.
    return is_inside_tree() && store_.is_valid() && store==store_ &&
        store_->contains(handle_) ? handle_ : 0;
}
bool NativeEntityActor::bind_entity(const Ref<NativeEntityStore> &store,int64_t handle) {
    if(!is_inside_tree()||store.is_null()||!store->contains(handle))return false;
    stepped_before_=false;store_=store;handle_=handle;set_global_position(store_->get_position(handle));
    set_velocity(Vector3());store_->set_velocity(handle_,Vector3());return true;
}
// Same bounded up/forward/landing policy as player movement, adapted to a
// capsule-centred body (player bodies use feet origins). No velocity teleport
// through an obstacle: all three parts and the landing normal are checked.
bool NativeEntityActor::step_grounded(const Vector3 &velocity,double delta){
    const Vector3 horizontal=Vector3(velocity.x,0,velocity.z)*real_t(delta);
    const uint64_t frame=Engine::get_singleton()->get_physics_frames();
    const bool recent_step=stepped_before_ && frame>=step_frame_ && frame-step_frame_<=1;
    if(!stairs_enabled || (!is_on_floor() && !recent_step) || velocity.y>0 || horizontal.length_squared()<.000001 || horizontal.length()>.5)return false;
    const Transform3D start=get_global_transform();const float margin=get_safe_margin();
    if(!test_move(start,horizontal,{},margin) || test_move(start,Vector3(0,.3,0),{},margin))return false;
    Transform3D raised=start;raised.origin.y+=.3;
    if(test_move(raised,horizontal,{},margin))return false;
    raised.origin+=horizontal;
    if(step_collision_.is_null())step_collision_.instantiate();
    if(!test_move(raised,Vector3(0,-.35,0),step_collision_,margin))return false;
    bool supported=step_collision_->get_normal().y>=.85;
    if(!supported && step_collision_->get_normal().y>0){
        if(step_support_.is_null())step_support_.instantiate();
        Vector3 probe=raised.origin-Vector3(0,.9,0)+horizontal.normalized()*.35;
        step_support_->set_from(probe);step_support_->set_to(probe-Vector3(0,.35,0));
        step_support_->set_collision_mask(get_collision_mask());
        TypedArray<RID> exclude;exclude.push_back(get_rid());step_support_->set_exclude(exclude);
        Dictionary hit=get_world_3d()->get_direct_space_state()->intersect_ray(step_support_);
        supported=hit.has("normal") && Vector3(hit["normal"]).y>=.85;
    }
    Vector3 landing=raised.origin+step_collision_->get_travel();real_t rise=landing.y-start.origin.y;
    if(!supported || rise<=.001 || rise>.301)return false;
    raised.origin=landing;set_global_transform(raised);set_velocity(Vector3(0,-1,0));move_and_slide();
    set_velocity(Vector3(velocity.x,get_velocity().y,velocity.z));step_frame_=frame;stepped_before_=true;return true;
}
bool NativeEntityActor::tick(const Vector3 &target,double delta,bool collision_ready) {
    transform_us=motion_us=store_us=0;
    if(!is_inside_tree()||store_.is_null()||!store_->contains(handle_)||!target.is_finite()||
       !std::isfinite(delta)||delta<=0||delta>0.1)return false;
    if(!collision_ready){set_velocity(Vector3());return false;}
    // External authority corrections must be reflected before the next collision step.
    const uint64_t correction_begin=profile_tick?Time::get_singleton()->get_ticks_usec():0;
    const Vector3 authoritative=store_->get_position(handle_);
    if(get_global_position()!=authoritative)set_global_position(authoritative);
    if(profile_tick)transform_us=Time::get_singleton()->get_ticks_usec()-correction_begin;
    Vector3 direction=target-get_global_position();direction.y=0;
    const real_t distance=direction.length();
    Vector3 velocity;
    if(distance>arrival_distance)velocity=direction/distance*real_t(std::min(2.5,double(distance)/delta));
    velocity.y=is_on_floor()?0:get_velocity().y-real_t(20.0*delta);
    const uint64_t motion_begin=profile_tick?Time::get_singleton()->get_ticks_usec():0;
    set_velocity(velocity);
    const bool approaching_step=target.y-get_global_position().y>.08 || is_on_wall();
    if(!approaching_step || !step_grounded(velocity,delta))move_and_slide();
    const uint64_t motion_done=profile_tick?Time::get_singleton()->get_ticks_usec():0;
    if(profile_tick)motion_us=motion_done-motion_begin;
    // The body owns integration while active, preventing a second kinematic store tick.
    const bool updated=store_->set_position(handle_,get_global_position());
    if(profile_tick)store_us=Time::get_singleton()->get_ticks_usec()-motion_done;
    return updated;
}
}
