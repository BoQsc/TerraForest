#include "block_shapes.hpp"
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <limits>

namespace terraforest {
namespace {
constexpr double EPS=1e-7,INF=std::numeric_limits<double>::infinity();
bool valid_ray(const Transform3D &frame,Vector3 from,Vector3 to,Vector3 &origin,Vector3 &end) {
    if(!from.is_finite()||!to.is_finite()||!frame.is_finite()||std::abs(frame.basis.determinant())<1e-12)return false;
    Transform3D inverse=frame.affine_inverse();origin=inverse.xform(from);end=inverse.xform(to);
    Vector3 direction=end-origin;
    if(!origin.is_finite()||!end.is_finite()||direction.length_squared()<1e-12||direction.length_squared()>256.0*256.0)return false;
    for(int a=0;a<3;a++)if(std::abs(origin[a])>1048576||std::abs(end[a])>1048576)return false;
    return true;
}
struct Intersection {double enter=-INF,exit=INF;Vector3 normal;bool valid=true;};
void clip(Intersection &hit,Vector3 origin,Vector3 direction,Vector3 normal,double offset) {
    if(!hit.valid)return;
    double velocity=normal.dot(direction),distance=offset-normal.dot(origin);
    if(std::abs(velocity)<1e-12) {if(distance<-EPS)hit.valid=false;return;}
    double t=distance/velocity;
    if(velocity<0) {if(t>hit.enter){hit.enter=t;hit.normal=normal;}}
    else hit.exit=std::min(hit.exit,t);
    if(hit.enter>hit.exit+EPS)hit.valid=false;
}
Intersection box(Vector3 origin,Vector3 direction,Vector3 lo,Vector3 hi) {
    Intersection hit;
    for(int a=0;a<3;a++) {
        Vector3 n;n[a]=1;clip(hit,origin,direction,n,hi[a]);
        n[a]=-1;clip(hit,origin,direction,n,-lo[a]);
    }
    return hit;
}
// -1 means the segment starts within this solid; front-face picking then rejects.
double shape_hit(int word,Vector3 origin,Vector3 direction,Vector3 &normal) {
    int rotation=(word>>3)&3,shape=word&7;
    for(int r=0;r<rotation;r++) {origin=Vector3(origin.z,origin.y,1-origin.x);direction=Vector3(direction.z,direction.y,-direction.x);}
    double nearest=INF;bool inside=false;
    auto accept=[&](const Intersection &hit) {
        if(!hit.valid||hit.exit<-EPS||hit.enter>1+EPS)return;
        if(hit.enter<-EPS&&hit.exit>EPS){inside=true;return;}
        if(hit.enter>=-EPS&&hit.enter<nearest){nearest=std::max(0.0,hit.enter);normal=hit.normal;}
    };
    if(shape==1)accept(box(origin,direction,Vector3(),Vector3(1,1,1)));
    else if(shape==2)accept(box(origin,direction,Vector3(),Vector3(1,.5,1)));
    else if(shape==3)for(int step=0;step<4;step++)accept(box(origin,direction,Vector3(0,0,step*.25),Vector3(1,(step+1)*.25,(step+1)*.25)));
    else if(shape==4) {
        auto hit=box(origin,direction,Vector3(),Vector3(1,1,1));
        clip(hit,origin,direction,Vector3(0,1,-1).normalized(),0);accept(hit);
    } else if(shape==5)accept(box(origin,direction,Vector3(.25,0,.25),Vector3(.75,1,.75)));
    else if(shape==6) {
        auto hit=box(origin,direction,Vector3(),Vector3(1,1,1));
        for(const auto &plane:sphere_template().planes)clip(hit,origin,direction,plane.normal,plane.offset);
        accept(hit);
    }
    if(inside)return -1;
    for(int r=0;r<rotation;r++)normal=Vector3(-normal.z,normal.y,normal.x);
    return nearest;
}
}
Dictionary NativeBlockWorld::raycast_cells(Vector3 from,Vector3 to) const {
    Dictionary result;
    Transform3D frame=is_inside_tree()?get_global_transform():get_transform();
    Vector3 origin,end;if(!valid_ray(frame,from,to,origin,end))return result;
    Transform3D inverse=frame.affine_inverse();
    Vector3 direction=end-origin;
    Vector3i coordinate;int step[3];double next[3],delta[3];
    for(int a=0;a<3;a++) {
        coordinate[a]=int(std::floor(origin[a]));step[a]=(direction[a]>0)-(direction[a]<0);
        delta[a]=step[a]?1/std::abs(double(direction[a])):INF;
        next[a]=step[a]?((coordinate[a]+(step[a]>0))-double(origin[a]))/direction[a]:INF;
    }
    double entered=0;
    // A 256 m local ray crosses fewer than 448 unit cells, including tied edges.
    for(int visited=1;visited<=512&&entered<=1+EPS;visited++) {
        double leaving=std::min({next[0],next[1],next[2],1.0});
        int word=cell(coordinate.x,coordinate.y,coordinate.z);
        if(word) {
            Vector3 normal;double fraction=shape_hit(word,origin-Vector3(coordinate),direction,normal);
            if(fraction<0)return result;
            if(std::isfinite(fraction)&&fraction>=entered-EPS&&fraction<=leaving+EPS) {
                result["cell"]=coordinate;result["word"]=word;result["cell_normal"]=normal;
                result["position"]=from+(to-from)*fraction;
                result["normal"]=inverse.basis.transposed().xform(normal).normalized();
                result["fraction"]=fraction;result["distance"]=from.distance_to(to)*fraction;
                result["visited_cells"]=visited;return result;
            }
        }
        double crossing=std::min({next[0],next[1],next[2]});
        if(crossing>1+EPS)return result;
        for(int a=0;a<3;a++)if(next[a]<=crossing+1e-12){coordinate[a]+=step[a];next[a]+=delta[a];}
        entered=crossing;
    }
    return result;
}
Dictionary NativeBlockWorld::raycast_scene(Vector3 from,Vector3 to,int64_t mask,const TypedArray<RID> &exclude) const {
    Vector3 origin,end;
    Transform3D frame=is_inside_tree()?get_global_transform():get_transform();
    if(mask<0||uint64_t(mask)>UINT32_MAX||exclude.size()>256||!valid_ray(frame,from,to,origin,end))return {};
    Dictionary authored;if(mask&2)authored=raycast_cells(from,to);
    if(!authored.is_empty())authored["collider"]=const_cast<NativeBlockWorld*>(this);
    if(!is_inside_tree())return authored;
    Ref<World3D> world=get_world_3d();if(world.is_null())return authored;
    // Ignore all derived block bodies, including a prior revision still awaiting
    // its replacement bake. Query the remaining scene once, not once per block.
    TypedArray<RID> ignored=exclude.duplicate();
    for(const auto &entry:visuals)if(entry.second.body)ignored.push_back(entry.second.body->get_rid());
    auto query=PhysicsRayQueryParameters3D::create(from,to,uint32_t(mask),ignored);
    Dictionary physics=world->get_direct_space_state()->intersect_ray(query);
    if(physics.is_empty())return authored;
    if(authored.is_empty())return physics;
    Vector3 physics_position=physics["position"],authored_position=authored["position"];
    return from.distance_squared_to(physics_position)+1e-8<from.distance_squared_to(authored_position)?physics:authored;
}
}
