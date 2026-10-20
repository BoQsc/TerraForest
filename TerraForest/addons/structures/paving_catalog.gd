# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY:="architecture/concrete_paving/v1"
static func register(world:Node3D)->bool:
 var mesh:=BoxMesh.new();mesh.size=Vector3.ONE
 var material:=StandardMaterial3D.new()
 material.albedo_color=Color("85867e");material.roughness=0.95
 material.albedo_texture=load("res://addons/structures/textures/original/concrete_albedo.png")
 mesh.material=material
 # Ground-supported surfacing uses the terrain collider. No rigid bodies or
 # additional per-slab collision objects; the top is only 15 mm above terrain.
 return world.register_model(KEY,mesh)!=null
static func records(poses:Array)->PackedFloat32Array:
 var result:=PackedFloat32Array()
 for pose:Transform3D in poses:
  for axis in 3:
   result.append_array(PackedFloat32Array([pose.basis.x[axis],pose.basis.y[axis],pose.basis.z[axis],pose.origin[axis]]))
 return result
