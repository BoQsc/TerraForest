// SPDX-License-Identifier: 0BSD
#include "zombie_posture.hpp"
#include "zombie_sleep_state.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeZombiePosture::_bind_methods(){
    ClassDB::bind_method(D_METHOD("apply_bounds","body","collider","bounds"),&NativeZombiePosture::apply_bounds);
    ClassDB::bind_method(D_METHOD("restore_capsule","body","collider","shape","local"),&NativeZombiePosture::restore_capsule);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeZombiePosture::statistics);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeZombiePosture::validate_snapshot);
}
NativeZombiePosture::NativeZombiePosture(){probe_.instantiate();proxy_.instantiate();query_.instantiate();query_->set_collide_with_areas(false);query_->set_margin(.001);}
bool NativeZombiePosture::clear(CharacterBody3D *body,const Ref<Shape3D> &shape,const Transform3D &local){
    if(!body||!body->is_inside_tree()||!body->get_collision_mask()||!local.is_finite()||!body->get_global_transform().is_finite())return false;
    Ref<World3D> world=body->get_world_3d();if(world.is_null()||!world->get_direct_space_state())return false;
    TypedArray<RID> exclusions;exclusions.push_back(body->get_rid());
    query_->set_exclude(exclusions);query_->set_collision_mask(body->get_collision_mask());
    if(query_->get_shape().ptr()!=shape.ptr())query_->set_shape(shape);
    query_->set_transform(body->get_global_transform()*local);++queries_;
    const bool free=world->get_direct_space_state()->intersect_shape(query_,1).is_empty();
    if(!free)++blocked_;return free;
}
bool NativeZombiePosture::apply_bounds(CharacterBody3D *body,CollisionShape3D *collider,const AABB &bounds){
    if(!body||!collider||collider->get_parent()!=body||!bounds.position.is_finite()||!bounds.size.is_finite())return false;
    const Vector3 end=bounds.get_end();
    if(bounds.size.x<=0||bounds.size.z<=0||bounds.size.y<=0||bounds.size.x>4||bounds.size.z>4||bounds.position.length()>4||end.y<=.04||end.y>3)return false;
    const Vector3 size(bounds.size.x,end.y,bounds.size.z),center(bounds.position.x+size.x*.5,size.y*.5,bounds.position.z+size.z*.5);
    const Vector3 probe_size(size.x,size.y-.012,size.z);
    if(probe_->get_size()!=probe_size)probe_->set_size(probe_size);
    if(!clear(body,probe_,Transform3D(Basis(),center+Vector3(0,.006,0))))return false;
    if(proxy_->get_size()!=size)proxy_->set_size(size);
    if(collider->get_shape().ptr()!=proxy_.ptr())collider->set_shape(proxy_);
    const Transform3D transform(Basis(),center);
    if(collider->get_transform()!=transform)collider->set_transform(transform);
    return true;
}
bool NativeZombiePosture::restore_capsule(CharacterBody3D *body,CollisionShape3D *collider,const Ref<CapsuleShape3D> &shape,const Transform3D &local){
    if(!body||!collider||collider->get_parent()!=body||shape.is_null()||!local.is_finite()||local.origin.length()>3||shape->get_radius()<=0||shape->get_radius()>1||shape->get_height()>3)return false;
    Transform3D probe=local;probe.origin.y+=.012;
    if(!clear(body,shape,probe))return false;
    collider->set_shape(shape);collider->set_transform(local);return true;
}
Dictionary NativeZombiePosture::statistics()const{Dictionary out;out["queries"]=queries_;out["blocked"]=blocked_;return out;}
bool NativeZombiePosture::validate_snapshot(const PackedByteArray &bytes)const{return !bytes.is_empty()&&valid_sleep_state(bytes);}
}
