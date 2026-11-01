// SPDX-License-Identifier: 0BSD
#include "trader_ride_state.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
using namespace godot;
namespace terraforest {
namespace {
constexpr int HEADER=96,LIMIT=8192;
constexpr uint32_t MAGIC=0x31445254;
bool point(Vector3 v){return v.is_finite()&&v.length()<8192;}
Vector3 read_point(const PackedByteArray &b,int offset){return Vector3(b.decode_float(offset),b.decode_float(offset+4),b.decode_float(offset+8));}
void write_point(PackedByteArray &b,int offset,Vector3 v){b.encode_float(offset,v.x);b.encode_float(offset+4,v.y);b.encode_float(offset+8,v.z);}
Dictionary empty_state(){
    Dictionary s;s["phase"]=0;s["vehicle"]=int64_t(0);s["fare"]=0;s["paid"]=false;s["refund"]=0;
    s["destination"]=0;s["passenger"]=false;s["seated"]=false;s["cursor"]=0;s["title"]=String();
    s["driver_position"]=Vector3();s["home"]=Vector3();s["driver_yaw"]=0.0;
    s["outbound"]=PackedVector3Array();s["return_route"]=PackedVector3Array();return s;
}
}
void NativeTraderRideState::_bind_methods(){
    ClassDB::bind_method(D_METHOD("snapshot"),&NativeTraderRideState::snapshot);
    ClassDB::bind_method(D_METHOD("set_state","state"),&NativeTraderRideState::set_state);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeTraderRideState::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeTraderRideState::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeTraderRideState::restore_storage_snapshot);
}
Dictionary NativeTraderRideState::decode(const PackedByteArray &b){
    if(b.is_empty())return empty_state();
    if(b.size()<HEADER||b.size()>HEADER+96+LIMIT*24||b.decode_u32(0)!=MAGIC||b.decode_u32(4)!=1)return {};
    const int phase=b.decode_u32(8);const uint64_t vehicle=b.decode_u64(12);
    const uint32_t fare=b.decode_u32(20),paid=b.decode_u32(24),refund=b.decode_u32(28),destination=b.decode_u32(32),passenger=b.decode_u32(36),seated=b.decode_u32(40),cursor=b.decode_u32(44),out_count=b.decode_u32(48),return_count=b.decode_u32(52),name_size=b.decode_u32(56);
    Vector3 driver=read_point(b,60),home=read_point(b,72);double yaw=b.decode_float(84);
    if(phase<0||phase>6||vehicle>INT64_MAX||fare>50000||paid>1||refund>50000||passenger>1||seated>1||out_count>LIMIT||return_count>LIMIT||name_size>96||!point(driver)||!point(home)||!std::isfinite(yaw)||std::abs(yaw)>100||b.decode_u32(88)!=0||b.decode_u32(92)!=0)return {};
    if(int64_t(HEADER)+name_size+int64_t(out_count+return_count)*12!=b.size())return {};
    if(phase!=0&&(vehicle==0||fare==0||out_count<2||return_count<2||name_size==0))return {};
    if(passenger&&(phase!=2&&phase!=3&&phase!=6))return {};
    if(paid&&fare==0)return {};
    const uint32_t active_count=phase==4?return_count:out_count;
    if(cursor>0&&(active_count<2||cursor>=active_count-1))return {};
    auto label=b.slice(HEADER,HEADER+name_size);
    for(int i=0;i<label.size();i++)if(label[i]<32||label[i]>126)return {};
    int offset=HEADER+name_size;
    PackedVector3Array outward,inward;
    for(uint32_t i=0;i<out_count+return_count;i++,offset+=12){
        Vector3 p=read_point(b,offset);if(!point(p))return {};
        auto &path=i<out_count?outward:inward;
        if(path.size()>0&&p.distance_to(path[path.size()-1])<.01)return {};
        path.push_back(p);
    }
    Dictionary s=empty_state();s["phase"]=phase;s["vehicle"]=int64_t(vehicle);s["fare"]=fare;s["paid"]=bool(paid);s["refund"]=refund;
    s["destination"]=destination;s["passenger"]=bool(passenger);s["seated"]=bool(seated);s["cursor"]=cursor;s["title"]=label.get_string_from_ascii();
    s["driver_position"]=driver;s["home"]=home;s["driver_yaw"]=yaw;s["outbound"]=outward;s["return_route"]=inward;return s;
}
Dictionary NativeTraderRideState::snapshot()const{return decode(data);}
bool NativeTraderRideState::set_state(const Dictionary &input){
    Dictionary s=empty_state();
    for(const char *key:{"phase","vehicle","fare","refund","destination","cursor"}){
        if(input.has(key)){if(input[key].get_type()!=Variant::INT||int64_t(input[key])<0)return false;s[key]=input[key];}
    }
    for(const char *key:{"paid","passenger","seated"}){if(input.has(key)){if(input[key].get_type()!=Variant::BOOL)return false;s[key]=input[key];}}
    for(const char *key:{"driver_position","home"}){if(input.has(key)){if(input[key].get_type()!=Variant::VECTOR3)return false;s[key]=input[key];}}
    for(const char *key:{"outbound","return_route"}){if(input.has(key)){if(input[key].get_type()!=Variant::PACKED_VECTOR3_ARRAY)return false;s[key]=input[key];}}
    if(input.has("title")){if(input["title"].get_type()!=Variant::STRING)return false;s["title"]=input["title"];}
    if(input.has("driver_yaw")){if(input["driver_yaw"].get_type()!=Variant::FLOAT&&input["driver_yaw"].get_type()!=Variant::INT)return false;s["driver_yaw"]=input["driver_yaw"];}
    for(const char *key:{"phase","fare","refund","destination","cursor"})if(int64_t(s[key])>UINT32_MAX)return false;
    PackedVector3Array out=s["outbound"],back=s["return_route"];auto label=String(s["title"]).to_utf8_buffer();
    if(out.size()>LIMIT||back.size()>LIMIT||label.size()>96)return false;
    PackedByteArray b;b.resize(HEADER+label.size()+(out.size()+back.size())*12);b.fill(0);
    b.encode_u32(0,MAGIC);b.encode_u32(4,1);b.encode_u32(8,int64_t(s["phase"]));b.encode_u64(12,int64_t(s["vehicle"]));
    b.encode_u32(20,int64_t(s["fare"]));b.encode_u32(24,bool(s["paid"]));b.encode_u32(28,int64_t(s["refund"]));b.encode_u32(32,int64_t(s["destination"]));
    b.encode_u32(36,bool(s["passenger"]));b.encode_u32(40,bool(s["seated"]));b.encode_u32(44,int64_t(s["cursor"]));
    b.encode_u32(48,out.size());b.encode_u32(52,back.size());b.encode_u32(56,label.size());
    write_point(b,60,s["driver_position"]);write_point(b,72,s["home"]);b.encode_float(84,double(s["driver_yaw"]));
    int offset=HEADER;for(int i=0;i<label.size();i++)b.set(offset++,label[i]);
    for(auto path:{out,back})for(int i=0;i<path.size();i++,offset+=12)write_point(b,offset,path[i]);
    return restore_storage_snapshot(b);
}
bool NativeTraderRideState::validate_snapshot(const PackedByteArray &b)const{return !decode(b).is_empty();}
bool NativeTraderRideState::restore_storage_snapshot(const PackedByteArray &b){if(!validate_snapshot(b))return false;data=b;return true;}
}
