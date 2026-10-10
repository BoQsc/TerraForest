// SPDX-License-Identifier: 0BSD
#include "parked_renderer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/material.hpp>
#include <set>
#include <cmath>
#include <godot_cpp/classes/mesh.hpp>
using namespace godot;
namespace terraforest {
void NativeParkedVehicleRenderer::_bind_methods(){
 ClassDB::bind_method(D_METHOD("configure","fleet","parts","capacity"),&NativeParkedVehicleRenderer::configure);
 ClassDB::bind_method(D_METHOD("refresh","center","radius","excluded","budget"),&NativeParkedVehicleRenderer::refresh);
}
void NativeParkedVehicleRenderer::hide_all(){for(auto &part:parts_){part.mesh->set_visible_instance_count(0);auto *node=Object::cast_to<MultiMeshInstance3D>(ObjectDB::get_instance(part.node));if(node)node->hide();}}
bool NativeParkedVehicleRenderer::configure(const Ref<NativeVehicleFleet> &fleet,const Array &parts,int capacity){
 if(capacity_||fleet.is_null()||capacity<1||capacity>256||parts.is_empty()||parts.size()>64)return false;
 for(int i=0;i<parts.size();++i){
  if(parts[i].get_type()!=Variant::DICTIONARY)return false;
  Dictionary row=parts[i];Variant mesh=row.get("mesh",Variant()),local=row.get("transform",Variant()),material=row.get("material",Variant());
  if(mesh.get_type()!=Variant::OBJECT||local.get_type()!=Variant::TRANSFORM3D)return false;
  Ref<Mesh> source=mesh;if(source.is_null())return false;
  Transform3D transform=local;if(!transform.is_finite()||std::abs(transform.basis.determinant())<0.000001)return false;
  if(material.get_type()!=Variant::NIL){if(material.get_type()!=Variant::OBJECT)return false;Ref<Material> value=material;if(value.is_null())return false;}
 }
 fleet_=fleet;capacity_=capacity;
 for(int i=0;i<parts.size();++i){
  Dictionary row=parts[i];Part part;part.local=row["transform"];part.mesh.instantiate();part.mesh->set_transform_format(MultiMesh::TRANSFORM_3D);
  part.mesh->set_mesh(row["mesh"]);part.mesh->set_instance_count(capacity);part.mesh->set_visible_instance_count(0);
  auto *node=memnew(MultiMeshInstance3D);node->set_multimesh(part.mesh);if(row.has("material"))node->set_material_override(row["material"]);add_child(node);
  part.node=node->get_instance_id();part.buffer.resize(capacity*12);part.buffer.fill(0);parts_.push_back(part);
 }
 return true;
}
Dictionary NativeParkedVehicleRenderer::refresh(const Vector3 &center,double radius,const PackedInt64Array &excluded,int budget){
 Dictionary result;result["ok"]=false;result["rendered"]=0;result["upload_bytes"]=int64_t(0);
 if(fleet_.is_null())return result;
 for(auto &part:parts_){
  auto *node=Object::cast_to<MultiMeshInstance3D>(ObjectDB::get_instance(part.node));
  if(!node||node->get_multimesh()!=part.mesh||part.mesh->get_instance_count()!=capacity_||part.mesh->get_transform_format()!=MultiMesh::TRANSFORM_3D||part.mesh->is_using_colors()||part.mesh->is_using_custom_data()){
   hide_all();result["reason"]="renderer_resource_modified";return result;
  }
 }
 if(excluded.size()>256){hide_all();return result;}
 result=fleet_->query_near(center,radius,capacity_,budget);result["rendered"]=0;result["upload_bytes"]=int64_t(0);
 if(!bool(result["ok"])||!bool(result["complete"])){hide_all();return result;}
 std::set<int64_t> skip;for(int i=0;i<excluded.size();++i)skip.insert(excluded[i]);
 PackedInt64Array ids=result["ids"],visible;std::vector<Transform3D> poses;
 for(int i=0;i<ids.size();++i){if(skip.count(ids[i]))continue;Dictionary record=fleet_->get_record(ids[i]);if(!bool(record["present"])){hide_all();result["ok"]=false;return result;}poses.push_back(record["pose"]);visible.push_back(ids[i]);}
 int64_t uploaded=0;
 for(auto &part:parts_){
  bool changed=false;float *out=nullptr;
  for(size_t i=0;i<poses.size();++i){
   Transform3D transform=poses[i]*part.local;float row[12];
   for(int axis=0;axis<3;++axis){for(int column=0;column<3;++column)row[axis*4+column]=transform.basis[axis][column];row[axis*4+3]=transform.origin[axis];}
   const float *old=part.buffer.ptr()+i*12;bool same=true;for(int j=0;j<12;++j)same= same && old[j]==row[j];if(same)continue;
   if(!out)out=part.buffer.ptrw();for(int j=0;j<12;++j)out[i*12+j]=row[j];changed=true;
  }
  if(changed){part.mesh->set_buffer(part.buffer);uploaded+=capacity_*48;}
  part.mesh->set_visible_instance_count(poses.size());
  auto *node=Object::cast_to<MultiMeshInstance3D>(ObjectDB::get_instance(part.node));if(node)node->show();
 }
 result["ids"]=visible;result["rendered"]=int64_t(poses.size());result["upload_bytes"]=uploaded;return result;
}
}
