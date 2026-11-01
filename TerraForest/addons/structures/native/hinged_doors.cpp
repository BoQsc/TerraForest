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
    // angles. Bounded work shared by instant use and active animated swings.
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
    ClassDB::bind_method(D_METHOD("configure_animation","opening","closing"),&NativeHingedDoors::configure_animation);
    ClassDB::bind_method(D_METHOD("animate_toggle","collection","id","protected_bounds"),&NativeHingedDoors::animate_toggle);
    ClassDB::bind_method(D_METHOD("advance","collection","delta"),&NativeHingedDoors::advance);
    ClassDB::bind_method(D_METHOD("motion_state","id"),&NativeHingedDoors::motion_state);
    ClassDB::bind_method(D_METHOD("moving_ids"),&NativeHingedDoors::moving_ids);
    ClassDB::bind_method(D_METHOD("moving_count"),&NativeHingedDoors::moving_count);
    ClassDB::bind_method(D_METHOD("is_moving","id"),&NativeHingedDoors::is_moving);
    ClassDB::bind_method(D_METHOD("is_blocked","id"),&NativeHingedDoors::is_blocked);
    ClassDB::bind_method(D_METHOD("toggle","collection","id","protected_bounds"),&NativeHingedDoors::toggle);
    ClassDB::bind_method(D_METHOD("forget","id"),&NativeHingedDoors::forget);
    ClassDB::bind_method(D_METHOD("is_open","id"),&NativeHingedDoors::is_open);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeHingedDoors::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeHingedDoors::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeHingedDoors::restore_storage_snapshot);
}
bool NativeHingedDoors::configure_animation(const PackedFloat32Array &opening,const PackedFloat32Array &closing){
    if(!curve_signature.is_empty()||!motions.empty())return false;
    auto valid=[](const PackedFloat32Array &curve,bool increasing){
        if(curve.size()<4||curve.size()>1024||curve.size()%2||curve[0]!=0||curve[curve.size()-2]<=0||curve[curve.size()-2]>10)return false;
        if(curve[1]!=(increasing?0.0f:1.0f)||curve[curve.size()-1]!=(increasing?1.0f:0.0f))return false;
        for(int i=0;i<curve.size();i+=2){
            if(!std::isfinite(curve[i])||!std::isfinite(curve[i+1])||curve[i+1]<0||curve[i+1]>1)return false;
            if(i&&(curve[i]<=curve[i-2]||(increasing?curve[i+1]<curve[i-1]:curve[i+1]>curve[i-1])))return false;
        }return true;
    };
    if(!valid(opening,true)||!valid(closing,false))return false;
    PackedByteArray bytes;bytes.resize(8+(opening.size()+closing.size())*4);
    bytes.encode_u32(0,opening.size());bytes.encode_u32(4,closing.size());int at=8;
    for(const auto *curve:{&opening,&closing})for(int i=0;i<curve->size();++i){bytes.encode_float(at,(*curve)[i]);at+=4;}
    Ref<HashingContext> hash;hash.instantiate();hash->start(HashingContext::HASH_SHA256);hash->update(bytes);curve_signature=hash->finish();
    opening_curve=opening;closing_curve=closing;return true;
}
double NativeHingedDoors::fraction(const Motion &motion) const {
    const auto &curve=motion.target?opening_curve:closing_curve;
    int low=0,high=int(curve.size()/2)-1;
    while(low+1<high){int mid=(low+high)/2;if(curve[mid*2]<=motion.elapsed)low=mid;else high=mid;}
    const double ratio=std::clamp((motion.elapsed-curve[low*2])/(curve[high*2]-curve[low*2]),0.0,1.0);
    return curve[low*2+1]+(curve[high*2+1]-curve[low*2+1])*ratio;
}
PackedFloat32Array NativeHingedDoors::pose_at(const PackedFloat32Array &closed,double amount) const {
    if(amount<=0)return closed;if(amount>=1)return swing(closed);
    Basis rotation(Vector3(0,1,0),opening_degrees*3.14159265358979323846/180.0*amount);
    return pack(unpack(closed)*Transform3D(rotation,pivot-rotation.xform(pivot)));
}
String NativeHingedDoors::obstruction(NativeStaticBatch *batch,const PackedFloat32Array &closed,const AABB &protection) const {
    Transform3D global=batch->is_inside_tree()?batch->get_global_transform():batch->get_transform();
    const AABB sweep=sweep_bounds(global*unpack(closed));
    if(protection.has_volume()&&sweep.intersects(protection))return "Step clear of the door swing";
    if(batch->is_inside_tree()){
        Ref<World3D> world=batch->get_world_3d();auto *space=world.is_valid()?world->get_direct_space_state():nullptr;
        if(!space)return "Door collision unavailable";
        Ref<BoxShape3D> shape;shape.instantiate();shape->set_size(sweep.size);
        Ref<PhysicsShapeQueryParameters3D> query;query.instantiate();query->set_shape(shape);
        query->set_transform(Transform3D(Basis(),sweep.get_center()));
        // Preserve player-operated overlap policy. Actors, vehicles and ragdolls
        // block the complete swing, including when they enter after it starts.
        query->set_collision_mask(12|(1<<16)|(1<<18));query->set_margin(0.0);
        if(!space->intersect_shape(query,1).is_empty())return "An actor or vehicle blocks the door swing";
    }return String();
}
Dictionary NativeHingedDoors::toggle(NativeStaticBatch *batch,int64_t id,const AABB &protection){
    Dictionary result;result["ok"]=false;result["reason"]="Door unavailable";
    if(!batch||id<=0||!protection.position.is_finite()||!protection.size.is_finite())return result;
    if(motions.count(id)){result["reason"]="Door is already moving";return result;}
    auto current=batch->get_instance(id);if(current.size()!=12)return result;
    auto found=opened.find(id);bool closing=found!=opened.end()&&swing(found->second)==current;
    if(!closing&&opened.size()>=65536&&found==opened.end())return result;
    auto closed=closing?found->second:current;
    String blocked=obstruction(batch,closed,protection);if(!blocked.is_empty()){result["reason"]=blocked;return result;}
    PackedInt64Array ids;ids.push_back(id);
    if(!batch->upsert_instances(ids,closing?closed:swing(closed)))return result;
    if(closing)opened.erase(id);else opened[id]=closed;
    result["ok"]=true;result["open"]=!closing;result["reason"]=closing?"Door closed":"Door opened";return result;
}
Dictionary NativeHingedDoors::animate_toggle(NativeStaticBatch *batch,int64_t id,const AABB &protection){
    Dictionary result;result["ok"]=false;result["reason"]="Door unavailable";
    if(!batch||id<=0||curve_signature.is_empty()||!protection.position.is_finite()||!protection.size.is_finite())return result;
    if(motions.count(id)){result["reason"]="Door is already moving";return result;}
    if(motions.size()>=32){result["reason"]="Too many doors are moving";return result;}
    auto current=batch->get_instance(id);if(current.size()!=12)return result;
    auto found=opened.find(id);bool closing=found!=opened.end()&&swing(found->second)==current;
    if(!closing&&opened.size()>=65536&&found==opened.end())return result;
    auto closed=closing?found->second:current;
    String blocked=obstruction(batch,closed,protection);if(!blocked.is_empty()){result["reason"]=blocked;return result;}
    Motion motion;motion.target=!closing;motion.last=current;opened[id]=closed;motions.emplace(id,motion);
    result["ok"]=true;result["open"]=!closing;result["reason"]=closing?"Door closing":"Door opening";return result;
}
int64_t NativeHingedDoors::advance(NativeStaticBatch *batch,double delta){
    if(!batch||!std::isfinite(delta)||delta<=0||motions.empty())return 0;
    delta=std::min(delta,0.1);int64_t changed=0;
    for(auto it=motions.begin();it!=motions.end();){
        const int64_t id=it->first;auto &motion=it->second;auto current=batch->get_instance(id);
        if(current.size()!=12&&batch->unloaded_ids.count(id)){++it;continue;}
        if(current!=motion.last){opened.erase(id);it=motions.erase(it);++changed;continue;}
        auto &closed=opened.at(id);motion.blocked=!obstruction(batch,closed,AABB()).is_empty();
        if(motion.blocked){++it;continue;}
        Motion next=motion;const auto &curve=next.target?opening_curve:closing_curve;
        const double duration=curve[curve.size()-2];next.elapsed=std::min(duration,next.elapsed+delta);
        const bool finished=next.elapsed>=duration;auto pose=pose_at(closed,finished?(next.target?1.0:0.0):fraction(next));
        PackedInt64Array ids;ids.push_back(id);
        if(!batch->upsert_instances_impl(ids,pose,true)){motion.blocked=true;++it;continue;}
        next.last=pose;motion=next;++changed;
        if(finished){
            // Refresh grass/footprint exclusion once at rest, not at 60 Hz.
            batch->emit_signal("exclusion_changed");
            if(!motion.target)opened.erase(id);it=motions.erase(it);
        }else ++it;
    }return changed;
}
Dictionary NativeHingedDoors::motion_state(int64_t id) const {
    Dictionary result;auto it=motions.find(id);result["active"]=it!=motions.end();
    if(it!=motions.end()){result["clip"]=it->second.target?"Open":"Close";result["time"]=it->second.elapsed;result["fraction"]=fraction(it->second);result["blocked"]=it->second.blocked;}
    return result;
}
PackedByteArray NativeHingedDoors::capture_storage_snapshot() const {
    const bool animated=!motions.empty(),legacy=!animated&&legacy_profile();int64_t at=animated?88:legacy?8:48;
    PackedByteArray b;b.resize(at+opened.size()*56+motions.size()*72);b.fill(0);
    b.encode_u32(0,animated?0x33524454:legacy?0x31524454:0x32524454);b.encode_u32(4,opened.size());
    if(!legacy){for(int j=0;j<3;++j){b.encode_float(8+j*4,leaf.position[j]);b.encode_float(20+j*4,leaf.size[j]);b.encode_float(32+j*4,pivot[j]);}b.encode_float(44,opening_degrees);}
    if(animated){b.encode_u32(48,motions.size());for(int i=0;i<32;++i)b.set(56+i,curve_signature[i]);}
    for(const auto &e:opened){b.encode_s64(at,e.first);for(int j=0;j<12;++j)b.encode_float(at+8+j*4,e.second[j]);at+=56;}
    for(const auto &e:motions){b.encode_s64(at,e.first);b.encode_double(at+8,e.second.elapsed);b.encode_u32(at+16,e.second.target?1:0);for(int j=0;j<12;++j)b.encode_float(at+24+j*4,e.second.last[j]);at+=72;}
    return b;
}
bool NativeHingedDoors::decode(const PackedByteArray &b,std::map<int64_t,PackedFloat32Array> *out,std::map<int64_t,Motion> *moving) const {
    if(b.size()<8)return false;
    const uint32_t magic=b.decode_u32(0);const bool legacy=magic==0x31524454,animated=magic==0x33524454;
    int64_t at=animated?88:legacy?8:48;uint32_t motion_count=0;
    if(legacy){if(!legacy_profile())return false;}
    else {
        if((magic!=0x32524454&&!animated)||b.size()<at)return false;
        for(int j=0;j<3;++j)if(b.decode_float(8+j*4)!=leaf.position[j]||b.decode_float(20+j*4)!=leaf.size[j]||b.decode_float(32+j*4)!=pivot[j])return false;
        if(b.decode_float(44)!=float(opening_degrees))return false;
        if(animated){
            motion_count=b.decode_u32(48);if(!motion_count||motion_count>32||b.decode_u32(52)!=0||curve_signature.size()!=32)return false;
            for(int i=0;i<32;++i)if(b[56+i]!=curve_signature[i])return false;
        }
    }
    const auto count=b.decode_u32(4);const int64_t records_at=at;
    if(count>65536||b.size()!=at+int64_t(count)*56+int64_t(motion_count)*72)return false;
    auto read_pose=[&](int64_t offset,PackedFloat32Array &pose){
        pose.resize(12);for(int j=0;j<12;++j){float v=b.decode_float(offset+j*4);if(!std::isfinite(v)||std::abs(v)>1048575)return false;pose.set(j,v);}
        return std::abs(unpack(pose).basis.determinant())>=1e-9;
    };
    int64_t last=0;
    for(uint32_t i=0;i<count;++i){int64_t id=b.decode_s64(at);if(id<=last)return false;last=id;PackedFloat32Array pose;
        if(!read_pose(at+8,pose))return false;if(out)out->emplace(id,pose);at+=56;
    }
    last=0;
    for(uint32_t i=0;i<motion_count;++i){
        const int64_t id=b.decode_s64(at);if(id<=last||b.decode_u32(at+16)>1||b.decode_u32(at+20)!=0)return false;last=id;
        Motion motion;motion.target=b.decode_u32(at+16)==1;motion.elapsed=b.decode_double(at+8);
        const auto &curve=motion.target?opening_curve:closing_curve;
        if(!std::isfinite(motion.elapsed)||motion.elapsed<0||motion.elapsed>=curve[curve.size()-2]||!read_pose(at+24,motion.last))return false;
        uint32_t lo=0,hi=count;while(lo<hi){uint32_t mid=lo+(hi-lo)/2;if(b.decode_s64(records_at+int64_t(mid)*56)<id)lo=mid+1;else hi=mid;}
        if(lo==count||b.decode_s64(records_at+int64_t(lo)*56)!=id)return false;
        PackedFloat32Array closed;if(!read_pose(records_at+int64_t(lo)*56+8,closed)||pose_at(closed,fraction(motion))!=motion.last)return false;
        if(moving)moving->emplace(id,motion);at+=72;
    }return true;
}
bool NativeHingedDoors::restore_storage_snapshot(const PackedByteArray &b){
    std::map<int64_t,PackedFloat32Array> staged;std::map<int64_t,Motion> moving;
    if(!decode(b,&staged,&moving))return false;opened.swap(staged);motions.swap(moving);return true;
}
}
