// SPDX-License-Identifier: 0BSD
#pragma once
#include "../core.h"
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <cmath>

namespace terraforest::experimental {
// Structural validation only. The owner must separately validate provenance and
// freshness before and after construction. No materials/collision are produced.
static godot::Array surface_arrays(const godot::Dictionary&packet){
 for(const char*key:{"positions","normals","indices"})
  if(!packet.has(key)||godot::Variant(packet[key]).get_type()!=godot::Variant::PACKED_BYTE_ARRAY)return {};
 godot::PackedByteArray p=packet["positions"],n=packet["normals"],i=packet["indices"];
 if(p.size()%12||n.size()!=p.size()||i.size()%12||p.size()>12000000||i.size()>12000000)return {};
 const int vertices=int(p.size()/12),indices=int(i.size()/4);
 godot::PackedVector3Array positions,normals;godot::PackedInt32Array triangles;
 if(positions.resize(vertices)!=godot::OK||normals.resize(vertices)!=godot::OK||triangles.resize(indices)!=godot::OK)return {};
 auto*position_data=positions.ptrw();auto*normal_data=normals.ptrw();auto*index_data=triangles.ptrw();
 Reader pr{p.ptr(),int(p.size())},nr{n.ptr(),int(n.size())},ir{i.ptr(),int(i.size())};
 for(int at=0;at<vertices;at++){
  V3 point=pr.vec(),normal=nr.vec();
  if(!std::isfinite(point.x)||!std::isfinite(point.y)||!std::isfinite(point.z)||point.x<0||point.x>WORLD||point.z<0||point.z>WORLD||point.y<0||point.y>WORLD_Y)return {};
  float squared=dot(normal,normal);
  if(!std::isfinite(squared)||std::abs(squared-1.f)>0.001f)return {};
  position_data[at]={point.x,point.y,point.z};normal_data[at]={normal.x,normal.y,normal.z};
 }
 for(int at=0;at<indices;at++){u32 index=ir.u();if(index>=u32(vertices))return {};index_data[at]=int32_t(index);}
 godot::Array arrays;arrays.resize(godot::Mesh::ARRAY_MAX);arrays[godot::Mesh::ARRAY_VERTEX]=positions;arrays[godot::Mesh::ARRAY_NORMAL]=normals;arrays[godot::Mesh::ARRAY_INDEX]=triangles;
 return arrays;
}
static godot::Ref<godot::ArrayMesh> make_surface_mesh(const godot::Dictionary&packet){
 auto arrays=surface_arrays(packet);if(arrays.is_empty()||godot::PackedInt32Array(arrays[godot::Mesh::ARRAY_INDEX]).is_empty())return {};
 godot::Ref<godot::ArrayMesh> mesh;mesh.instantiate();mesh->add_surface_from_arrays(godot::Mesh::PRIMITIVE_TRIANGLES,arrays);
 return mesh->get_surface_count()==1?mesh:godot::Ref<godot::ArrayMesh>{};
}
}
