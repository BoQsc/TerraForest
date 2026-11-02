// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <algorithm>
#include <cmath>
namespace terraforest {
class NativePlayerLife : public godot::RefCounted {
    GDCLASS(NativePlayerLife,godot::RefCounted)
    double health=100,yaw=0;
    godot::Vector3 spawn;
    bool has_spawn=false;
    uint32_t deaths=0;
    static bool valid_spawn(godot::Vector3 point,double heading){return point.is_finite()&&point.x>=2&&point.x<=1998&&point.z>=2&&point.z<=1998&&point.y>=1.1&&point.y<=600&&std::isfinite(heading)&&std::abs(heading)<=3.141593;}
protected:
    static void _bind_methods(){
        using namespace godot;
        ClassDB::bind_method(D_METHOD("damage","amount"),&NativePlayerLife::damage);
        ClassDB::bind_method(D_METHOD("set_spawn","position","yaw"),&NativePlayerLife::set_spawn);
        ClassDB::bind_method(D_METHOD("respawn"),&NativePlayerLife::respawn);
        ClassDB::bind_method(D_METHOD("snapshot"),&NativePlayerLife::snapshot);
        ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativePlayerLife::capture_storage_snapshot);
        ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativePlayerLife::validate_snapshot);
        ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativePlayerLife::restore_storage_snapshot);
    }
public:
    bool damage(double amount){if(!std::isfinite(amount)||amount<=0||health<=0)return false;health=std::max(0.0,health-amount);if(health==0&&deaths<0xffffffffu)++deaths;return true;}
    bool set_spawn(godot::Vector3 point,double heading){if(!valid_spawn(point,heading))return false;spawn=point;yaw=heading;has_spawn=true;return true;}
    bool respawn(){if(health>0||!has_spawn)return false;health=100;return true;}
    godot::Dictionary snapshot()const{godot::Dictionary out;out["health"]=health;out["maximum_health"]=100;out["dead"]=health==0;out["has_spawn"]=has_spawn;out["spawn"]=spawn;out["yaw"]=yaw;out["deaths"]=int64_t(deaths);return out;}
    godot::PackedByteArray capture_storage_snapshot()const{
        godot::PackedByteArray bytes;bytes.resize(56);bytes.fill(0);bytes.encode_u32(0,0x314c4654);bytes.encode_u32(4,1);bytes.encode_double(8,health);
        bytes.encode_double(16,spawn.x);bytes.encode_double(24,spawn.y);bytes.encode_double(32,spawn.z);bytes.encode_double(40,yaw);bytes.encode_u32(48,has_spawn);bytes.encode_u32(52,deaths);return bytes;
    }
    bool validate_snapshot(const godot::PackedByteArray &bytes)const{
        if(bytes.is_empty())return true;
        if(bytes.size()!=56||bytes.decode_u32(0)!=0x314c4654||bytes.decode_u32(4)!=1||bytes.decode_u32(48)>1)return false;
        for(int offset=8;offset<=40;offset+=8)if(!std::isfinite(bytes.decode_double(offset)))return false;
        if(bytes.decode_double(8)<0||bytes.decode_double(8)>100)return false;
        if(bytes.decode_u32(48))return valid_spawn({float(bytes.decode_double(16)),float(bytes.decode_double(24)),float(bytes.decode_double(32))},bytes.decode_double(40));
        return bytes.decode_double(16)==0&&bytes.decode_double(24)==0&&bytes.decode_double(32)==0&&bytes.decode_double(40)==0;
    }
    bool restore_storage_snapshot(const godot::PackedByteArray &bytes){
        if(!validate_snapshot(bytes))return false;
        if(bytes.is_empty()){health=100;spawn={};yaw=0;has_spawn=false;deaths=0;return true;}
        health=bytes.decode_double(8);spawn={float(bytes.decode_double(16)),float(bytes.decode_double(24)),float(bytes.decode_double(32))};yaw=bytes.decode_double(40);has_spawn=bytes.decode_u32(48);deaths=bytes.decode_u32(52);return true;
    }
};
}
