// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <cmath>
namespace terraforest {
class NativeRoadEditorSettings : public godot::RefCounted {
 GDCLASS(NativeRoadEditorSettings,godot::RefCounted)
 static bool valid(int surface,double width,double depth,double clearance,double shoulder) {
  return surface>=0 && surface<=1 && std::isfinite(width) && width>=0.5 && width<=16 && std::isfinite(depth) && depth>=1 && depth<=8 && std::isfinite(clearance) && clearance>=0 && clearance<=16 && std::isfinite(shoulder) && shoulder>=0 && shoulder<=16;
 }
protected:
 static void _bind_methods() {
  godot::ClassDB::bind_method(godot::D_METHOD("encode","surface","width","depth","clearance","shoulder"),&NativeRoadEditorSettings::encode);
  godot::ClassDB::bind_method(godot::D_METHOD("decode","data"),&NativeRoadEditorSettings::decode);
  godot::ClassDB::bind_method(godot::D_METHOD("validate_snapshot","data"),&NativeRoadEditorSettings::validate_snapshot);
 }
public:
 godot::PackedByteArray encode(int surface,double width,double depth,double clearance,double shoulder) const {
  godot::PackedByteArray data;if(!valid(surface,width,depth,clearance,shoulder))return data;
  data.resize(48);data.fill(0);data.encode_u32(0,0x31534552);data.encode_u32(4,1);data.encode_u32(8,surface);
  data.encode_double(16,width);data.encode_double(24,depth);data.encode_double(32,clearance);data.encode_double(40,shoulder);return data;
 }
 bool validate_snapshot(const godot::PackedByteArray &data) const {
  if(data.is_empty())return true;
  return data.size()==48 && data.decode_u32(0)==0x31534552 && data.decode_u32(4)==1 && data.decode_u32(8)<=1 && data.decode_u32(12)==0 && valid(int(data.decode_u32(8)),data.decode_double(16),data.decode_double(24),data.decode_double(32),data.decode_double(40));
 }
 godot::Dictionary decode(const godot::PackedByteArray &data) const {
  godot::Dictionary out;out["ok"]=validate_snapshot(data);if(!bool(out["ok"]))return out;
  out["surface"]=data.is_empty()?0:int(data.decode_u32(8));out["width"]=data.is_empty()?3.0:data.decode_double(16);out["depth"]=data.is_empty()?2.0:data.decode_double(24);out["clearance"]=data.is_empty()?0.0:data.decode_double(32);out["shoulder"]=data.is_empty()?0.0:data.decode_double(40);return out;
 }
};
}
