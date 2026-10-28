// SPDX-License-Identifier: 0BSD
#include "zombie_anatomy.hpp"
#include "zombie_rest_body.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/skin.hpp>
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/classes/physics_direct_body_state3d.hpp>
#include <godot_cpp/classes/physical_bone3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <algorithm>
#include <cmath>
#include <unordered_map>
using namespace godot;
namespace terraforest {
std::vector<uint64_t> NativeZombieAnatomy::ragdoll_owners_;
uint64_t NativeZombieAnatomy::ragdoll_frame_=uint64_t(-1);
double NativeZombieAnatomy::ragdoll_clock_=0;
NativeZombieAnatomy::~NativeZombieAnatomy(){
    auto id=get_instance_id();ragdoll_owners_.erase(std::remove(ragdoll_owners_.begin(),ragdoll_owners_.end(),id),ragdoll_owners_.end());
}
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
    ClassDB::bind_method(D_METHOD("set_hit_meshes","skeleton","meshes","geometry"),&NativeZombieAnatomy::set_hit_meshes,DEFVAL(Ref<NativeZombieAnatomy>()));
    ClassDB::bind_method(D_METHOD("sample_vertices","part","to_local"),&NativeZombieAnatomy::sample_vertices);
    ClassDB::bind_method(D_METHOD("hand_groups","part","to_local"),&NativeZombieAnatomy::hand_groups);
    ClassDB::bind_method(D_METHOD("closest_contact","part","target","use_point","shapes","mouth"),&NativeZombieAnatomy::closest_contact);
    ClassDB::bind_method(D_METHOD("fit_collision_shapes"),&NativeZombieAnatomy::fit_collision_shapes);
    ClassDB::bind_method(D_METHOD("geometry_stats"),&NativeZombieAnatomy::geometry_stats);
    ClassDB::bind_method(D_METHOD("hit","part","damage","force_sever","impact"),&NativeZombieAnatomy::hit,DEFVAL(false),DEFVAL(String("melee")));
    ClassDB::bind_method(D_METHOD("detach","part"),&NativeZombieAnatomy::detach);
    ClassDB::bind_method(D_METHOD("kill"),&NativeZombieAnatomy::kill);
    ClassDB::bind_method(D_METHOD("snapshot"),&NativeZombieAnatomy::snapshot);
    ClassDB::bind_method(D_METHOD("capture_vitals"),&NativeZombieAnatomy::capture_vitals);
    ClassDB::bind_method(D_METHOD("restore_vitals","bytes"),&NativeZombieAnatomy::restore_vitals);
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
bool NativeZombieAnatomy::set_hit_meshes(Skeleton3D *skeleton,const Dictionary &meshes,const Ref<NativeZombieAnatomy> &geometry){
    if(!configured_||skeleton_||!skeleton||skeleton->get_bone_count()>256||meshes.size()!=14)return false;
    geometry_names_.clear();geometry_rest_.clear();geometry_pose_.clear();geometry_mesh_transforms_.clear();
    for(auto &morphs:geometry_morphs_)morphs.clear();
    const int bone_count=skeleton->get_bone_count();
    bool reuse=geometry.is_valid()&&geometry.ptr()!=this&&geometry->geometry_valid_&&int(geometry->geometry_names_.size())==bone_count;
    bool reuse_shapes=reuse&&!geometry->fitted_shapes_.is_empty();
    for(int bone=0;bone<bone_count;bone++){
        geometry_names_.push_back(skeleton->get_bone_name(bone));
        geometry_rest_.push_back(skeleton->get_bone_global_rest(bone));
        geometry_pose_.push_back(skeleton->get_bone_global_pose(bone));
        if(reuse&&(geometry_names_.back()!=geometry->geometry_names_[bone]||geometry_rest_.back()!=geometry->geometry_rest_[bone]))reuse=false;
        if(reuse_shapes&&!geometry_pose_.back().is_equal_approx(geometry->geometry_pose_[bone]))reuse_shapes=false;
    }
    for(int index=0;index<14;index++){
        auto *node=Object::cast_to<MeshInstance3D>(meshes.get(NAMES[index],Variant()));
        if(!node||node->get_mesh().is_null())return false;
        auto *asset=Object::cast_to<ArrayMesh>(node->get_mesh().ptr());if(!asset||asset->get_blend_shape_count()>16)return false;
        geometry_mesh_transforms_.push_back(skeleton->get_global_transform().affine_inverse()*node->get_global_transform());
        for(int morph=0;morph<asset->get_blend_shape_count();morph++)geometry_morphs_[index].push_back(node->get_blend_shape_value(morph));
        if(reuse&&(node->get_mesh()!=geometry->parts_[index].asset||node->get_skin()!=geometry->parts_[index].skin))reuse=false;
        if(reuse_shapes&&(!geometry_mesh_transforms_.back().is_equal_approx(geometry->geometry_mesh_transforms_[index])||geometry_morphs_[index]!=geometry->geometry_morphs_[index]))reuse_shapes=false;
    }
    reuse_shapes=reuse_shapes&&reuse;
    auto next=parts_;int vertices=0,triangles=0;
    for(int i=0;i<14;i++){
        auto *node=Object::cast_to<MeshInstance3D>(meshes.get(NAMES[i],Variant()));
        if(!node||node->get_mesh().is_null())return false;
        auto &part=next[i];part.mesh=node->get_instance_id();Ref<Mesh> mesh=node->get_mesh();Ref<Skin> skin=node->get_skin();
        part.asset=mesh;part.skin=skin;
        if(reuse){
            part.bone_ids=geometry->parts_[i].bone_ids;part.binds=geometry->parts_[i].binds;part.surfaces=geometry->parts_[i].surfaces;
            continue;
        }
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
    parts_=std::move(next);skeleton_=skeleton->get_instance_id();vertices_=reuse?geometry->vertices_:vertices;triangles_=reuse?geometry->triangles_:triangles;
    geometry_valid_=true;geometry_reused_=reuse;shapes_reused_=reuse_shapes;
    if(reuse_shapes)fitted_shapes_=geometry->fitted_shapes_.duplicate(true);
    Callable changed=callable_mp(this,&NativeZombieAnatomy::invalidate_geometry);
    for(const auto &part:parts_){
        if(!part.asset->is_connected("changed",changed))part.asset->connect("changed",changed);
        if(part.skin.is_valid()&&!part.skin->is_connected("changed",changed))part.skin->connect("changed",changed);
    }
    return true;
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
PackedByteArray NativeZombieAnatomy::capture_vitals() const {
    PackedByteArray out;if(!configured_)return out;out.resize(60);uint32_t missing=0;
    for(int part=0;part<14;part++){out.encode_float(part*4,parts_[part].health);if(parts_[part].missing)missing|=1<<part;}
    out.encode_u32(56,missing);return out;
}
bool NativeZombieAnatomy::restore_vitals(const PackedByteArray &bytes){
    if(!configured_||bytes.size()!=60||bytes.decode_u32(56)>=16384)return false;
    uint32_t missing=bytes.decode_u32(56);
    for(int part=0;part<14;part++){
        double health=bytes.decode_float(part*4);
        if(!std::isfinite(health)||health<0||health>parts_[part].maximum||((missing&(1<<part))&&health!=0))return false;
        if(parts_[part].parent>=0&&(missing&(1<<parts_[part].parent))&&!(missing&(1<<part)))return false;
    }
    if((missing&3)&&bytes.decode_float(0)>0)return false;
    for(int part=0;part<14;part++){parts_[part].health=bytes.decode_float(part*4);parts_[part].missing=missing&(1<<part);}
    health_=parts_[0].health;return true;
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
    }
    if(ragdolls_.empty())ragdoll_owners_.push_back(get_instance_id());
    ragdolls_.push_back(std::move(group));return true;
}
void NativeZombieAnatomy::advance_ragdolls(double delta){
    if(!std::isfinite(delta)||delta<=0||delta>.25||ragdoll_owners_.empty())return;
    uint64_t frame=Engine::get_singleton()->get_physics_frames();if(frame==ragdoll_frame_)return;ragdoll_frame_=frame;
    struct Entry {Ragdoll *group;NativeZombieAnatomy *owner;};
    std::vector<Entry> entries;
    for(uint64_t id:ragdoll_owners_)if(auto *owner=Object::cast_to<NativeZombieAnatomy>(ObjectDB::get_instance(id))){
        auto &groups=owner->ragdolls_;
        groups.erase(std::remove_if(groups.begin(),groups.end(),[](const Ragdoll &group){for(uint64_t body:group.bodies)if(ObjectDB::get_instance(body))return false;return true;}),groups.end());
        for(auto &group:groups){
            bool processing=false;
            for(uint64_t body:group.bodies)if(auto *node=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(body))){if(node->is_inside_tree()&&node->can_process())processing=true;}
            if(processing)entries.push_back({&group,owner});
        }
    }
    ragdoll_owners_.erase(std::remove_if(ragdoll_owners_.begin(),ragdoll_owners_.end(),[](uint64_t id){auto *owner=Object::cast_to<NativeZombieAnatomy>(ObjectDB::get_instance(id));return !owner||owner->ragdolls_.empty();}),ragdoll_owners_.end());
    if(entries.empty()){ragdoll_clock_=0;return;}
    auto *server=PhysicsServer3D::get_singleton();
    for(auto &entry:entries){auto &group=*entry.group;if(group.resting){
        bool impact=false;
        for(uint64_t id:group.bodies){
            auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(!body)continue;
            if(auto *bone=Object::cast_to<NativeZombiePhysicalBone>(body)){if(!bone->is_resting())impact=true;}
            if(auto *part=Object::cast_to<NativeZombieRigidPart>(body)){if(!part->is_resting())impact=true;}
            if(ragdoll_rest_impact(server->body_get_direct_state(body->get_rid())))impact=true;
        }
        if(impact){group.resting=false;group.quiet=0;group.still=0;group.still_poses.clear();for(uint64_t id:group.bodies){auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(body){if(auto *bone=Object::cast_to<NativeZombiePhysicalBone>(body))bone->set_resting(false);if(auto *part=Object::cast_to<NativeZombieRigidPart>(body))part->set_resting(false);server->body_set_state(body->get_rid(),PhysicsServer3D::BODY_STATE_SLEEPING,false);}}}
    }}
    ragdoll_clock_+=delta;if(ragdoll_clock_<.1)return;double elapsed=ragdoll_clock_;ragdoll_clock_=0;
    const int count=entries.size();std::vector<int> parents(count);std::vector<bool> ground(count,false),quiet(count,true),awake(count,false);
    std::unordered_map<uint64_t,int> owners;
    for(int index=0;index<count;index++)parents[index]=index;
    for(int index=0;index<count;index++)for(uint64_t id:entries[index].group->bodies){auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(body)owners.emplace(body->get_rid().get_id(),index);}
    auto root=[&](int index){while(parents[index]!=index){parents[index]=parents[parents[index]];index=parents[index];}return index;};
    for(int index=0;index<count;index++){
        auto &group=*entries[index].group;bool still=group.still_poses.size()==group.bodies.size(),moving_contact=false;
        double support_height=1e30;
        group.still_poses.resize(group.bodies.size());
        for(size_t member=0;member<group.bodies.size();member++){
            uint64_t id=group.bodies[member];
            auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(!body)continue;
            RID rid=body->get_rid();awake[index]=awake[index]||!bool(server->body_get_state(rid,PhysicsServer3D::BODY_STATE_SLEEPING));
            Transform3D pose=server->body_get_state(rid,PhysicsServer3D::BODY_STATE_TRANSFORM);const auto &reference=group.still_poses[member];
            double alignment=0;for(int axis=0;axis<3;axis++)alignment+=pose.basis.get_column(axis).dot(reference.basis.get_column(axis));
            if(pose.origin.distance_squared_to(reference.origin)>.015*.015||alignment<2.99)still=false;
            Vector3 linear=server->body_get_state(rid,PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY),angular=server->body_get_state(rid,PhysicsServer3D::BODY_STATE_ANGULAR_VELOCITY);
            if(linear.length_squared()>.22*.22||angular.length_squared()>2.5*2.5)quiet[index]=false;
            auto *state=server->body_get_direct_state(rid);
            if(state)for(int contact=0;contact<state->get_contact_count();contact++){
                if(!ragdoll_contact_valid(state,contact))continue;
                RID contact_body=state->get_contact_collider(contact);
                Vector3 normal=state->get_contact_local_normal(contact),point=state->get_contact_collider_position(contact);
                bool support=(server->body_get_collision_layer(contact_body)&7)!=0;
                if(support&&normal.y>=.2&&!group.resting){
                    ground[index]=true;
                    if(!group.resting&&point.y<support_height){support_height=point.y;group.support_body=id;group.support_local=pose.affine_inverse().xform(point);}
                }
                if(!ragdoll_player_load(state,contact)&&!(server->body_get_collision_layer(contact_body)&(1<<18))&&state->get_contact_collider_velocity_at_position(contact).length_squared()>.1*.1)moving_contact=true;
                auto owner=owners.find(contact_body.get_id());if(owner!=owners.end()&&owner->second!=index)parents[root(index)]=root(owner->second);
            }
        }
        if(still&&!moving_contact)group.still+=elapsed;
        else{
            group.still=0;
            for(size_t member=0;member<group.bodies.size();member++)if(auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(group.bodies[member])))group.still_poses[member]=server->body_get_state(body->get_rid(),PhysicsServer3D::BODY_STATE_TRANSFORM);
        }
        quiet[index]=!moving_contact&&(quiet[index]||group.still>=.9);
    }
    std::vector<std::vector<int>> islands(count);for(int index=0;index<count;index++)islands[root(index)].push_back(index);
    for(const auto &island:islands)if(!island.empty()){
        bool supported=false,stable=true,active=false;double held=1e9;
        for(int index:island){supported=supported||ground[index];stable=stable&&quiet[index];active=active||awake[index];held=std::min(held,entries[index].group->quiet);}
        if(!supported&&stable)for(int index:island)if(entries[index].group->ground_damped&&entries[index].group->support_body){
            auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(entries[index].group->support_body));
            if(body&&body->is_inside_tree()){
                Ref<World3D> world=body->get_world_3d();
                if(world.is_valid()){
                    Transform3D pose=server->body_get_state(body->get_rid(),PhysicsServer3D::BODY_STATE_TRANSFORM);
                    Vector3 point=pose.xform(entries[index].group->support_local);
                    auto ray=PhysicsRayQueryParameters3D::create(point+Vector3(0,.025,0),point-Vector3(0,.025,0),7);
                    Dictionary hit=world->get_direct_space_state()->intersect_ray(ray);
                    supported=!hit.is_empty()&&Vector3(hit["normal"]).y>=.2;
                }
            }
            if(supported)break;
        }
        held=supported&&stable?held+elapsed:0;
        bool sleep=held>=.9;
        for(int index:island){
            auto &group=*entries[index].group;
            group.quiet=sleep?0:held;
            if(sleep||!supported||!stable)group.resting=sleep;
            if(!supported&&group.ground_damped){
                for(size_t member=0;member<group.bodies.size();member++)if(auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(group.bodies[member]))){
                    server->body_set_param(body->get_rid(),PhysicsServer3D::BODY_PARAM_LINEAR_DAMP,group.damping[member].x);
                    server->body_set_param(body->get_rid(),PhysicsServer3D::BODY_PARAM_ANGULAR_DAMP,group.damping[member].y);
                }
                group.ground_damped=false;group.damping.clear();
            }
            if(supported&&!group.ground_damped){
                // Passive impact damping removes constraint/contact chatter.
                // It starts only after real support and never holds a pose.
                for(uint64_t id:group.bodies){
                    auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(!body){group.damping.push_back(Vector2());continue;}
                    RID rid=body->get_rid();
                    group.damping.push_back(Vector2(server->body_get_param(rid,PhysicsServer3D::BODY_PARAM_LINEAR_DAMP),server->body_get_param(rid,PhysicsServer3D::BODY_PARAM_ANGULAR_DAMP)));
                    server->body_set_param(rid,PhysicsServer3D::BODY_PARAM_LINEAR_DAMP,std::max(3.0,double(server->body_get_param(rid,PhysicsServer3D::BODY_PARAM_LINEAR_DAMP))));
                    server->body_set_param(rid,PhysicsServer3D::BODY_PARAM_ANGULAR_DAMP,std::max(8.0,double(server->body_get_param(rid,PhysicsServer3D::BODY_PARAM_ANGULAR_DAMP))));
                }
                group.ground_damped=true;
            }
            if(sleep||!supported||!stable)for(uint64_t id:group.bodies){
                auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(!body)continue;
                bool was_resting=false;
                if(auto *bone=Object::cast_to<NativeZombiePhysicalBone>(body)){was_resting=bone->is_resting();bone->set_resting(sleep);}
                if(auto *part=Object::cast_to<NativeZombieRigidPart>(body)){was_resting=part->is_resting();part->set_resting(sleep);}
                if(!sleep&&(was_resting||(!supported&&bool(server->body_get_state(body->get_rid(),PhysicsServer3D::BODY_STATE_SLEEPING)))))server->body_set_state(body->get_rid(),PhysicsServer3D::BODY_STATE_SLEEPING,false);
            }
        }
        if(sleep){
            for(int index:island){for(uint64_t id:entries[index].group->bodies){auto *body=Object::cast_to<PhysicsBody3D>(ObjectDB::get_instance(id));if(body)server->body_set_state(body->get_rid(),PhysicsServer3D::BODY_STATE_SLEEPING,true);}entries[index].owner->settle_events_++;}
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
    for(auto &group:ragdolls_){group.resting=false;group.quiet=0;group.still=0;group.still_poses.clear();for(uint64_t id:group.bodies){
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
