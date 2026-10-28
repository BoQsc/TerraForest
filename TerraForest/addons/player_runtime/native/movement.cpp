// SPDX-License-Identifier: 0BSD
#include "movement.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
namespace terraforest {
using namespace godot;
void NativePlayerMovement::_bind_methods() {
    ClassDB::bind_method(D_METHOD("update_crouch","body","requested"),&NativePlayerMovement::update_crouch);
    ClassDB::bind_method(D_METHOD("configure_ladders","collection"),&NativePlayerMovement::configure_ladders);
    ClassDB::bind_method(D_METHOD("ladder_velocity","body","direction","delta","jump"),&NativePlayerMovement::ladder_velocity);
    ClassDB::bind_method(D_METHOD("move_grounded","body","delta"),&NativePlayerMovement::move_grounded);
    ClassDB::bind_method(D_METHOD("set_step_radius","radius"),&NativePlayerMovement::set_step_radius);
    ClassDB::bind_method(D_METHOD("swimming_velocity","direction","previous","vertical","depth","delta","sprint"),&NativePlayerMovement::swimming_velocity);
    ClassDB::bind_method(D_METHOD("walking_velocity","direction","previous","delta","sprint","grounded","jump","crouched"),&NativePlayerMovement::walking_velocity,DEFVAL(false));
    ClassDB::bind_method(D_METHOD("flight_displacement","direction","vertical","delta","sprint"),&NativePlayerMovement::flight_displacement);
}
void NativePlayerMovement::configure_ladders(Node3D *collection) {
    ladder_collection_=collection?collection->get_instance_id():ObjectID();
    ladder_detach_=0;
}
bool NativePlayerMovement::ladder_velocity(CharacterBody3D *body,Vector3 direction,double delta,bool jump) {
    if(!body||!body->is_inside_tree()||!valid(delta,direction))return false;
    ladder_detach_=std::max(0.0,ladder_detach_-delta);
    auto *collection=Object::cast_to<Node3D>(ObjectDB::get_instance(ladder_collection_));
    if(!collection||ladder_detach_>0)return false;
    // At most two short rays, independent of total world placement count. The
    // first collider also prevents attaching through walls or unloaded proxies.
    Vector3 forward=-body->get_global_basis().get_column(2);forward.y=0;
    if(forward.length_squared()<0.5)return false;
    forward.normalize();
    if(ladder_probe_.is_null())ladder_probe_.instantiate();
    Vector3 from=body->get_global_position()+Vector3(0,0.15,0);
    ladder_probe_->set_from(from);ladder_probe_->set_to(from+forward*0.85);
    ladder_probe_->set_collision_mask(body->get_collision_mask());
    TypedArray<RID> exclude;exclude.push_back(body->get_rid());ladder_probe_->set_exclude(exclude);
    Dictionary hit=body->get_world_3d()->get_direct_space_state()->intersect_ray(ladder_probe_);
    // The lower probe keeps the last rung reachable while stepping above it.
    if(hit.is_empty()) {
        from.y-=0.45;ladder_probe_->set_from(from);ladder_probe_->set_to(from+forward*0.85);
        hit=body->get_world_3d()->get_direct_space_state()->intersect_ray(ladder_probe_);
    }
    Object *collider=hit.get("collider",Variant());
    if(collider!=collection)return false;
    int64_t id=collection->call("placement_for_body",hit["rid"]);
    PackedFloat32Array p=collection->call("get_instance",id);
    if(p.size()!=12)return false;
    Transform3D frame(Basis(p[0],p[1],p[2],p[4],p[5],p[6],p[8],p[9],p[10]),Vector3(p[3],p[7],p[11]));
    frame=collection->get_global_transform()*frame;
    // Upright ladders may vary in height; width/depth stay unit scale so the
    // collision probe and attachment corridor retain their physical dimensions.
    const double height_scale=frame.basis.get_column(1).y;
    if(!frame.is_finite()||height_scale<0.25||height_scale>4.0||
       frame.basis.get_column(1).distance_to(Vector3(0,height_scale,0))>0.001||
       std::abs(frame.basis.determinant()-height_scale)>0.001||
       std::abs(frame.basis.get_column(0).length()-1)>0.001||
       std::abs(frame.basis.get_column(2).length()-1)>0.001)return false;
    Vector3 local=frame.affine_inverse().xform(body->get_global_position());
    Vector3 normal=frame.basis.get_column(2),side=frame.basis.get_column(0);
    if(std::abs(local.x)>0.44||local.y<-.15||local.y>3.85||local.z<0.30||local.z>0.9||forward.dot(-normal)<0.5)return false;
    if(jump) {body->set_velocity(normal*3+Vector3(0,5,0));ladder_detach_=0.35;return true;}
    double rise=std::clamp(double(direction.dot(-normal)),-1.0,1.0);
    Vector3 velocity=side*real_t(std::clamp(double(direction.dot(side)),-1.0,1.0)*2)+Vector3(0,rise*2,0);
    // Above the landing, continue inward while collision still resolves walls
    // and ceilings. No teleport or collision bypass is used for the exit.
    if(local.y>3.05&&rise>0)velocity-=normal*2;
    body->set_velocity(velocity);return true;
}
bool NativePlayerMovement::update_crouch(CharacterBody3D *body,bool requested){
    if(!body||!body->is_inside_tree())return false;
    CollisionShape3D *collider=Object::cast_to<CollisionShape3D>(ObjectDB::get_instance(stance_collider_));
    if(uint64_t(stance_body_)!=body->get_instance_id()||!collider){
        collider=nullptr;
        for(int child=0;child<body->get_child_count();child++){
            auto *candidate=Object::cast_to<CollisionShape3D>(body->get_child(child));
            if(candidate&&Object::cast_to<CapsuleShape3D>(candidate->get_shape().ptr())){collider=candidate;break;}
        }
        if(!collider)return false;
        auto *capsule=Object::cast_to<CapsuleShape3D>(collider->get_shape().ptr());
        stance_body_=body->get_instance_id();stance_collider_=collider->get_instance_id();
        standing_height_=capsule->get_height();standing_center_=collider->get_position();crouched_=false;
        standing_shape_.instantiate();standing_shape_->set_radius(capsule->get_radius());standing_shape_->set_height(standing_height_);
        stance_query_.instantiate();stance_query_->set_shape(standing_shape_);
    }
    if(requested==crouched_)return crouched_;
    if(!requested){
        stance_query_->set_transform(body->get_global_transform()*Transform3D(collider->get_basis(),standing_center_));
        stance_query_->set_collision_mask(body->get_collision_mask());
        TypedArray<RID> excluded;excluded.push_back(body->get_rid());stance_query_->set_exclude(excluded);
        if(!body->get_world_3d()->get_direct_space_state()->intersect_shape(stance_query_,1).is_empty())return true;
    }
    auto *capsule=Object::cast_to<CapsuleShape3D>(collider->get_shape().ptr());
    if(!capsule)return crouched_;
    double height=requested?std::max(double(capsule->get_radius())*2.,standing_height_-.7):standing_height_;
    capsule->set_height(height);collider->set_position(standing_center_-Vector3(0,(standing_height_-height)*.5,0));
    crouched_=requested;return crouched_;
}
bool NativePlayerMovement::move_grounded(CharacterBody3D *body,double delta) {
    if(!body||!body->is_inside_tree()||!valid(delta,body->get_velocity()))return false;
    constexpr uint32_t ragdoll_layer=1<<18;
    auto *server=PhysicsServer3D::get_singleton();
    auto hits_ragdoll=[](const Ref<KinematicCollision3D> &collision){
        for(int contact=0;contact<collision->get_collision_count();contact++){
            auto *collider=Object::cast_to<PhysicsBody3D>(collision->get_collider(contact));
            if(collider&&(collider->get_collision_layer()&(1<<18))&&(!collider->has_method("is_resting")||!bool(collider->call("is_resting"))))return true;
        }
        return false;
    };
    for(int contact=0;contact<body->get_slide_collision_count();contact++){
        if(hits_ragdoll(body->get_slide_collision(contact))){body->move_and_slide();return false;}
    }
    const Vector3 velocity=body->get_velocity();
    const Vector3 horizontal=Vector3(velocity.x,0,velocity.z)*real_t(delta);
    bool stepped=false;
    // Capsule/riser contact can momentarily report a wall after a verified step.
    // Preserve that support for one tick only; jumping still rejects via velocity.y.
    const uint64_t frame=Engine::get_singleton()->get_physics_frames();
    const bool recent_step=uint64_t(step_body_)==body->get_instance_id() && frame>=step_frame_ && frame-step_frame_<=1;
    // Retain a verified tread while a rounded foot crosses its riser. Gravity
    // must not project the walker back down the steep corner between tiny ticks.
    // This assistance exists only after a swept step, with a tread under the
    // actual capsule's front and at the already reached elevation.
    if(recent_step&&!body->is_on_floor()&&velocity.y<=0&&horizontal.length_squared()>.000001&&horizontal.length()<=.5){
        if(step_support_.is_null())step_support_.instantiate();
        Vector3 probe=body->get_global_position()+horizontal.normalized()*real_t(step_radius_);
        step_support_->set_from(probe+Vector3(0,.02,0));step_support_->set_to(probe-Vector3(0,.04,0));
        step_support_->set_collision_mask(body->get_collision_mask());
        TypedArray<RID> exclude;exclude.push_back(body->get_rid());step_support_->set_exclude(exclude);
        Dictionary hit=body->get_world_3d()->get_direct_space_state()->intersect_ray(step_support_);
        Object *support=hit.get("collider",Variant());
        bool stable=!hit.is_empty()&&(!(server->body_get_collision_layer(hit["rid"])&ragdoll_layer)||(support&&support->has_method("is_resting")&&bool(support->call("is_resting"))));
        if(stable&&Vector3(hit["normal"]).y>=std::cos(body->get_floor_max_angle())&&
           !body->test_move(body->get_global_transform(),horizontal,{},body->get_safe_margin())){
            body->set_velocity(Vector3(velocity.x,0,velocity.z));body->move_and_slide();body->apply_floor_snap();
            step_frame_=frame;return false;
        }
    }
    if(velocity.y<=0&&horizontal.length_squared()>0.000001&&horizontal.length()<=0.5) {
        const Transform3D start=body->get_global_transform();
        const float margin=body->get_safe_margin();
        // Four bounded sweeps: obstacle, head clearance, raised travel, landing.
        // Refuse jumping, oversized tick travel, tall walls and unsupported gaps.
        if(step_collision_.is_null())step_collision_.instantiate();
        if(body->test_move(start,horizontal,step_collision_,margin,false,4)) {
            if(hits_ragdoll(step_collision_)){body->move_and_slide();return false;}
            double step_height=.3;
            for(int contact=0;contact<step_collision_->get_collision_count();contact++){
                auto *collider=Object::cast_to<PhysicsBody3D>(step_collision_->get_collider(contact));
                if(collider&&(collider->get_collision_layer()&ragdoll_layer))step_height=.55;
            }
            if(body->test_move(start,Vector3(0,step_height,0),{},margin)){body->move_and_slide();return false;}
            // A rounded capsule can lose is_on_floor while touching a riser,
            // including a tick without an attempted step. Require nearby actual
            // walkable support instead of allowing that transient flag to
            // deadlock the staircase. Falling through a gap is still rejected.
            if(!body->is_on_floor()&&!recent_step) {
                if(step_support_.is_null())step_support_.instantiate();
                step_support_->set_from(start.origin+Vector3(0,.01,0));
                step_support_->set_to(start.origin-Vector3(0,.3,0));
                step_support_->set_collision_mask(body->get_collision_mask());
                TypedArray<RID> exclude;exclude.push_back(body->get_rid());step_support_->set_exclude(exclude);
                Dictionary hit=body->get_world_3d()->get_direct_space_state()->intersect_ray(step_support_);
                if(hit.is_empty()||Vector3(hit["normal"]).y<std::cos(body->get_floor_max_angle())) {
                    body->move_and_slide();return false;
                }
            }
            Transform3D raised=start;raised.origin.y+=step_height;
            if(!body->test_move(raised,horizontal,{},margin)) {
                raised.origin+=horizontal;
                if(step_collision_.is_null())step_collision_.instantiate();
                if(body->test_move(raised,Vector3(0,-step_height-.05,0),step_collision_,margin,false,4)) {
                    if(hits_ragdoll(step_collision_)){body->move_and_slide();return false;}
                    bool supported=step_collision_->get_normal().y>=std::cos(body->get_floor_max_angle());
                    // Capsule/riser corner normals differ from tread normals.
                    // Confirm the tread under the front of the 0.34 m capsule;
                    // do not relax the player's walkable surface angle.
                    Vector3 tread;bool has_tread=false;
                    if(!supported) {
                        if(step_support_.is_null())step_support_.instantiate();
                        Vector3 probe=raised.origin+horizontal.normalized()*real_t(step_radius_);
                        step_support_->set_from(probe);step_support_->set_to(probe-Vector3(0,step_height+.05,0));
                        step_support_->set_collision_mask(body->get_collision_mask());
                        TypedArray<RID> exclude;exclude.push_back(body->get_rid());step_support_->set_exclude(exclude);
                        Dictionary hit=body->get_world_3d()->get_direct_space_state()->intersect_ray(step_support_);
                        if(hit.has("normal")){
                            supported=Vector3(hit["normal"]).y>=std::cos(body->get_floor_max_angle());
                            if(supported){tread=hit["position"];has_tread=true;}
                        }
                        // Rough terrain may put the forward rim on a steep
                        // facet while the proposed foot centre still has a
                        // walkable tread. Qualify that tread independently;
                        // capsule up/travel/landing sweeps remain mandatory.
                        if(!supported){
                            step_support_->set_from(raised.origin);
                            step_support_->set_to(raised.origin-Vector3(0,step_height+.3,0));
                            hit=body->get_world_3d()->get_direct_space_state()->intersect_ray(step_support_);
                            if(hit.has("normal")){
                                supported=Vector3(hit["normal"]).y>=std::cos(body->get_floor_max_angle());
                                if(supported){tread=hit["position"];has_tread=true;}
                            }
                        }
                    }
                    Vector3 landing=raised.origin+step_collision_->get_travel();
                    // Stay above the first swept contact, at the verified tread
                    // elevation. Never exceed the already cleared lift.
                    if(has_tread)landing.y=std::min(raised.origin.y,std::max(landing.y,tread.y+margin));
                    const real_t rise=landing.y-start.origin.y;
                    bool corpse_landing=false;
                    for(int contact=0;contact<step_collision_->get_collision_count();contact++){
                        auto *collider=Object::cast_to<PhysicsBody3D>(step_collision_->get_collider(contact));
                        if(collider&&(collider->get_collision_layer()&ragdoll_layer))corpse_landing=true;
                    }
                    if(supported&&rise>0.001&&rise<=step_height+.001&&(rise<=.301||corpse_landing)) {
                        raised.origin=landing;body->set_global_transform(raised);
                        // The landing sweep already integrated the downward
                        // part of this step. A second downward velocity projects
                        // against a steep riser normal and slides the capsule
                        // backwards farther than a slow walker advanced.
                        body->set_velocity(Vector3());body->move_and_slide();
                        body->set_velocity(Vector3(velocity.x,body->get_velocity().y,velocity.z));
                        stepped=true;step_frame_=frame;step_body_=body->get_instance_id();
                    }
                }
            }
        }
    }
    if(!stepped)body->move_and_slide();
    return stepped;
}
}
