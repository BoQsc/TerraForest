#include "lake_catalog.hpp"
#include "lake_volume.hpp"
#include <array>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeLakeCatalog::_bind_methods() {
    ClassDB::bind_method(D_METHOD("encode","records","next_id"),&NativeLakeCatalog::encode,DEFVAL(0));
    ClassDB::bind_method(D_METHOD("decode","bytes"),&NativeLakeCatalog::decode);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeLakeCatalog::validate_snapshot);
    ClassDB::bind_method(D_METHOD("placement_mask","volumes","transforms"),&NativeLakeCatalog::placement_mask);
}
PackedByteArray NativeLakeCatalog::placement_mask(const Array &volumes,const TypedArray<Transform3D> &transforms) const {
    if(volumes.size()>16||transforms.size()>512)return {};
    std::array<NativeLakeVolume*,16> lakes{};
    for(int i=0;i<volumes.size();++i){
        if(volumes[i].get_type()!=Variant::OBJECT)return {};
        lakes[i]=Object::cast_to<NativeLakeVolume>(static_cast<Object*>(volumes[i]));
        if(!lakes[i])return {};
    }
    PackedByteArray result;result.resize(transforms.size());result.fill(0);
    for(int i=0;i<transforms.size();++i){
        const Transform3D transform=transforms[i];if(!transform.origin.is_finite())return {};
        for(int j=0;j<volumes.size();++j)if(lakes[j]->submerges_root(transform.origin)){result.set(i,1);break;}
    }
    return result;
}
static bool valid(const Dictionary &r) {
    if(r.get("id",Variant()).get_type()!=Variant::INT || r.get("origin",Variant()).get_type()!=Variant::VECTOR3 ||
       r.get("cells",Variant()).get_type()!=Variant::VECTOR3I || r.get("seed",Variant()).get_type()!=Variant::VECTOR3)return false;
    const Variant a=r.get("spacing",Variant()),b=r.get("level",Variant());
    if((a.get_type()!=Variant::FLOAT&&a.get_type()!=Variant::INT)||(b.get_type()!=Variant::FLOAT&&b.get_type()!=Variant::INT))return false;
    const int64_t id=r["id"];const Vector3 origin=r["origin"],seed=r["seed"];const Vector3i cells=r["cells"];
    const double spacing=a,level=b;
    if(id<1||id>9007199254740991ll || !origin.is_finite()||!seed.is_finite()||origin.length()>100000||!std::isfinite(spacing)||!std::isfinite(level)||spacing<1||spacing>8||
       cells.x<3||cells.y<3||cells.z<3||cells.x>128||cells.y>64||cells.z>128||int64_t(cells.x)*cells.y*cells.z>262144||
       level<=origin.y||level>=origin.y+cells.y*spacing||seed.y>=level)return false;
    const Vector3 local=(seed-origin)/spacing;
    return local.x>=0&&local.y>=0&&local.z>=0&&local.x<cells.x&&local.y<cells.y&&local.z<cells.z;
}
PackedByteArray NativeLakeCatalog::encode(const Array &records,int64_t next_id) const {
    if(records.size()>16)return {};
    Dictionary ids;
    int64_t minimum_next=1;
    for(int64_t i=0;i<records.size();++i){
        if(records[i].get_type()!=Variant::DICTIONARY)return {};
        const Dictionary r=records[i];if(!valid(r)||ids.has(r["id"]))return {};ids[r["id"]]=true;
        if(int64_t(r["id"])+1>minimum_next)minimum_next=int64_t(r["id"])+1;
    }
    if(next_id==0)next_id=minimum_next;
    if(next_id<minimum_next||next_id>9007199254740992ll)return {};
    PackedByteArray out;out.resize(20+records.size()*56);out.fill(0);
    out.encode_u32(0,0x314c5754);out.encode_u32(4,1);out.encode_u32(8,uint32_t(records.size()));
    out.encode_u64(12,next_id);
    for(int64_t i=0;i<records.size();++i) {
        const Dictionary r=records[i];const int64_t off=20+i*56;
        const Vector3 origin=r["origin"],seed=r["seed"];const Vector3i cells=r["cells"];
        out.encode_u64(off,int64_t(r["id"]));
        for(int j=0;j<3;++j){out.encode_float(off+8+j*4,origin[j]);out.encode_u32(off+20+j*4,cells[j]);out.encode_float(off+40+j*4,seed[j]);}
        out.encode_float(off+32,double(r["spacing"]));out.encode_float(off+36,double(r["level"]));
    }
    // Reject values that become invalid when rounded to the on-disk float32 ABI.
    return validate_snapshot(out) ? out : PackedByteArray();
}
Dictionary NativeLakeCatalog::decode(const PackedByteArray &bytes) const {
    Dictionary result;result["ok"]=false;
    if(bytes.size()<20||bytes.decode_u32(0)!=0x314c5754||bytes.decode_u32(4)!=1)return result;
    const uint32_t count=bytes.decode_u32(8);if(count>16||bytes.size()!=20+count*56)return result;
    const uint64_t next_id=bytes.decode_u64(12);if(next_id<1||next_id>9007199254740992ull)return result;
    Array records;Dictionary ids;
    for(uint32_t i=0;i<count;++i){
        const int64_t off=20+i*56;if(bytes.decode_u32(off+52)!=0)return result;
        Dictionary r;Vector3 origin,seed;Vector3i cells;
        for(int j=0;j<3;++j){origin[j]=bytes.decode_float(off+8+j*4);cells[j]=int32_t(bytes.decode_u32(off+20+j*4));seed[j]=bytes.decode_float(off+40+j*4);}
        r["id"]=int64_t(bytes.decode_u64(off));r["origin"]=origin;r["seed"]=seed;r["cells"]=cells;r["spacing"]=bytes.decode_float(off+32);r["level"]=bytes.decode_float(off+36);
        if(!valid(r)||ids.has(r["id"])||uint64_t(int64_t(r["id"]))>=next_id)return result;
        ids[r["id"]]=true;records.push_back(r);
    }
    result["ok"]=true;result["records"]=records;result["next_id"]=int64_t(next_id);return result;
}
bool NativeLakeCatalog::validate_snapshot(const PackedByteArray &bytes) const {return bool(decode(bytes)["ok"]);}
}
