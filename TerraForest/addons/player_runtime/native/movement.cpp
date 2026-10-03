// SPDX-License-Identifier: 0BSD
#include "movement.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
namespace terraforest {
using namespace godot;
void NativePlayerMovement::_bind_methods() {
    ClassDB::bind_method(D_METHOD("move_grounded","body","delta"),&NativePlayerMovement::move_grounded);
    ClassDB::bind_method(D_METHOD("swimming_velocity","direction","previous","vertical","depth","delta","sprint"),&NativePlayerMovement::swimming_velocity);
    ClassDB::bind_method(D_METHOD("walking_velocity","direction","previous","delta","sprint","grounded","jump"),&NativePlayerMovement::walking_velocity);
    ClassDB::bind_method(D_METHOD("flight_displacement","direction","vertical","delta","sprint"),&NativePlayerMovement::flight_displacement);
}
bool NativePlayerMovement::move_grounded(CharacterBody3D *body,double delta) {
    if(!body||!body->is_inside_tree()||!valid(delta,body->get_velocity()))return false;
    const Vector3 velocity=body->get_velocity();
    const Vector3 horizontal=Vector3(velocity.x,0,velocity.z)*real_t(delta);
    bool stepped=false;
    if(body->is_on_floor()&&velocity.y<=0&&horizontal.length_squared()>0.000001&&horizontal.length()<=0.5) {
        const Transform3D start=body->get_global_transform();
        const float margin=body->get_safe_margin();
        // Four bounded sweeps: obstacle, head clearance, raised travel, landing.
        // Refuse jumping, oversized tick travel, tall walls and unsupported gaps.
        if(body->test_move(start,horizontal,{},margin)&&!body->test_move(start,Vector3(0,0.3,0),{},margin)) {
            Transform3D raised=start;raised.origin.y+=0.3;
            if(!body->test_move(raised,horizontal,{},margin)) {
                raised.origin+=horizontal;
                if(step_collision_.is_null())step_collision_.instantiate();
                if(body->test_move(raised,Vector3(0,-0.35,0),step_collision_,margin)) {
                    bool supported=step_collision_->get_normal().y>=std::cos(body->get_floor_max_angle());
                    // Capsule/riser corner normals differ from tread normals.
                    // Confirm the tread under the front of the 0.34 m capsule;
                    // do not relax the player's walkable surface angle.
                    if(!supported&&step_collision_->get_normal().y>0) {
                        if(step_support_.is_null())step_support_.instantiate();
                        Vector3 probe=raised.origin+horizontal.normalized()*0.34;
                        step_support_->set_from(probe);step_support_->set_to(probe-Vector3(0,0.35,0));
                        step_support_->set_collision_mask(body->get_collision_mask());
                        TypedArray<RID> exclude;exclude.push_back(body->get_rid());step_support_->set_exclude(exclude);
                        Dictionary hit=body->get_world_3d()->get_direct_space_state()->intersect_ray(step_support_);
                        if(hit.has("normal"))supported=Vector3(hit["normal"]).y>=std::cos(body->get_floor_max_angle());
                    }
                    const Vector3 landing=raised.origin+step_collision_->get_travel();
                    const real_t rise=landing.y-start.origin.y;
                    if(supported&&rise>0.001&&rise<=0.301) {
                        raised.origin=landing;body->set_global_transform(raised);
                        body->set_velocity(Vector3(0,-1,0));body->move_and_slide();
                        body->set_velocity(Vector3(velocity.x,body->get_velocity().y,velocity.z));
                        stepped=true;
                    }
                }
            }
        }
    }
    if(!stepped)body->move_and_slide();
    return stepped;
}
}
