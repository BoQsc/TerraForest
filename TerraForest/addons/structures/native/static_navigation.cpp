// SPDX-License-Identifier: 0BSD
#include "static_batch.hpp"
namespace terraforest {
AABB NativeStaticBatch::placement_obstacle_bounds(const Placement &placement)const{
    const Transform3D frame=is_inside_tree()?get_global_transform():get_transform();
    const AABB prototype=proxy_parts.empty()?(source_mesh.is_valid()?source_mesh->get_aabb():AABB()):proxy_box;
    return (frame*placement_transform(placement)).xform(prototype);
}
AABB NativeStaticBatch::instance_obstacle_bounds(int64_t id)const{
    auto found=placements.find(id);
    return found==placements.end()?AABB():placement_obstacle_bounds(found->second);
}
void NativeStaticBatch::publish_exclusion(const AABB &bounds){
    const auto identity=get_instance_id();
    emit_signal("obstacles_changed",bounds);
    if(auto *live=ObjectDB::get_instance(identity))live->emit_signal("exclusion_region_changed",bounds);
    if(auto *live=ObjectDB::get_instance(identity))live->emit_signal("exclusion_changed");
}
void NativeStaticBatch::publish_notifications(bool notify_exclusion){
    const auto identity=get_instance_id();
    const bool notify_obstacles=pending_obstacles;
    const AABB bounds=pending_obstacles_global?AABB():pending_obstacle_bounds;
    // Consume before callbacks: a reentrant edit owns its own notification.
    pending_obstacles=pending_obstacles_global=false;pending_obstacle_bounds=AABB();
    emit_signal("changed");
    if(notify_obstacles)if(auto *live=ObjectDB::get_instance(identity))live->emit_signal("obstacles_changed",bounds);
    if(notify_exclusion){
        if(auto *live=ObjectDB::get_instance(identity))live->emit_signal("exclusion_region_changed",bounds);
        if(auto *live=ObjectDB::get_instance(identity))live->emit_signal("exclusion_changed");
    }
}
void NativeStaticBatch::publish_change(bool storage_only,bool notify_exclusion,const AABB &bounds){
    if(!storage_only)survey_saved_identity=String();
    ++edit_revision;
    // Residency-only transfers retain authoritative geometry. Motion changes
    // collision now even when vegetation exclusion waits for the resting pose.
    if(!storage_only||notify_exclusion){
        const bool global=bounds.size==Vector3()||!bounds.position.is_finite()||!bounds.size.is_finite();
        if(!global)pending_obstacle_bounds=pending_obstacles?pending_obstacle_bounds.merge(bounds):bounds;
        pending_obstacles=true;pending_obstacles_global|=global;
    }
    if(!defer_change_signal)publish_notifications(notify_exclusion);
}
}
