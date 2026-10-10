// SPDX-License-Identifier: 0BSD
#include "storage.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeVehicleStorage::_bind_methods(){
    ClassDB::bind_method(D_METHOD("validate_fleet_snapshot","data"),&NativeVehicleStorage::validate_fleet_snapshot);
    ClassDB::bind_method(D_METHOD("encode_fleet","records","next_identity"),&NativeVehicleStorage::encode_fleet);
    ClassDB::bind_method(D_METHOD("decode_fleet","data"),&NativeVehicleStorage::decode_fleet);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeVehicleStorage::validate_snapshot);
    ClassDB::bind_method(D_METHOD("encode","pose"),&NativeVehicleStorage::encode);
    ClassDB::bind_method(D_METHOD("decode","data"),&NativeVehicleStorage::decode);
}
bool NativeVehicleStorage::validate_snapshot(const PackedByteArray &data) const {
    if(data.is_empty())return true;
    if(data.size()!=72||data.decode_u32(0)!=0x31564654||data.decode_u32(4)!=1||data.decode_u64(8)!=1)return false;
    for(int i=0;i<7;++i)if(!std::isfinite(data.decode_double(16+i*8)))return false;
    double x=data.decode_double(16),y=data.decode_double(24),z=data.decode_double(32);
    if(x<2||x>1998||z<2||z>1998||y<0||y>600)return false;
    double norm=0;for(int i=0;i<4;++i){double q=data.decode_double(40+i*8);norm+=q*q;}
    return std::abs(norm-1)<.00001;
}
PackedByteArray NativeVehicleStorage::encode(Transform3D pose) const {
    if(!pose.is_finite()||std::abs(pose.basis.determinant()-1)>.00001||!pose.basis.is_equal_approx(pose.basis.orthonormalized()))return {};
    Quaternion q=pose.basis.get_rotation_quaternion().normalized();
    PackedByteArray data;data.resize(72);data.encode_u32(0,0x31564654);data.encode_u32(4,1);data.encode_u64(8,1);
    for(int i=0;i<3;++i)data.encode_double(16+i*8,pose.origin[i]);
    data.encode_double(40,q.x);data.encode_double(48,q.y);data.encode_double(56,q.z);data.encode_double(64,q.w);
    return validate_snapshot(data)?data:PackedByteArray();
}
Dictionary NativeVehicleStorage::decode(const PackedByteArray &data) const {
    Dictionary result;bool valid=validate_snapshot(data);result["ok"]=valid;result["present"]=valid&&!data.is_empty();
    if(!valid||data.is_empty())return result;
    Vector3 position(data.decode_double(16),data.decode_double(24),data.decode_double(32));
    Quaternion q(data.decode_double(40),data.decode_double(48),data.decode_double(56),data.decode_double(64));
    result["pose"]=Transform3D(Basis(q.normalized()),position);return result;
}
// Fleet v2: 24-byte header, then sorted 64-byte rows (identity + pose).
// Separate validator prevents the legacy single-car owner accepting a fleet
// and silently discarding all but one record. Validation is worker-safe.
bool NativeVehicleStorage::validate_fleet_snapshot(const PackedByteArray &data) const {
    if(data.is_empty() || (data.size()==72 && data.decode_u32(4)==1))return validate_snapshot(data);
    if(data.size()<24 || data.decode_u32(0)!=0x31564654 || data.decode_u32(4)!=2 || data.decode_u32(12)!=0)return false;
    const uint32_t count=data.decode_u32(8);
    const uint64_t next=data.decode_u64(16);
    if(count>65536 || data.size()!=24+int64_t(count)*64 || !next || next>INT64_MAX)return false;
    uint64_t previous=0;
    for(uint32_t i=0;i<count;++i){
        const int64_t at=24+int64_t(i)*64;
        const uint64_t id=data.decode_u64(at);
        if(id<=previous || id>=next)return false;
        previous=id;
        for(int j=0;j<7;++j)if(!std::isfinite(data.decode_double(at+8+j*8)))return false;
        const double x=data.decode_double(at+8),y=data.decode_double(at+16),z=data.decode_double(at+24);
        if(x<2||x>1998||z<2||z>1998||y<0||y>600)return false;
        double norm=0;for(int j=0;j<4;++j){double q=data.decode_double(at+32+j*8);norm+=q*q;}
        if(std::abs(norm-1)>=.00001)return false;
    }
    return true;
}
PackedByteArray NativeVehicleStorage::encode_fleet(const Array &records,int64_t next_identity) const {
    if(records.size()>65536 || next_identity<1)return {};
    PackedByteArray data;data.resize(24+records.size()*64);data.fill(0);
    data.encode_u32(0,0x31564654);data.encode_u32(4,2);data.encode_u32(8,records.size());data.encode_u64(16,next_identity);
    int64_t previous=0;
    for(int64_t i=0;i<records.size();++i){
        if(records[i].get_type()!=Variant::DICTIONARY)return {};
        Dictionary row=records[i];Variant id=row.get("identity",Variant()),pose=row.get("pose",Variant());
        if(id.get_type()!=Variant::INT || pose.get_type()!=Variant::TRANSFORM3D)return {};
        const int64_t identity=id;
        if(identity<=previous || identity>=next_identity)return {};
        const auto encoded=encode(pose);if(encoded.is_empty())return {};
        const int64_t at=24+i*64;data.encode_u64(at,identity);
        for(int j=0;j<7;++j)data.encode_double(at+8+j*8,encoded.decode_double(16+j*8));
        previous=identity;
    }
    return data;
}
Dictionary NativeVehicleStorage::decode_fleet(const PackedByteArray &data) const {
    Dictionary result;const bool ok=validate_fleet_snapshot(data);result["ok"]=ok;
    if(!ok)return result;
    Array rows;int64_t next=1;
    if(!data.is_empty() && data.decode_u32(4)==1){
        Dictionary row;row["identity"]=int64_t(1);row["pose"]=decode(data)["pose"];rows.push_back(row);next=2;
    } else if(!data.is_empty()){
        next=data.decode_u64(16);
        for(uint32_t i=0;i<data.decode_u32(8);++i){
            const int64_t at=24+int64_t(i)*64;
            Vector3 p(data.decode_double(at+8),data.decode_double(at+16),data.decode_double(at+24));
            Quaternion q(data.decode_double(at+32),data.decode_double(at+40),data.decode_double(at+48),data.decode_double(at+56));
            Dictionary row;row["identity"]=int64_t(data.decode_u64(at));row["pose"]=Transform3D(Basis(q.normalized()),p);rows.push_back(row);
        }
    }
    result["records"]=rows;result["next_identity"]=next;return result;
}

}
