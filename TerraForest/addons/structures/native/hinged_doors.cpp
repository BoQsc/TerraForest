// SPDX-License-Identifier: 0BSD
#include "hinged_doors.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
namespace terraforest {
using namespace godot;
static Transform3D unpack(const PackedFloat32Array &p){return Transform3D(Basis(p[0],p[1],p[2],p[4],p[5],p[6],p[8],p[9],p[10]),Vector3(p[3],p[7],p[11]));}
static PackedFloat32Array pack(const Transform3D &t){PackedFloat32Array p;p.resize(12);for(int r=0;r<3;++r){for(int c=0;c<3;++c)p.set(r*4+c,t.basis[r][c]);p.set(r*4+3,t.origin[r]);}return p;}
// Door asset origin is its left hinge. A quarter turn has no trigonometric drift.
static PackedFloat32Array swing(const PackedFloat32Array &p){return pack(unpack(p)*Transform3D(Basis(0,0,1,0,1,0,-1,0,0),Vector3()));}
void NativeHingedDoors::_bind_methods(){
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
    AABB leaf(Vector3(0,0,-0.07),Vector3(1,2.2,0.14));
    AABB sweep=(global*unpack(current)).xform(leaf).merge((global*unpack(requested)).xform(leaf)).grow(0.05);
    if(protection.has_volume()&&sweep.intersects(protection)){result["reason"]="Step clear of the door swing";return result;}
    PackedInt64Array ids;ids.push_back(id);
    if(!batch->upsert_instances(ids,requested))return result;
    if(closing)opened.erase(id);else opened[id]=current;
    result["ok"]=true;result["open"]=!closing;result["reason"]=closing?"Door closed":"Door opened";return result;
}
PackedByteArray NativeHingedDoors::capture_storage_snapshot() const {
    PackedByteArray b;b.resize(8+opened.size()*56);b.encode_u32(0,0x31524454);b.encode_u32(4,opened.size());int64_t at=8;
    for(const auto &e:opened){b.encode_s64(at,e.first);for(int j=0;j<12;++j)b.encode_float(at+8+j*4,e.second[j]);at+=56;}return b;
}
bool NativeHingedDoors::decode(const PackedByteArray &b,std::map<int64_t,PackedFloat32Array> *out){
    if(b.size()<8||b.decode_u32(0)!=0x31524454)return false;
    auto count=b.decode_u32(4);if(count>65536||b.size()!=8+int64_t(count)*56)return false;
    int64_t last=0,at=8;
    for(uint32_t i=0;i<count;++i){int64_t id=b.decode_s64(at);if(id<=last)return false;last=id;PackedFloat32Array p;p.resize(12);
        for(int j=0;j<12;++j){float v=b.decode_float(at+8+j*4);if(!std::isfinite(v)||std::abs(v)>1048575)return false;p.set(j,v);}
        if(std::abs(unpack(p).basis.determinant())<1e-9)return false;
        if(out)out->emplace(id,p);at+=56;
    }return true;
}
bool NativeHingedDoors::restore_storage_snapshot(const PackedByteArray &b){std::map<int64_t,PackedFloat32Array> staged;if(!decode(b,&staged))return false;opened.swap(staged);return true;}
}
