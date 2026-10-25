#include "block_shapes.hpp"
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <limits>
#include <godot_cpp/variant/packed_float64_array.hpp>

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
// -1 means the segment starts within this solid; front-face picking then rejects.
double shape_hit(int word,Vector3 origin,Vector3 direction,Vector3 &normal) {
    int rotation=block_rotation(word),shape=block_shape(word);
    Basis orientation=block_basis(rotation),inverse=orientation.transposed();
    origin=inverse.xform(origin-Vector3(.5,.5,.5))+Vector3(.5,.5,.5);direction=inverse.xform(direction);
    double nearest=INF;bool inside=false;
    auto accept=[&](const Intersection &hit) {
        if(!hit.valid||hit.exit<-EPS||hit.enter>1+EPS)return;
        if(hit.enter<-EPS&&hit.exit>EPS){inside=true;return;}
        if(hit.enter>=-EPS&&hit.enter<nearest){nearest=std::max(0.0,hit.enter);normal=hit.normal;}
    };
    Intersection component;
    visit_shape_hulls(shape,[&](){component=Intersection{};},
        [&](Vector3 n,double offset){clip(component,origin,direction,n,offset);},
        [&](){accept(component);});
    if(inside)return -1;
    normal=orientation.xform(normal);
    return nearest;
}
}
Dictionary NativeBlockWorld::solid_hulls(const AABB &bounds) const {
    Dictionary result;result["ok"]=false;result["unavailable"]=false;
    if(!bounds.position.is_finite()||!bounds.size.is_finite()||bounds.size.x<=0||bounds.size.y<=0||bounds.size.z<=0)return result;
    Transform3D frame=is_inside_tree()?get_global_transform():get_transform();
    if(!frame.is_finite()||std::abs(frame.basis.determinant())<1e-12)return result;
    Transform3D inverse=frame.affine_inverse();AABB local=inverse.xform(bounds);
    Vector3 lo=local.position.floor(),hi=(local.position+local.size).ceil();
    for(int a=0;a<3;++a)if(lo[a]<-1048575||hi[a]>1048576)return result;
    Vector3 extent=hi-lo;if(double(extent.x)*extent.y*extent.z>512)return result;
    if(unavailable_region(local)){result["unavailable"]=true;return result;}
    Array hulls;Basis normal_frame=inverse.basis.transposed();
    for(int z=int(lo.z);z<int(hi.z);++z)for(int y=int(lo.y);y<int(hi.y);++y)for(int x=int(lo.x);x<int(hi.x);++x){
        int word=cell(x,y,z);if(!word)continue;
        PackedFloat64Array hull;Vector3 center(.5,.5,.5),translation(x,y,z);
        visit_shape_hulls(block_shape(word),[&](){hull=PackedFloat64Array();},[&](Vector3 n,double offset){
            Vector3 rotated=orient_block_vector(n,block_rotation(word));
            auto dot=[](Vector3 a,Vector3 b){return double(a.x)*b.x+double(a.y)*b.y+double(a.z)*b.z;};
            double local_offset=offset+dot(rotated,center+translation)-dot(n,center);
            Vector3 world_normal=normal_frame.xform(rotated);double length=std::sqrt(dot(world_normal,world_normal));
            double world_offset=(local_offset+dot(world_normal,frame.origin))/length;
            hull.push_back(double(world_normal.x)/length);hull.push_back(double(world_normal.y)/length);hull.push_back(double(world_normal.z)/length);hull.push_back(world_offset);
        },[&](){hulls.push_back(hull);});
    }
    result["hulls"]=hulls;result["ok"]=true;return result;
}
PackedByteArray NativeBlockWorld::sample_solid(const PackedVector3Array &points) const {
    PackedByteArray result;if(points.size()>4096)return result;
    Transform3D frame=is_inside_tree()?get_global_transform():get_transform();
    if(!frame.is_finite()||std::abs(frame.basis.determinant())<1e-12)return result;
    const Transform3D inverse=frame.affine_inverse();
    result.resize(points.size());
    for(int64_t i=0;i<points.size();++i){
        Vector3 p=inverse.xform(points[i]);
        if(!points[i].is_finite()||!p.is_finite())return PackedByteArray();
        for(int a=0;a<3;++a)if(p[a]<-1048575.0||p[a]>=1048576.0)return PackedByteArray();
        Vector3i cell_position(int(std::floor(p.x)),int(std::floor(p.y)),int(std::floor(p.z)));
        if(unavailable_region(AABB(Vector3(cell_position),Vector3(1,1,1)))){result.set(i,2);continue;}
        int word=cell(cell_position.x,cell_position.y,cell_position.z);Vector3 unused;
        // A zero-length segment reuses the exact convex planes used by picking,
        // including the faceted rendered sphere rather than an analytic sphere.
        result.set(i,word&&shape_hit(word,p-Vector3(cell_position),Vector3(),unused)<0?1:0);
    }
    return result;
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
Dictionary NativeBlockWorld::raycast_scene(Vector3 from,Vector3 to,int64_t mask,const TypedArray<RID> &exclude,bool hit_from_inside) const {
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
    query->set_hit_from_inside(hit_from_inside);
    Dictionary physics=world->get_direct_space_state()->intersect_ray(query);
    if(physics.is_empty())return authored;
    if(authored.is_empty())return physics;
    Vector3 physics_position=physics["position"],authored_position=authored["position"];
    return from.distance_squared_to(physics_position)+1e-8<from.distance_squared_to(authored_position)?physics:authored;
}
Dictionary NativeBlockWorld::placement_support(const AABB &bounds,Vector3 surface,bool lattice,bool terrain_only,const TypedArray<RID> &exclude) const {
    Dictionary out;out["ok"]=false;out["samples"]=0;out["hits"]=0;out["inside"]=0;
    out["reason"]="Placement surface is unavailable";
    Vector3 size=bounds.size;
    if(!bounds.position.is_finite()||!size.is_finite()||!surface.is_finite()||
       size.x<=0||size.z<=0||size.y<=0||size.x>16||size.z>16||size.y>32||exclude.size()>64||!is_inside_tree())return out;
    for(int a=0;a<3;a++)if(std::abs(bounds.position[a])>1048544||std::abs(surface[a])>1048544)return out;
    Ref<World3D> world=get_world_3d();if(world.is_null())return out;
    TypedArray<RID> ignored=exclude.duplicate();
    if(!terrain_only)for(const auto &entry:visuals)if(entry.second.body)ignored.push_back(entry.second.body->get_rid());
    auto query=PhysicsRayQueryParameters3D::create(Vector3(),Vector3(),terrain_only?1:3,ignored);
    query->set_hit_from_inside(true);
    double minimum=INF,maximum=-INF;int hits=0,inside=0;
    // One fixed 3x3 footprint, inset from shared seams. Never a world scan.
    constexpr double factors[3]={.08,.5,.92};
    for(double x:factors)for(double z:factors){
        Vector3 from(bounds.position.x+size.x*x,surface.y+1.5,bounds.position.z+size.z*z);
        Vector3 to(from.x,surface.y-1.5,from.z);query->set_from(from);query->set_to(to);
        Dictionary hit=world->get_direct_space_state()->intersect_ray(query);
        if(!terrain_only){
            Dictionary authored=raycast_cells(from,to);
            if(!authored.is_empty()&&(hit.is_empty()||from.distance_squared_to(authored["position"])<from.distance_squared_to(hit["position"])))hit=authored;
        }
        if(hit.is_empty())continue;
        Vector3 normal=hit["normal"],point=hit["position"];
        if(normal.length_squared()<1e-8){inside++;continue;}
        if(normal.y<.35)continue;
        minimum=std::min(minimum,double(point.y));maximum=std::max(maximum,double(point.y));hits++;
    }
    out["samples"]=9;out["hits"]=hits;out["inside"]=inside;
    if(hits){out["minimum"]=minimum;out["maximum"]=maximum;}
    if(inside){out["reason"]="Ground or structure rises through this placement; aim higher or dig it clear";return out;}
    if(!hits){out["reason"]="Aim at a nearby supporting surface";return out;}
    double overlap=lattice?(terrain_only?std::min(.20,double(size.y)*.25):0.):std::min(.03,double(size.y)*.10);
    double bottom=lattice?std::max(double(bounds.position.y),std::ceil(maximum-overlap-1e-5)):maximum-overlap;
    double shift=bottom-bounds.position.y,gap=std::max(0.,bottom-minimum);
    out["overlap_limit"]=overlap;out["bottom"]=bottom;out["offset_y"]=shift;out["gap"]=gap;
    if((lattice&&(shift>1.001||gap>1.15))||(!lattice&&(std::abs(shift)>.8||gap>.6))){
        out["reason"]="Ground is too uneven here; aim at a flatter spot";return out;
    }
    out["ok"]=true;out["reason"]="";return out;
}
}
