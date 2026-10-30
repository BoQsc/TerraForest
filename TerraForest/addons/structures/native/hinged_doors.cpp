// SPDX-License-Identifier: 0BSD
#include "hinged_doors.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/box_shape3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <cmath>
#include <algorithm>
namespace terraforest {
using namespace godot;
static Transform3D unpack(const PackedFloat32Array &p){return Transform3D(Basis(p[0],p[1],p[2],p[4],p[5],p[6],p[8],p[9],p[10]),Vector3(p[3],p[7],p[11]));}
static PackedFloat32Array pack(const Transform3D &t){PackedFloat32Array p;p.resize(12);for(int r=0;r<3;++r){for(int c=0;c<3;++c)p.set(r*4+c,t.basis[r][c]);p.set(r*4+3,t.origin[r]);}return p;}
bool NativeHingedDoors::legacy_profile() const {
    return leaf==AABB(Vector3(0,0,-0.07),Vector3(1,2.2,0.14))&&pivot==Vector3()&&opening_degrees==90.0;
}
bool NativeHingedDoors::configure(const AABB &bounds,Vector3 hinge,double degrees){
    if(configured||!opened.empty()||!bounds.position.is_finite()||!bounds.size.is_finite()||!hinge.is_finite()||!std::isfinite(degrees))return false;
    if(bounds.size.x<=0||bounds.size.y<=0||bounds.size.z<=0||bounds.size.x>8||bounds.size.y>8||bounds.size.z>8||bounds.position.length()>16||hinge.length()>16||std::abs(degrees)<1||std::abs(degrees)>170)return false;
    leaf=bounds;pivot=hinge;opening_degrees=float(degrees);configured=true;return true;
}
PackedFloat32Array NativeHingedDoors::swing(const PackedFloat32Array &p) const {
    // Preserve the exact historical quarter turn and byte-identical closed poses.
    Basis rotation=opening_degrees==90.0?Basis(0,0,1,0,1,0,-1,0,0):opening_degrees==-90.0?Basis(0,0,-1,0,1,0,1,0,0):Basis(Vector3(0,1,0),opening_degrees*3.14159265358979323846/180.0);
    return pack(unpack(p)*Transform3D(rotation,pivot-rotation.xform(pivot)));
}
AABB NativeHingedDoors::sweep_bounds(const Transform3D &pose) const {
    // Exact axis extrema of each rotating box corner, including intermediate
    // angles. Bounded click-time work; no nodes or per-frame door simulation.
    constexpr double pi=3.14159265358979323846;
    const double angle=opening_degrees*pi/180.0,lo=std::min(0.0,angle),hi=std::max(0.0,angle);
    Vector3 minimum,maximum;
    for(int corner=0;corner<8;++corner){
        const Vector3 point=leaf.get_endpoint(corner)-pivot;
        const Vector3 centre=pose.xform(pivot+Vector3(0,point.y,0));
        for(int axis=0;axis<3;++axis){
            const double a=pose.basis[axis][0]*point.x+pose.basis[axis][2]*point.z;
            const double b=pose.basis[axis][0]*point.z-pose.basis[axis][2]*point.x;
            auto value=[&](double t){return centre[axis]+a*std::cos(t)+b*std::sin(t);};
            double low=std::min(value(lo),value(hi)),high=std::max(value(lo),value(hi));
            const double critical=std::atan2(b,a);
            for(int k=-2;k<=2;++k){double t=critical+k*pi;if(t>=lo&&t<=hi){low=std::min(low,value(t));high=std::max(high,value(t));}}
            if(corner==0){minimum[axis]=low;maximum[axis]=high;}
            else {minimum[axis]=std::min(double(minimum[axis]),low);maximum[axis]=std::max(double(maximum[axis]),high);}
        }
    }
    return AABB(minimum,maximum-minimum);
}
void NativeHingedDoors::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","bounds","pivot","opening_degrees"),&NativeHingedDoors::configure);
    ClassDB::bind_method(D_METHOD("toggle","collection","id","protected_bounds"),&NativeHingedDoors::toggle);
    ClassDB::bind_method(D_METHOD("forget","id"),&NativeHingedDoors::forget);
    ClassDB::bind_method(D_METHOD("is_open","id"),&NativeHingedDoors::is_open);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeHingedDoors::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeHingedDoors::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeHingedDoors::restore_storage_snapshot);
}
Dictionary NativeHingedDoors::toggle(NativeStaticBatch *batch,int64_t id,const AABB &protection){
    Dictionary result;result["ok"]=false;result["reason"]="Door unavailable";
    if(!batch||id<=0||!protection.position.is_finite()||!protection.size.is_finite())return result;
    auto current=batch->get_instance(id);if(current.size()!=12)return result;
    auto found=opened.find(id);
    // An editor move invalidates the old hinge pose; never teleport to stale coordinates.
    bool closing=found!=opened.end()&&swing(found->second)==current;
    if(!closing&&opened.size()>=65536&&found==opened.end())return result;
    auto requested=closing?found->second:swing(current);
    Transform3D global=batch->is_inside_tree()?batch->get_global_transform():batch->get_transform();
    // Contact with the closed leaf is not penetration. An extra inflated margin
    // here prevents a player stopped by collision from opening away from them.
    AABB sweep=sweep_bounds(global*unpack(closing?found->second:current));
    if(protection.has_volume()&&sweep.intersects(protection)){result["reason"]="Step clear of the door swing";return result;}
    // Click-time broadphase query only: active actors use layer 8, vehicle
    // bodies (including parked proxies) use layer 4. Never scan entity stores.
    if(batch->is_inside_tree()){
        Ref<World3D> world=batch->get_world_3d();
        auto *space=world.is_valid()?world->get_direct_space_state():nullptr;
        if(!space)return result;
        Ref<BoxShape3D> shape;shape.instantiate();shape->set_size(sweep.size);
        Ref<PhysicsShapeQueryParameters3D> query;query.instantiate();
        query->set_shape(shape);query->set_transform(Transform3D(Basis(),sweep.get_center()));
        query->set_collision_mask(12 | (1<<16) | (1<<18));query->set_margin(0.0);
        if(!space->intersect_shape(query,1).is_empty()){
            result["reason"]="An actor or vehicle blocks the door swing";return result;
        }
    }
    PackedInt64Array ids;ids.push_back(id);
    if(!batch->upsert_instances(ids,requested))return result;
    if(closing)opened.erase(id);else opened[id]=current;
    result["ok"]=true;result["open"]=!closing;result["reason"]=closing?"Door closed":"Door opened";return result;
}
PackedByteArray NativeHingedDoors::capture_storage_snapshot() const {
    const bool legacy=legacy_profile();int64_t at=legacy?8:48;
    PackedByteArray b;b.resize(at+opened.size()*56);b.encode_u32(0,legacy?0x31524454:0x32524454);b.encode_u32(4,opened.size());
    if(!legacy){for(int j=0;j<3;++j){b.encode_float(8+j*4,leaf.position[j]);b.encode_float(20+j*4,leaf.size[j]);b.encode_float(32+j*4,pivot[j]);}b.encode_float(44,opening_degrees);}
    for(const auto &e:opened){b.encode_s64(at,e.first);for(int j=0;j<12;++j)b.encode_float(at+8+j*4,e.second[j]);at+=56;}return b;
}
bool NativeHingedDoors::decode(const PackedByteArray &b,std::map<int64_t,PackedFloat32Array> *out) const {
    if(b.size()<8)return false;
    const bool legacy=b.decode_u32(0)==0x31524454;
    int64_t at=legacy?8:48;
    if(legacy){if(!legacy_profile())return false;}
    else {
        if(b.decode_u32(0)!=0x32524454||b.size()<48)return false;
        for(int j=0;j<3;++j)if(b.decode_float(8+j*4)!=leaf.position[j]||b.decode_float(20+j*4)!=leaf.size[j]||b.decode_float(32+j*4)!=pivot[j])return false;
        if(b.decode_float(44)!=float(opening_degrees))return false;
    }
    auto count=b.decode_u32(4);if(count>65536||b.size()!=at+int64_t(count)*56)return false;
    int64_t last=0;
    for(uint32_t i=0;i<count;++i){int64_t id=b.decode_s64(at);if(id<=last)return false;last=id;PackedFloat32Array p;p.resize(12);
        for(int j=0;j<12;++j){float v=b.decode_float(at+8+j*4);if(!std::isfinite(v)||std::abs(v)>1048575)return false;p.set(j,v);}
        if(std::abs(unpack(p).basis.determinant())<1e-9)return false;
        if(out)out->emplace(id,p);at+=56;
    }return true;
}
bool NativeHingedDoors::restore_storage_snapshot(const PackedByteArray &b){std::map<int64_t,PackedFloat32Array> staged;if(!decode(b,&staged))return false;opened.swap(staged);return true;}
}
