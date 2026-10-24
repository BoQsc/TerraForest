// SPDX-License-Identifier: 0BSD
#include "zombie_anatomy.hpp"
#include "zombie_rest_body.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/skin.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/classes/physics_direct_body_state3d.hpp>
#include <godot_cpp/classes/physical_bone3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/joint3d.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
namespace {
constexpr const char *NAMES[]={"torso","head","upper_arm_l","forearm_l","hand_l","upper_arm_r","forearm_r","hand_r","thigh_l","shin_l","foot_l","thigh_r","shin_r","foot_r"};
bool triangle(Vector3 from,Vector3 direction,Vector3 a,Vector3 b,Vector3 c,double &fraction,Vector3 &normal){
    Vector3 edge=b-a,other=c-a,h=direction.cross(other);double determinant=edge.dot(h);
    if(std::abs(determinant)<1e-10)return false;
    double inverse=1/determinant;Vector3 s=from-a;double u=inverse*s.dot(h);
    if(u<-1e-6||u>1+1e-6)return false;
    Vector3 q=s.cross(edge);double v=inverse*direction.dot(q);
    if(v<-1e-6||u+v>1+1e-6)return false;
    double t=inverse*other.dot(q);if(t<0||t>fraction)return false;
    fraction=t;normal=edge.cross(other).normalized();if(normal.dot(direction)>0)normal=-normal;return true;
}
}
void NativeZombieAnatomy::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","definitions"),&NativeZombieAnatomy::configure);
    ClassDB::bind_method(D_METHOD("set_hit_meshes","skeleton","meshes"),&NativeZombieAnatomy::set_hit_meshes);
    ClassDB::bind_method(D_METHOD("hit","part","damage","force_sever","impact"),&NativeZombieAnatomy::hit,DEFVAL(false),DEFVAL(String("melee")));
    ClassDB::bind_method(D_METHOD("detach","part"),&NativeZombieAnatomy::detach);
    ClassDB::bind_method(D_METHOD("kill"),&NativeZombieAnatomy::kill);
    ClassDB::bind_method(D_METHOD("snapshot"),&NativeZombieAnatomy::snapshot);
    ClassDB::bind_method(D_METHOD("pick","from","to"),&NativeZombieAnatomy::pick);
    ClassDB::bind_method(D_METHOD("track_ragdoll","bodies"),&NativeZombieAnatomy::track_ragdoll);
    ClassDB::bind_method(D_METHOD("advance_ragdolls","delta"),&NativeZombieAnatomy::advance_ragdolls);
    ClassDB::bind_method(D_METHOD("wake_ragdolls","bounds"),&NativeZombieAnatomy::wake_ragdolls,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("ragdoll_stats"),&NativeZombieAnatomy::ragdoll_stats);
}
int NativeZombieAnatomy::part_index(const String &name){for(int i=0;i<14;i++)if(name==NAMES[i])return i;return -1;}
bool NativeZombieAnatomy::configure(const Dictionary &definitions){
    if(configured_||definitions.size()!=14)return false;
    std::array<Part,14> next;
    for(int i=0;i<14;i++){
        if(!definitions.has(NAMES[i])||definitions[NAMES[i]].get_type()!=Variant::DICTIONARY)return false;
        Dictionary row=definitions[NAMES[i]];double maximum=row.get("health",0.);
        String parent=row.get("parent","");int p=part_index(parent);
        if(!std::isfinite(maximum)||maximum<=0||maximum>10000||(i&&p<0)||p>=i)return false;
        next[i].maximum=next[i].health=maximum;next[i].parent=p;
    }
    parts_=std::move(next);maximum_=health_=parts_[0].maximum;configured_=true;return true;
}
bool NativeZombieAnatomy::set_hit_meshes(Skeleton3D *skeleton,const Dictionary &meshes){
    if(!configured_||skeleton_||!skeleton||skeleton->get_bone_count()>256||meshes.size()!=14)return false;
    auto next=parts_;int vertices=0,triangles=0;
    for(int i=0;i<14;i++){
        auto *node=Object::cast_to<MeshInstance3D>(meshes.get(NAMES[i],Variant()));
        if(!node||node->get_mesh().is_null())return false;
        auto &part=next[i];part.mesh=node->get_instance_id();Ref<Mesh> mesh=node->get_mesh();Ref<Skin> skin=node->get_skin();
        auto *array_mesh=Object::cast_to<ArrayMesh>(mesh.ptr());
        if(!array_mesh||mesh->get_surface_count()>8)return false;
        if(skin.is_valid())for(int j=0;j<skin->get_bind_count();j++){
            StringName name=skin->get_bind_name(j);int bone=name.is_empty()?skin->get_bind_bone(j):skeleton->find_bone(name);
            if(bone<0||bone>=skeleton->get_bone_count())return false;
            part.bone_ids.push_back(bone);part.binds.push_back(skin->get_bind_pose(j));
        }
        for(int s=0;s<mesh->get_surface_count();s++){
            if(array_mesh->surface_get_primitive_type(s)!=Mesh::PRIMITIVE_TRIANGLES)return false;
            Array arrays=mesh->surface_get_arrays(s);Surface surface;surface.vertices=arrays[Mesh::ARRAY_VERTEX];
            surface.indices=arrays[Mesh::ARRAY_INDEX];surface.bones=arrays[Mesh::ARRAY_BONES];surface.weights=arrays[Mesh::ARRAY_WEIGHTS];
            int count=surface.vertices.size();if(!count||count>32768)return false;
            if(surface.bones.size()!=surface.weights.size()||surface.bones.size()%count)return false;
            if(surface.bones.size()/count>8)return false;
            for(int j=0;j<surface.bones.size();j++)if(surface.bones[j]<0||surface.bones[j]>=int(part.binds.size())||!std::isfinite(surface.weights[j]))return false;
            for(int j=0;j<surface.indices.size();j++)if(surface.indices[j]<0||surface.indices[j]>=count)return false;
            for(int j=0;j<count;j++)if(!surface.vertices[j].is_finite())return false;
            if(array_mesh){
                Array morphs=array_mesh->surface_get_blend_shape_arrays(s);if(morphs.size()>16)return false;
                surface.relative=array_mesh->get_blend_shape_mode()==Mesh::BLEND_SHAPE_MODE_RELATIVE;
                for(int m=0;m<morphs.size();m++){
                    Array shape=morphs[m];PackedVector3Array positions=shape[Mesh::ARRAY_VERTEX];
                    if(positions.size()!=count)return false;surface.morphs.push_back(positions);
                }
            }
            vertices+=count;triangles+=(surface.indices.is_empty()?count:surface.indices.size())/3;
            if(vertices>131072||triangles>131072)return false;
            part.surfaces.push_back(std::move(surface));
        }
    }
    parts_=std::move(next);skeleton_=skeleton->get_instance_id();vertices_=vertices;triangles_=triangles;return true;
}
Dictionary NativeZombieAnatomy::hit(const String &name,double damage,bool force_sever,const String &impact){
    Dictionary out;out["ok"]=false;int index=part_index(name);
    if(!configured_||index<0||parts_[index].missing||!std::isfinite(damage)||damage<0||damage>1000000||(!damage&&!force_sever))return out;
    double sever_factor;
    if(impact=="unarmed")sever_factor=0;
    else if(impact=="melee")sever_factor=.3;
    else if(impact=="cutting")sever_factor=.5;
    else if(impact=="heavy"||impact=="firearm")sever_factor=1;
    else return out;
    if(health_<=0)wake_ragdolls();
    auto &part=parts_[index];double previous_health=health_;
    double limb_damage=index==0?0:std::min(part.health,damage*sever_factor);
    part.health=std::max(0.,part.health-limb_damage);
    health_=std::max(0.,health_-damage);
    bool sever=index!=0&&(force_sever||(sever_factor>0&&part.health<=0));
    if((index==1&&sever)||(index==0&&force_sever))health_=0;
    parts_[0].health=health_;double body_damage=previous_health-health_;
    out["ok"]=true;out["part"]=name;out["remaining"]=health_;out["applied"]=body_damage;
    out["limb_remaining"]=part.health;out["limb_damage"]=limb_damage;
    out["health"]=health_;out["maximum"]=maximum_;out["body_damage"]=body_damage;
    out["sever"]=sever;out["dead"]=health_<=0;return out;
}
bool NativeZombieAnatomy::detach(const String &name){
    int root=part_index(name);if(!configured_||root<0||parts_[root].missing)return false;
    if(root==0){kill();return true;}
    for(int i=root;i<14;i++)for(int ancestor=i;ancestor>=0;ancestor=parts_[ancestor].parent)if(ancestor==root){parts_[i].missing=true;parts_[i].health=0;break;}
    if(root==1)health_=parts_[0].health=0;return true;
}
void NativeZombieAnatomy::kill(){
    if(!configured_)return;
    health_=0;parts_[0].health=0;
    auto *skeleton=Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_));
    if(skeleton&&death_poses_.empty()){
        skeleton->force_update_all_bone_transforms();
        for(int i=0;i<skeleton->get_bone_count();i++)death_poses_.push_back(skeleton->get_bone_global_pose(i));
    }
}
Dictionary NativeZombieAnatomy::snapshot() const {
    Dictionary out,limbs,missing;out["health"]=health_;out["maximum"]=maximum_;out["alive"]=configured_&&health_>0;
    for(int i=0;i<14;i++){limbs[NAMES[i]]=parts_[i].health;missing[NAMES[i]]=parts_[i].missing;}
    out["limbs"]=limbs;out["missing"]=missing;out["vertices"]=vertices_;out["triangles"]=triangles_;return out;
}
Dictionary NativeZombieAnatomy::pick(Vector3 from,Vector3 to) const {
    Dictionary out;auto *skeleton=Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_));
    Vector3 direction=to-from;
    if(!skeleton||!from.is_finite()||!to.is_finite()||direction.length_squared()<1e-10||direction.length_squared()>128*128)return out;
    if(health_>0){
        if(from.distance_to(skeleton->get_global_position())>direction.length()+4)return out;
    }else{
        // Impacts can carry the corpse away from its retired character root.
        bool nearby=false;
        for(const auto &group:ragdolls_)for(uint64_t id:group.bodies){auto *body=Object::cast_to<PhysicalBone3D>(ObjectDB::get_instance(id));if(body&&from.distance_to(body->get_global_position())<=direction.length()+2)nearby=true;}
        if(!nearby)return out;
    }
    skeleton->force_update_all_bone_transforms();std::vector<Transform3D> poses(skeleton->get_bone_count());
    for(int i=0;i<int(poses.size());i++)poses[i]=skeleton->get_global_transform()*skeleton->get_bone_global_pose(i);
    if(health_<=0&&death_poses_.size()==poses.size()){
        std::vector<PhysicalBone3D*> physical(poses.size(),nullptr);
        for(const auto &group:ragdolls_)for(uint64_t id:group.bodies){
            auto *body=Object::cast_to<PhysicalBone3D>(ObjectDB::get_instance(id));
            if(body&&body->get_bone_id()>=0&&body->get_bone_id()<int(poses.size()))physical[body->get_bone_id()]=body;
        }
        for(int i=0;i<int(poses.size());i++){
            int ancestor=i;while(ancestor>=0&&!physical[ancestor])ancestor=skeleton->get_bone_parent(ancestor);
            if(ancestor>=0)poses[i]=physical[ancestor]->get_global_transform()*physical[ancestor]->get_body_offset().affine_inverse()*death_poses_[ancestor].affine_inverse()*death_poses_[i];
            else poses[i]=skeleton->get_global_transform()*death_poses_[i];
        }
    }
    double nearest=1.;Vector3 normal;int found=-1,work=0;
    for(int i=0;i<14;i++){
        const auto &part=parts_[i];auto *node=Object::cast_to<MeshInstance3D>(ObjectDB::get_instance(part.mesh));
        if(part.missing||!node||!node->is_visible_in_tree())continue;
        std::vector<Transform3D> binds(part.binds.size());for(int j=0;j<int(binds.size());j++)binds[j]=poses[part.bone_ids[j]]*part.binds[j];
        for(const auto &surface:part.surfaces){
            int count=surface.vertices.size(),influences=surface.bones.size()/count;std::vector<Vector3> positions(count);
            std::vector<double> morphs(surface.morphs.size());for(int m=0;m<int(morphs.size());m++)morphs[m]=node->get_blend_shape_value(m);
            AABB bounds;
            for(int v=0;v<count;v++){
                Vector3 vertex=surface.vertices[v],point;double total=0;
                for(int m=0;m<int(morphs.size());m++)if(std::isfinite(morphs[m])&&std::abs(morphs[m])>1e-6)vertex+=(surface.relative?surface.morphs[m][v]:surface.morphs[m][v]-surface.vertices[v])*morphs[m];
                for(int k=0;k<influences;k++){int slot=v*influences+k;double weight=surface.weights[slot];if(weight>0){point+=binds[surface.bones[slot]].xform(vertex)*weight;total+=weight;}}
                positions[v]=total>1e-5?point/total:node->get_global_transform().xform(vertex);
                if(v==0)bounds=AABB(positions[v],Vector3());else bounds.expand_to(positions[v]);
            }
            if(!bounds.grow(.002).intersects_segment(from,to))continue;
            int indices=surface.indices.is_empty()?count:surface.indices.size();
            for(int v=0;v+2<indices;v+=3){
                int a=surface.indices.is_empty()?v:surface.indices[v],b=surface.indices.is_empty()?v+1:surface.indices[v+1],c=surface.indices.is_empty()?v+2:surface.indices[v+2];
                work++;if(triangle(from,direction,positions[a],positions[b],positions[c],nearest,normal))found=i;
            }
        }
    }
    if(found>=0){out["part"]=NAMES[found];out["position"]=from+direction*nearest;out["normal"]=normal;out["fraction"]=nearest;out["triangles_tested"]=work;}
    return out;
}
bool NativeZombieAnatomy::track_ragdoll(const TypedArray<PhysicsBody3D> &bodies){
    if(bodies.is_empty()||bodies.size()>16||ragdolls_.size()>=16)return false;
    Ragdoll group;auto *server=PhysicsServer3D::get_singleton();
    for(int i=0;i<bodies.size();i++){
        PhysicsBody3D *body=Object::cast_to<PhysicsBody3D>(bodies[i]);if(!body)return false;
        group.bodies.push_back(body->get_instance_id());server->body_set_max_contacts_reported(body->get_rid(),4);
        if(auto *bone=Object::cast_to<PhysicalBone3D>(body)){
            if(bone->get_joint_type()!=PhysicalBone3D::JOINT_TYPE_NONE){
                JointState state;state.node=bone->get_instance_id();state.physical=true;state.type=bone->get_joint_type();
                Array properties=bone->get_property_list();
                for(int p=0;p<properties.size();p++){Dictionary row=properties[p];String name=row["name"];if(name.begins_with("joint_constraints/"))state.properties[name]=bone->get(name);}
                group.joints.push_back(std::move(state));
            }
        }
        for(int child=0;child<body->get_child_count();child++)if(auto *joint=Object::cast_to<Joint3D>(body->get_child(child))){
            JointState state;state.node=joint->get_instance_id();state.properties["node_a"]=joint->get_node_a();state.properties["node_b"]=joint->get_node_b();
            if(auto *second=Object::cast_to<PhysicsBody3D>(joint->get_node_or_null(joint->get_node_b()))){state.body_b=second->get_instance_id();state.frame_b=second->get_global_transform().affine_inverse()*joint->get_global_transform();}
            group.joints.push_back(std::move(state));
        }
    }
    ragdolls_.push_back(std::move(group));return true;
}
void NativeZombieAnatomy::park_constraints(Ragdoll &group,bool park){
    if(group.parked==park)return;
    for(const auto &state:group.joints){
        if(state.physical){
            auto *bone=Object::cast_to<PhysicalBone3D>(ObjectDB::get_instance(state.node));if(!bone)continue;
            bone->set_joint_type(park?PhysicalBone3D::JOINT_TYPE_NONE:PhysicalBone3D::JointType(state.type));
            if(!park){Array keys=state.properties.keys();for(int k=0;k<keys.size();k++)bone->set(keys[k],state.properties[keys[k]]);}
        }else{
            auto *joint=Object::cast_to<Joint3D>(ObjectDB::get_instance(state.node));if(!joint)continue;
            if(park)PhysicsServer3D::get_singleton()->joint_clear(joint->get_rid());
            else{
                if(auto *second=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(state.body_b)))joint->set_global_transform(second->get_global_transform()*state.frame_b);
                joint->set_node_a(NodePath());joint->set_node_a(state.properties["node_a"]);
            }
        }
    }
    group.parked=park;
}
void NativeZombieAnatomy::advance_ragdolls(double delta){
    if(!std::isfinite(delta)||delta<=0||delta>.25||ragdolls_.empty())return;
    auto *server=PhysicsServer3D::get_singleton();
    for(auto &group:ragdolls_)if(group.parked){
        bool impact=false;
        for(uint64_t id:group.bodies){auto *body=ObjectDB::get_instance(id);if(auto *bone=Object::cast_to<NativeZombiePhysicalBone>(body)){if(!bone->is_resting())impact=true;}if(auto *part=Object::cast_to<NativeZombieRigidPart>(body)){if(!part->is_resting())impact=true;}}
        if(impact){park_constraints(group,false);group.quiet=0;for(uint64_t id:group.bodies){auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(body){if(auto *bone=Object::cast_to<NativeZombiePhysicalBone>(body))bone->set_resting(false);if(auto *part=Object::cast_to<NativeZombieRigidPart>(body))part->set_resting(false);server->body_set_state(body->get_rid(),PhysicsServer3D::BODY_STATE_SLEEPING,false);}}}
        else for(uint64_t id:group.bodies){
            auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));
            // Scene/contact synchronization may renew an active flag after a
            // body's rest callback. Commit parked sleep after those callbacks;
            // meaningful impulses above already cleared the rest flag.
            if(body&&!bool(server->body_get_state(body->get_rid(),PhysicsServer3D::BODY_STATE_SLEEPING)))server->body_set_state(body->get_rid(),PhysicsServer3D::BODY_STATE_SLEEPING,true);
        }
    }
    ragdoll_clock_+=delta;if(ragdoll_clock_<.1)return;double elapsed=ragdoll_clock_;ragdoll_clock_=0;
    // Severed chains can rest against the corpse. Sleep their contact island
    // together so one resting fragment cannot repeatedly wake another group.
    const int count=ragdolls_.size();std::vector<int> parents(count);std::vector<bool> ground(count,false),quiet(count,true),awake(count,false);
    std::vector<std::pair<RID,int>> owners;
    for(int i=0;i<count;i++)parents[i]=i;
    for(int g=0;g<count;g++)for(uint64_t id:ragdolls_[g].bodies){auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(body)owners.push_back({body->get_rid(),g});}
    auto root=[&](int i){while(parents[i]!=i)i=parents[i];return i;};
    for(int index=0;index<count;index++){
        for(uint64_t id:ragdolls_[index].bodies){
            auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(!body)continue;
            RID rid=body->get_rid();awake[index]=awake[index]||!bool(server->body_get_state(rid,PhysicsServer3D::BODY_STATE_SLEEPING));
            Vector3 linear=server->body_get_state(rid,PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY),angular=server->body_get_state(rid,PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY);
            if(linear.length_squared()>.22*.22||angular.length_squared()>2.5*2.5)quiet[index]=false;
            auto *state=server->body_get_direct_state(rid);
            if(state)for(int contact=0;contact<state->get_contact_count();contact++){
                RID contact_body=state->get_contact_collider(contact);
                if(server->body_get_collision_layer(contact_body)&7)ground[index]=true;
                for(const auto &owner:owners)if(owner.second!=index&&owner.first==contact_body)parents[root(index)]=root(owner.second);
            }
        }
    }
    for(int island=0;island<count;island++)if(root(island)==island){
        bool supported=false,stable=true,active=false;double held=1e9;
        for(int g=0;g<count;g++)if(root(g)==island){supported=supported||ground[g];stable=stable&&quiet[g];active=active||awake[g];held=std::min(held,ragdolls_[g].quiet);}
        // A sleeping support body need not keep reporting contacts. Verify near
        // support for previously grounded islands before releasing their rest.
        // One ray per unsupported island, at most the fixed sixteen groups.
        // A shared first-two budget starves scattered severed parts forever.
        if(!supported&&stable)for(int g=0;g<count;g++)if(root(g)==island&&ragdolls_[g].ground_damped&&!ragdolls_[g].bodies.empty()){
            auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(ragdolls_[g].bodies.front()));
            if(body&&body->is_inside_tree()){
                Ref<World3D> world=body->get_world_3d();
                if(world.is_valid()){
                    Vector3 point=body->get_global_position();
                    auto ray=PhysicsRayQueryParameters3D::create(point+Vector3(0,.05,0),point-Vector3(0,.5,0),7);
                    supported=!world->get_direct_space_state()->intersect_ray(ray).is_empty();
                }
            }
            break;
        }
        held=supported&&stable&&active?held+elapsed:0;
        bool sleep=held>=.9;
        for(int g=0;g<count;g++)if(root(g)==island){
            ragdolls_[g].quiet=sleep?0:held;
            if(sleep||!supported||!stable)park_constraints(ragdolls_[g],sleep);
            if(supported&&!ragdolls_[g].ground_damped){
                // Passive impact damping removes constraint/contact chatter.
                // It starts only after real support and never holds a pose.
                for(uint64_t id:ragdolls_[g].bodies){
                    auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(!body)continue;
                    RID rid=body->get_rid();
                    server->body_set_param(rid,PhysicsServer3D::BODY_PARAM_LINEAR_DAMP,std::max(1.4,double(server->body_get_param(rid,PhysicsServer3D::BODY_PARAM_LINEAR_DAMP))));
                    server->body_set_param(rid,PhysicsServer3D::BODY_PARAM_ANGULAR_DAMP,std::max(4.0,double(server->body_get_param(rid,PhysicsServer3D::BODY_PARAM_ANGULAR_DAMP))));
                }
                ragdolls_[g].ground_damped=true;
            }
            if(sleep||!supported||!stable)for(uint64_t id:ragdolls_[g].bodies){
                auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(!body)continue;
                bool was_resting=false;
                if(auto *bone=Object::cast_to<NativeZombiePhysicalBone>(body)){was_resting=bone->is_resting();bone->set_resting(sleep);}
                if(auto *part=Object::cast_to<NativeZombieRigidPart>(body)){was_resting=part->is_resting();part->set_resting(sleep);}
                if(!sleep&&was_resting)server->body_set_state(body->get_rid(),PhysicsServer3D::BODY_STATE_SLEEPING,false);
            }
        }
        if(sleep){
            // Parking another joint can wake a contact neighbour. Commit the
            // whole island's sleep only after all its constraints are parked.
            for(int g=0;g<count;g++)if(root(g)==island)for(uint64_t id:ragdolls_[g].bodies){auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(body)server->body_set_state(body->get_rid(),PhysicsServer3D::BODY_STATE_SLEEPING,true);}
            settle_events_++;
        }
    }
}
void NativeZombieAnatomy::wake_ragdolls(const AABB &bounds){
    if(!bounds.position.is_finite()||!bounds.size.is_finite())return;
    if(bounds.size!=Vector3()){
        bool touched=false;AABB area=bounds.grow(.75);
        for(const auto &group:ragdolls_)for(uint64_t id:group.bodies){auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(body&&area.has_point(body->get_global_position()))touched=true;}
        if(!touched)return;
    }
    auto *server=PhysicsServer3D::get_singleton();
    for(auto &group:ragdolls_){park_constraints(group,false);group.quiet=0;for(uint64_t id:group.bodies){
        auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(!body)continue;
        if(auto *bone=Object::cast_to<NativeZombiePhysicalBone>(body))bone->set_resting(false);
        if(auto *part=Object::cast_to<NativeZombieRigidPart>(body))part->set_resting(false);
        server->body_set_state(body->get_rid(),PhysicsServer3D::BODY_STATE_SLEEPING,false);
    }}
}
Dictionary NativeZombieAnatomy::ragdoll_stats() const {
    Dictionary out;int bodies=0,sleeping=0,resting=0;double linear=0,angular=0;auto *server=PhysicsServer3D::get_singleton();
    for(const auto &group:ragdolls_)for(uint64_t id:group.bodies){auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(body){bodies++;if(bool(server->body_get_state(body->get_rid(),PhysicsServer3D::BODY_STATE_SLEEPING)))sleeping++;if(auto *bone=Object::cast_to<NativeZombiePhysicalBone>(body)){if(bone->is_resting())resting++;}if(auto *part=Object::cast_to<NativeZombieRigidPart>(body)){if(part->is_resting())resting++;}Vector3 v=server->body_get_state(body->get_rid(),PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY),w=server->body_get_state(body->get_rid(),PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY);linear=std::max(linear,double(v.length()));angular=std::max(angular,double(w.length()));}}
    out["groups"]=int(ragdolls_.size());out["bodies"]=bodies;out["sleeping"]=sleeping;out["resting"]=resting;out["settle_events"]=settle_events_;out["maximum_linear_speed"]=linear;out["maximum_angular_speed"]=angular;return out;
}
}
