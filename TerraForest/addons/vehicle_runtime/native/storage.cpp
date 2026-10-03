// SPDX-License-Identifier: 0BSD
#include "storage.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeVehicleStorage::_bind_methods(){
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
}
