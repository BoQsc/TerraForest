// SPDX-License-Identifier: 0BSD
#include "pose.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
namespace terraforest {
using namespace godot;
void NativePlayerPose::_bind_methods() {
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativePlayerPose::validate_snapshot);
    ClassDB::bind_method(D_METHOD("encode","position","yaw","pitch","fly","tool"),&NativePlayerPose::encode);
    ClassDB::bind_method(D_METHOD("decode","data"),&NativePlayerPose::decode);
}
bool NativePlayerPose::validate_snapshot(const PackedByteArray &data) const {
    if(data.is_empty())return true; // Legacy world: use default spawn.
    if(data.size()!=56||data.decode_u32(0)!=0x31504654||data.decode_u32(4)!=1)return false;
    for(int i=0;i<5;++i)if(!std::isfinite(data.decode_double(8+i*8)))return false;
    const bool fly=data.decode_u32(48)==1;
    if(data.decode_u32(48)>1||data.decode_u32(52)>4)return false;
    // Bounds match the current playable world, not an unrestricted teleport packet.
    const double x=data.decode_double(8),y=data.decode_double(16),z=data.decode_double(24);
    if(x<(fly?-1500:2)||x>(fly?3500:1998)||z<(fly?-1500:2)||z>(fly?3500:1998)||y<1.1||y>(fly?3000:600))return false;
    return std::abs(data.decode_double(32))<=3.141593&&std::abs(data.decode_double(40))<=1.530001;
}
PackedByteArray NativePlayerPose::encode(Vector3 position,double yaw,double pitch,bool fly,int64_t tool) const {
    PackedByteArray data;data.resize(56);data.encode_u32(0,0x31504654);data.encode_u32(4,1);
    data.encode_double(8,position.x);data.encode_double(16,position.y);data.encode_double(24,position.z);
    data.encode_double(32,yaw);data.encode_double(40,pitch);data.encode_u32(48,fly?1:0);data.encode_u32(52,tool);
    if(tool<0||tool>4||!validate_snapshot(data))return {};
    return data;
}
Dictionary NativePlayerPose::decode(const PackedByteArray &data) const {
    Dictionary out;out["ok"]=validate_snapshot(data);
    if(!bool(out["ok"])||data.is_empty())return out;
    out["position"]=Vector3(data.decode_double(8),data.decode_double(16),data.decode_double(24));
    out["yaw"]=data.decode_double(32);out["pitch"]=data.decode_double(40);
    out["fly"]=data.decode_u32(48)==1;out["tool"]=int64_t(data.decode_u32(52));return out;
}
}
