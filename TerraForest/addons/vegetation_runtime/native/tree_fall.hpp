// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
#include <vector>
namespace terraforest {
using namespace godot;
// Bounded transient presentation: no physics owner, harvest IDs or saved copies.
class NativeTreeFall : public Node3D {
    GDCLASS(NativeTreeFall,Node3D)
    struct Fall {MultiMeshInstance3D *node;Ref<MultiMesh> mesh;Transform3D root;Vector3 axis;double age=0,angle=1.55,seed=0;bool fading=false;};
    Ref<Mesh> source;std::vector<Fall> active;
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("configure","mesh"),&NativeTreeFall::configure);
        ClassDB::bind_method(D_METHOD("start","pose","direction","seed"),&NativeTreeFall::start);
        ClassDB::bind_method(D_METHOD("advance","delta","clock"),&NativeTreeFall::advance);
        ClassDB::bind_method(D_METHOD("clear"),&NativeTreeFall::clear);
        ClassDB::bind_method(D_METHOD("count"),&NativeTreeFall::count);
    }
public:
    bool configure(const Ref<Mesh> &mesh){if(source.is_valid()||mesh.is_null())return false;source=mesh;return true;}
    int64_t count()const{return active.size();}
    void clear(){for(auto &fall:active)fall.node->queue_free();active.clear();}
    bool start(const Transform3D &pose,Vector3 direction,double seed){
        if(source.is_null()||!is_inside_tree()||!pose.is_finite()||!direction.is_finite()||!std::isfinite(seed))return false;
        direction.y=0;if(direction.length_squared()<.001)direction=Vector3(0,0,1);direction=direction.normalized();
        if(active.size()==16){active.front().node->queue_free();active.erase(active.begin());}
        Fall fall;fall.root=pose;fall.axis=Vector3(0,1,0).cross(direction).normalized();fall.seed=seed;
        double height=18.47*pose.basis.get_column(1).length(),radius=.3*pose.basis.get_column(0).length();
        fall.angle=1.57079632679;
        for(double fraction:{.35,.65,.95}){
            Vector3 point=pose.origin+direction*(height*fraction);
            auto ray=PhysicsRayQueryParameters3D::create(point+Vector3(0,height+8,0),point-Vector3(0,height+16,0),1);
            Dictionary hit=get_world_3d()->get_direct_space_state()->intersect_ray(ray);
            if(!hit.is_empty())fall.angle=std::min(fall.angle,std::acos(std::clamp((double(Vector3(hit["position"]).y-pose.origin.y)+radius)/(height*fraction),-.3,.95)));
        }
        fall.mesh.instantiate();fall.mesh->set_transform_format(MultiMesh::TRANSFORM_3D);fall.mesh->set_use_custom_data(true);fall.mesh->set_mesh(source);fall.mesh->set_instance_count(1);
        fall.mesh->set_instance_transform(0,pose);fall.mesh->set_instance_custom_data(0,Color(seed,0,0,0));
        fall.node=memnew(MultiMeshInstance3D);fall.node->set_multimesh(fall.mesh);add_child(fall.node);active.push_back(fall);return true;
    }
    void advance(double delta,double clock){
        if(!std::isfinite(delta)||delta<0||!std::isfinite(clock))return;
        for(size_t i=0;i<active.size();){auto &fall=active[i];fall.age+=std::min(delta,.1);
            if(fall.age>=6){fall.node->queue_free();active.erase(active.begin()+i);continue;}
            double t=std::clamp(fall.age/1.9,0.,1.);double angle=fall.angle*(t*t*(2.-t));
            if(t>=1)angle+=.018*std::sin((fall.age-1.9)*12)*std::exp(-(fall.age-1.9)*4);
            Transform3D pose=fall.root;pose.basis=Basis(fall.axis,angle)*pose.basis;fall.mesh->set_instance_transform(0,pose);
            if(fall.age>=5&&!fall.fading){fall.fading=true;fall.mesh->set_instance_custom_data(0,Color(fall.seed,std::fmod(clock,4096.),-1,1));}
            ++i;
        }
    }
};
}
