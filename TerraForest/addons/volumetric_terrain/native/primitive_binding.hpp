// SPDX-License-Identifier: 0BSD
#pragma once
#include "primitive_stamp.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <limits>

namespace terraforest {
class NativeTerrainStamp : public godot::RefCounted {
 GDCLASS(NativeTerrainStamp,godot::RefCounted)
 PrimitiveStamp stamp_;
 bool ready_=false;
 static V3 native(godot::Vector3 v){return {v.x,v.y,v.z};}
 static godot::Vector3 vector(V3 v){return {v.x,v.y,v.z};}
protected:
 static void _bind_methods(){
  godot::ClassDB::bind_method(godot::D_METHOD("configure","shape","center","half_extents","quarter_turns","steps"),&NativeTerrainStamp::configure);
  godot::ClassDB::bind_method(godot::D_METHOD("packet","add","material"),&NativeTerrainStamp::packet);
  godot::ClassDB::bind_method(godot::D_METHOD("inspect","packet"),&NativeTerrainStamp::inspect);
  godot::ClassDB::bind_method(godot::D_METHOD("distance","point"),&NativeTerrainStamp::distance);
 }
public:
 bool configure(int64_t shape,godot::Vector3 center,godot::Vector3 half,int64_t turn,int64_t steps){
  if(ready_||shape<0||shape>4||turn<0||turn>3||steps<1||steps>16)return false;
  PrimitiveStamp s;s.shape=u32(shape);s.center=native(center);s.half=native(half);s.turn=u32(turn);s.steps=u32(steps);
  if(!s.valid())return false;stamp_=s;ready_=true;return true;
 }
 godot::PackedByteArray packet(bool add,int64_t material)const{
  godot::PackedByteArray result;
  if(!ready_||material<1||material>3)return result;
  PrimitiveStamp s=stamp_;s.add=add;s.material=u32(material);
  Bytes data;s.encode(data);result.resize(data.n);if(data.n)copy_bytes(result.ptrw(),data.p,data.n);data.release();return result;
 }
 godot::Dictionary inspect(const godot::PackedByteArray &packet)const{
  godot::Dictionary result;result["valid"]=false;PrimitiveStamp s;
  if(packet.size()!=52||!s.decode(packet.ptr(),int(packet.size())))return result;
  const V3 extent=s.extent();result["valid"]=true;result["shape"]=s.shape;result["add"]=bool(s.add);
  result["bounds"]=godot::AABB(vector(s.center-extent),vector(extent*2));
  result["edit_bounds"]=godot::AABB(vector(s.center-extent)-godot::Vector3(5,5,5),vector(extent*2)+godot::Vector3(10,10,10));
  return result;
 }
 double distance(godot::Vector3 p)const{return ready_&&p.is_finite()?stamp_.distance(native(p)):std::numeric_limits<double>::infinity();}
};
}
