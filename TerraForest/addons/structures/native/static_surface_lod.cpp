// SPDX-License-Identifier: 0BSD
#include "static_batch.hpp"
#include <godot_cpp/classes/camera3d.hpp>
#include <godot_cpp/classes/viewport.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <algorithm>
#include <cmath>

namespace terraforest {
// Optional removal of inactive surfaces, independent of residency and instance
// buffers. The caller supplies equivalent one-surface meshes either side of a
// shared ArrayMesh error threshold. The original remains the boundary fallback.
bool NativeStaticBatch::configure_surface_lod(const Ref<Mesh> &near_mesh,const Ref<Mesh> &far_mesh,double error) {
    if(!std::isfinite(error)||error<0)return false;
    const Ref<ArrayMesh> full=source_mesh,near_array=near_mesh,far_array=far_mesh;
    if(error>0&&(source_mesh.is_null()||source_mesh->get_surface_count()!=2||
        near_mesh.is_null()||far_mesh.is_null()||near_mesh->get_surface_count()!=1||far_mesh->get_surface_count()!=1||
        full.is_null()||near_array.is_null()||far_array.is_null()||full->get_custom_aabb().size==Vector3()||
        near_array->get_custom_aabb()!=full->get_custom_aabb()||far_array->get_custom_aabb()!=full->get_custom_aabb()))return false;
    const double begin=error>0&&source_mesh.is_valid()?double(source_mesh->get_meta("surface_lod_begin",error)):error;
    if(!std::isfinite(begin)||begin<0||begin>error)return false;
    surface_lod_near=near_mesh;surface_lod_far=far_mesh;surface_lod_error=error;
    surface_lod_dirty=true;
    for(auto &entry:batches)entry.second->get_multimesh()->set_mesh(source_mesh);
    update_surface_lod();return true;
}

void NativeStaticBatch::update_surface_lod() {
    if(surface_lod_error<=0||!is_inside_tree())return;
    auto *viewport=get_viewport();auto *camera=viewport->get_camera_3d();
    // Unsupported views use the unchanged two-surface mesh. Keep engine debug
    // LOD controls and orthographic inspection independent of this optimization.
    const bool perspective=camera&&camera->get_projection()==Camera3D::PROJECTION_PERSPECTIVE;
    const double pixels=viewport->get_mesh_lod_threshold();
    const double width=viewport->get_visible_rect().size.x;
    const double scaling=ProjectSettings::get_singleton()->get_setting("rendering/scaling_3d/scale",1.0);
    const bool enabled=perspective&&pixels>0&&width>0&&scaling>0&&
        viewport->get_debug_draw()==Viewport::DEBUG_DRAW_DISABLED;
    const Vector3 eye=camera?camera->get_global_position():Vector3();
    // Godot 4.7's perspective LOD test uses distance to the batch AABB, the
    // projection's LOD multiplier, viewport width and the global render scale.
    const double distance_per_error=enabled?width*scaling/(pixels*camera->get_camera_projection().get_lod_multiplier()):0;
    const Transform3D parent_transform=get_global_transform();
    // Half-metre motion reuse fits entirely inside the one-metre boundary guard.
    // New/rebuilt pages, shadow policy, zoom, resolution and parent transforms
    // invalidate immediately; no per-instance CPU work is introduced.
    if(!surface_lod_dirty&&surface_lod_uploads==uploads&&surface_lod_metric==distance_per_error&&
        surface_lod_transform==parent_transform&&surface_lod_eye.distance_squared_to(eye)<0.25)return;
    surface_lod_dirty=false;surface_lod_uploads=uploads;surface_lod_metric=distance_per_error;
    surface_lod_eye=eye;surface_lod_transform=parent_transform;
    // Per-root blends need both surfaces when ANY part of a page reaches the
    // incoming band. The original end cutoff still retires opaque geometry.
    const double begin=double(source_mesh->get_meta("surface_lod_begin",surface_lod_error));
    const bool overlap=begin<surface_lod_error;
    for(auto &entry:batches) {
        auto *instance=entry.second;Ref<MultiMesh> multi=instance->get_multimesh();
        Ref<Mesh> desired=source_mesh;
        if(enabled) {
            const Transform3D transform=instance->get_global_transform();
            const AABB box=transform.xform(multi->get_aabb());
            const Vector3 end=box.get_end();
            const Vector3 closest(std::clamp(eye.x,box.position.x,end.x),std::clamp(eye.y,box.position.y,end.y),std::clamp(eye.z,box.position.z,end.z));
            const Vector3 scale=transform.basis.get_scale().abs();
            const double threshold=surface_lod_error*distance_per_error*std::max({scale.x,scale.y,scale.z})*instance->get_lod_bias();
            const double distance=eye.distance_to(closest);
            // A one-metre guard keeps floating-point boundary differences on the
            // original mesh. Shadow-casting pages also retain the opaque caster.
            const Vector3 farthest(std::abs(eye.x-box.position.x)>std::abs(eye.x-end.x)?box.position.x:end.x,
                std::abs(eye.y-box.position.y)>std::abs(eye.y-end.y)?box.position.y:end.y,
                std::abs(eye.z-box.position.z)>std::abs(eye.z-end.z)?box.position.z:end.z);
            const double near_distance=overlap?eye.distance_to(farthest):distance;
            const double near_threshold=threshold*(begin/surface_lod_error);
            if(near_distance<near_threshold-1.0)desired=surface_lod_near;
            else if(distance>threshold+1.0&&instance->get_cast_shadows_setting()==GeometryInstance3D::SHADOW_CASTING_SETTING_OFF)desired=surface_lod_far;
        }
        if(multi->get_mesh()!=desired)multi->set_mesh(desired);
    }
}
}
