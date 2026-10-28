#include "zombie_anatomy.hpp"
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/physical_bone3d.hpp>
#include <godot_cpp/classes/convex_polygon_shape3d.hpp>
#include <cmath>
#include <algorithm>
#include <map>
#include <limits>
using namespace godot;
namespace terraforest {
namespace {
constexpr const char *PART_NAMES[]={"torso","head","upper_arm_l","forearm_l","hand_l","upper_arm_r","forearm_r","hand_r","thigh_l","shin_l","foot_l","thigh_r","shin_r","foot_r"};
constexpr const char *BONE_NAMES[]={"Spine2","Head","LeftArm","LeftForeArm","LeftHand","RightArm","RightForeArm","RightHand","LeftUpLeg","LeftLeg","LeftFoot","RightUpLeg","RightLeg","RightFoot"};
Dictionary fit_cloud(const PackedVector3Array &vertices,const Transform3D &inverse_rest){
    Dictionary result;if(vertices.size()<4)return result;
    PackedVector3Array points;points.resize(vertices.size());auto *destination=points.ptrw();const auto *source=vertices.ptr();
    AABB bounds(inverse_rest.xform(source[0]),Vector3());
    for(int vertex=0;vertex<vertices.size();vertex++){destination[vertex]=inverse_rest.xform(source[vertex]);bounds.expand_to(destination[vertex]);}
    Vector3 center=bounds.get_center();for(int vertex=0;vertex<vertices.size();vertex++)destination[vertex]-=center;
    Ref<ConvexPolygonShape3D> shape;shape.instantiate();shape->set_points(points);shape->set_margin(.003);
    result["shape"]=shape;result["offset"]=Transform3D(Basis(),center);result["length"]=bounds.size.y;result["mesh_fit_bounds"]=bounds;
    return result;
}
}
void NativeZombieAnatomy::invalidate_geometry(){geometry_valid_=false;fitted_shapes_.clear();}
std::vector<Transform3D> NativeZombieAnatomy::evaluated_poses() const {
    auto *skeleton=Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_));if(!skeleton)return {};
    skeleton->force_update_all_bone_transforms();std::vector<Transform3D> poses(skeleton->get_bone_count());
    for(int bone=0;bone<int(poses.size());bone++)poses[bone]=skeleton->get_global_transform()*skeleton->get_bone_global_pose(bone);
    if(health_<=0&&death_poses_.size()==poses.size()){
        std::vector<PhysicalBone3D*> physical(poses.size(),nullptr);
        for(const auto &group:ragdolls_)for(uint64_t identity:group.bodies){
            auto *body=Object::cast_to<PhysicalBone3D>(ObjectDB::get_instance(identity));
            if(body&&body->get_bone_id()>=0&&body->get_bone_id()<int(poses.size()))physical[body->get_bone_id()]=body;
        }
        for(int bone=0;bone<int(poses.size());bone++){
            int ancestor=bone;while(ancestor>=0&&!physical[ancestor])ancestor=skeleton->get_bone_parent(ancestor);
            if(ancestor>=0)poses[bone]=physical[ancestor]->get_global_transform()*physical[ancestor]->get_body_offset().affine_inverse()*death_poses_[ancestor].affine_inverse()*death_poses_[bone];
            else poses[bone]=skeleton->get_global_transform()*death_poses_[bone];
        }
    }
    return poses;
}
PackedVector3Array NativeZombieAnatomy::sample_vertices(const String &name,const Transform3D &to_local) const {
    PackedVector3Array result;int index=part_index(name);if(index<0||!to_local.is_finite())return result;
    const auto &part=parts_[index];auto *node=Object::cast_to<MeshInstance3D>(ObjectDB::get_instance(part.mesh));
    auto poses=evaluated_poses();if(!node||poses.empty())return result;
    std::vector<Transform3D> binds(part.binds.size());
    for(int bind=0;bind<int(binds.size());bind++){if(part.bone_ids[bind]>=int(poses.size()))return result;binds[bind]=to_local*poses[part.bone_ids[bind]]*part.binds[bind];}
    int total_vertices=0;for(const auto &surface:part.surfaces)total_vertices+=surface.vertices.size();
    result.resize(total_vertices);auto *output=result.ptrw();int offset=0;Transform3D unskinned=to_local*node->get_global_transform();
    for(const auto &surface:part.surfaces){
        const int count=surface.vertices.size(),influences=surface.bones.size()/count;
        const auto *vertices=surface.vertices.ptr();const auto *bones=surface.bones.ptr();const auto *weights=surface.weights.ptr();
        std::vector<double> amounts;std::vector<const Vector3*> morphs;
        for(int morph=0;morph<int(surface.morphs.size());morph++){amounts.push_back(node->get_blend_shape_value(morph));morphs.push_back(surface.morphs[morph].ptr());}
        for(int vertex=0;vertex<count;vertex++){
            Vector3 source=vertices[vertex],point;double total=0;
            for(int morph=0;morph<int(amounts.size());morph++)if(std::isfinite(amounts[morph])&&std::abs(amounts[morph])>1e-6)source+=(surface.relative?morphs[morph][vertex]:morphs[morph][vertex]-vertices[vertex])*amounts[morph];
            for(int influence=0;influence<influences;influence++){
                const int slot=vertex*influences+influence;double weight=weights[slot];
                if(weight<=0)continue;point+=binds[bones[slot]].xform(source)*weight;total+=weight;
            }
            output[offset++]=total>1e-5?point/total:unskinned.xform(source);
        }
    }
    return result;
}
Dictionary NativeZombieAnatomy::fit_collision_shapes(){
    if(!fitted_shapes_.is_empty())return fitted_shapes_.duplicate(true);
    auto *skeleton=Object::cast_to<Skeleton3D>(ObjectDB::get_instance(skeleton_));if(!skeleton||!geometry_valid_)return {};
    int hips=skeleton->find_bone("Hips");if(hips<0)return {};
    double waist=skeleton->get_bone_global_rest(hips).origin.y+.14;
    Transform3D to_skeleton=skeleton->get_global_transform().affine_inverse();Dictionary next;
    for(int part=0;part<14;part++){
        int bone=skeleton->find_bone(BONE_NAMES[part]);if(bone<0)return {};
        auto points=sample_vertices(PART_NAMES[part],to_skeleton);if(points.size()<4)return {};
        if(part==0){
            PackedVector3Array chest,pelvis;PackedInt32Array chest_indices,pelvis_indices;
            for(int vertex=0;vertex<points.size();vertex++){
                if(points[vertex].y>=waist-.045){chest.push_back(points[vertex]);chest_indices.push_back(vertex);}
                if(points[vertex].y<=waist+.045){pelvis.push_back(points[vertex]);pelvis_indices.push_back(vertex);}
            }
            auto upper=fit_cloud(chest,skeleton->get_bone_global_rest(bone).affine_inverse());auto lower=fit_cloud(pelvis,skeleton->get_bone_global_rest(hips).affine_inverse());
            if(upper.is_empty()||lower.is_empty())return {};
            upper["source_indices"]=chest_indices;lower["source_indices"]=pelvis_indices;next["torso"]=upper;next["pelvis"]=lower;
        }else next[PART_NAMES[part]]=fit_cloud(points,skeleton->get_bone_global_rest(bone).affine_inverse());
    }
    fitted_shapes_=next;return fitted_shapes_.duplicate(true);
}
Dictionary NativeZombieAnatomy::geometry_stats() const {
    Dictionary result;result["mesh_reused"]=geometry_reused_;result["shapes_reused"]=shapes_reused_;result["valid"]=geometry_valid_;result["vertices"]=vertices_;result["shapes"]=fitted_shapes_.size();return result;
}
Dictionary NativeZombieAnatomy::hand_groups(const String &name,const Transform3D &to_local) const {
    Dictionary result;int index=part_index(name);if(index!=4&&index!=7)return result;
    auto points=sample_vertices(name,to_local);if(points.is_empty())return result;
    const auto &part=parts_[index];String prefix=index==4?"LeftHand":"RightHand";
    std::map<String,std::vector<Vector3>> groups;std::vector<String> order;int offset=0;
    for(const auto &surface:part.surfaces){
        int count=surface.vertices.size(),influences=surface.bones.size()/count;
        const auto *bones=surface.bones.ptr();const auto *weights=surface.weights.ptr();
        for(int vertex=0;vertex<count;vertex++){
            String group="Palm";double maximum=0;
            for(int influence=0;influence<influences;influence++){
                int slot=vertex*influences+influence,bind=bones[slot];if(weights[slot]<=maximum)continue;
                maximum=weights[slot];String bone=geometry_names_[part.bone_ids[bind]];
                group=bone.begins_with(prefix)&&bone!=prefix?bone.trim_prefix(prefix):String("Palm");
            }
            if(groups.find(group)==groups.end())order.push_back(group);
            groups[group].push_back(points[offset++]);
        }
    }
    if(groups.find("Palm")==groups.end())order.push_back("Palm");
    auto &palm=groups[String("Palm")];
    for(const auto &group:order){
        auto iterator=groups.find(group);
        if(group!="Palm"&&iterator->second.size()<4){palm.insert(palm.end(),iterator->second.begin(),iterator->second.end());groups.erase(iterator);}
    }
    for(const auto &name:order){
        auto found=groups.find(name);if(found==groups.end())continue;
        const auto &points=found->second;
        PackedVector3Array cloud;cloud.resize(points.size());auto *output=cloud.ptrw();
        std::copy(points.begin(),points.end(),output);result[name]=cloud;
    }
    return result;
}
Dictionary NativeZombieAnatomy::closest_contact(const String &name,Vector3 target,bool use_point,const Array &shapes,const AABB &mouth) const {
    Dictionary result;int index=part_index(name);if(index<0||!target.is_finite()||!mouth.position.is_finite()||!mouth.size.is_finite()||shapes.size()>64)return result;
    auto points=sample_vertices(name,Transform3D());if(points.is_empty())return result;
    struct ContactShape {Transform3D world,inverse;Vector3 half;double radius=0;bool sphere=false;};
    std::vector<ContactShape> prepared;
    for(int shape_index=0;shape_index<shapes.size();shape_index++){
        if(shapes[shape_index].get_type()!=Variant::DICTIONARY)continue;
        Dictionary row=shapes[shape_index];if(row.get("transform",Variant()).get_type()!=Variant::TRANSFORM3D)continue;
        ContactShape shape;shape.world=row["transform"];if(!shape.world.is_finite()||std::abs(shape.world.basis.determinant())<.000001)continue;
        String type=row.get("type","");shape.sphere=type=="sphere";
        if(shape.sphere){shape.radius=row.get("radius",0.);if(!std::isfinite(shape.radius)||shape.radius<=0)continue;}
        else if(type=="box"&&row.get("half_extents",Variant()).get_type()==Variant::VECTOR3){shape.half=row["half_extents"];if(!shape.half.is_finite()||shape.half.x<=0||shape.half.y<=0||shape.half.z<=0)continue;}
        else continue;
        shape.inverse=shape.world.affine_inverse();prepared.push_back(shape);
    }
    double best=std::numeric_limits<double>::infinity();Vector3 best_point,best_target;int offset=0;
    Vector3 mouth_end=mouth.position+mouth.size;
    for(const auto &surface:parts_[index].surfaces){
        const auto *bind=surface.vertices.ptr();
        for(int vertex=0;vertex<surface.vertices.size();vertex++){
            Vector3 point=points[offset++];
            if(index==1&&(bind[vertex].x<mouth.position.x||bind[vertex].y<mouth.position.y||bind[vertex].z<mouth.position.z||bind[vertex].x>mouth_end.x||bind[vertex].y>mouth_end.y||bind[vertex].z>mouth_end.z))continue;
            if(shapes.is_empty()){
                Vector3 closest=use_point?target:Vector3(target.x,Math::clamp(point.y,target.y+real_t(.20),target.y+real_t(1.65)),target.z);
                double distance=point.distance_to(closest);if(distance<best){best=distance;best_point=point;best_target=closest;}
            }else for(const auto &shape:prepared){
                Vector3 local=shape.inverse.xform(point);Vector3 closest=shape.world.xform(shape.sphere?local.limit_length(shape.radius):local.clamp(-shape.half,shape.half));
                double distance=point.distance_to(closest);if(distance<best){best=distance;best_point=point;best_target=closest;}
            }
        }
    }
    if(std::isfinite(best)){result["distance"]=best;result["point"]=best_point;result["target"]=best_target;}return result;
}
}
