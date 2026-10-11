# SPDX-License-Identifier: 0BSD
extends RefCounted
# Startup asset construction only. All per-instance gait work is native/shader.
static func build() -> ArrayMesh:
 var vertices:=PackedVector3Array();var normals:=PackedVector3Array();var colors:=PackedColorArray();var indices:=PackedInt32Array()
 var parts=[
  [Vector3(0.52,0.65,0.30),Vector3(0,0.15,0),Vector3.ZERO,0.5],
  [Vector3(0.32,0.32,0.32),Vector3(0,0.69,0),Vector3.ZERO,0.5],
  [Vector3(0.16,0.62,0.22),Vector3(-0.38,0.13,0),Vector3(-0.38,0.44,0),0.75],
  [Vector3(0.16,0.62,0.22),Vector3(0.38,0.13,0),Vector3(0.38,0.44,0),0.25],
  [Vector3(0.23,0.72,0.28),Vector3(-0.16,-0.51,0),Vector3(-0.16,-0.15,0),0.25],
  [Vector3(0.23,0.72,0.28),Vector3(0.16,-0.51,0),Vector3(0.16,-0.15,0),0.75]]
 for part in parts:
  var box:=BoxMesh.new();box.size=part[0];var arrays:=box.get_mesh_arrays();var offset:=vertices.size()
  var pivot: Vector3=(part[2]+Vector3.ONE)*0.5
  for i in arrays[Mesh.ARRAY_VERTEX].size():
   vertices.append(arrays[Mesh.ARRAY_VERTEX][i]+part[1]);normals.append(arrays[Mesh.ARRAY_NORMAL][i]);colors.append(Color(pivot.x,pivot.y,pivot.z,part[3]))
  for index in arrays[Mesh.ARRAY_INDEX]:indices.append(index+offset)
 var data:=[];data.resize(Mesh.ARRAY_MAX);data[Mesh.ARRAY_VERTEX]=vertices;data[Mesh.ARRAY_NORMAL]=normals;data[Mesh.ARRAY_COLOR]=colors;data[Mesh.ARRAY_INDEX]=indices
 var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data)
 var material:=ShaderMaterial.new();material.shader=load("res://addons/world_runtime/actor_gait.gdshader");mesh.surface_set_material(0,material)
 # Conservative envelope includes the largest permitted limb swing.
 mesh.custom_aabb=AABB(Vector3(-0.55,-0.95,-0.65),Vector3(1.1,1.9,1.3))
 return mesh
