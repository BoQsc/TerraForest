// SPDX-License-Identifier: 0BSD
#include "camera.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeVehicleCamera::_bind_methods(){ClassDB::bind_method(D_METHOD("update","body","camera","delta"),&NativeVehicleCamera::update);}
NativeVehicleCamera::NativeVehicleCamera(){
    shape.instantiate();shape->set_radius(.25);
    query.instantiate();query->set_shape(shape);query->set_margin(.05);query->set_collision_mask(7);
}
bool NativeVehicleCamera::update(RigidBody3D *body,Camera3D *camera,double delta){
    if(!body||!camera||!body->is_inside_tree()||!camera->is_inside_tree()||!std::isfinite(delta)||delta<=0)return false;
    auto world=body->get_world_3d();if(world.is_null()||world!=camera->get_world_3d())return false;
    auto *space=world->get_direct_space_state();if(!space)return false;
    Vector3 at=body->get_global_position(),current=camera->get_global_position();
    if(!at.is_finite()||!current.is_finite())return false;
    Vector3 forward=body->get_global_transform().basis.get_column(2);forward.y=0;
    forward=forward.length_squared()<.0001?Vector3(0,0,1):forward.normalized();
    Vector3 anchor=at+Vector3(0,.65,0),desired=at-forward*7.2+Vector3(0,3,0);
    Vector3 candidate=current.lerp(desired,real_t(1-std::exp(-7.5*std::min(delta,.1))));
    TypedArray<RID> excluded;excluded.push_back(body->get_rid());query->set_exclude(excluded);
    query->set_transform(Transform3D(Basis(),anchor));query->set_motion(Vector3());
    // A sweep cannot solve an anchor already embedded in world collision.
    // Report that condition rather than claiming an unobstructed camera pose.
    if(!space->intersect_shape(query,1).is_empty())return false;
    Vector3 motion=candidate-anchor;query->set_motion(motion);
    PackedFloat32Array fractions=space->cast_motion(query);
    if(fractions.size()!=2||!std::isfinite(fractions[0]))return false;
    Vector3 position=anchor+motion*std::clamp(fractions[0],0.f,1.f);
    camera->set_global_position(position);
    Vector3 look=anchor+forward*1.8;
    if(position.distance_squared_to(look)>.0001)camera->look_at(look,Vector3(0,1,0));
    return true;
}
}
