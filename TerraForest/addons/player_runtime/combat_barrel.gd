# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY:="combat/explosive_barrel/v1"
const ITEM:=222
const BOUNDS:=AABB(Vector3(-.36,0,-.36),Vector3(.72,1.05,.72))
static func mesh()->ArrayMesh:
	var result:=ArrayMesh.new()
	for band in 5:
		var cylinder:=CylinderMesh.new();cylinder.radial_segments=24;cylinder.rings=1
		cylinder.top_radius=.36 if band in [1,3] else .34;cylinder.bottom_radius=cylinder.top_radius
		cylinder.height=.055 if band in [1,3] else (.08 if band==4 else .46)
		var material:=StandardMaterial3D.new();material.albedo_color=Color("d6ad42") if band==2 else Color("353d43") if band in [1,3] else Color("9a3229");material.roughness=.64;material.metallic=.5
		var arrays:=cylinder.get_mesh_arrays();var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var y:float=[.23,.28,.70,.78,1.01][band]
		for index in vertices.size():vertices[index].y+=y
		arrays[Mesh.ARRAY_VERTEX]=vertices;result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(band,material)
	return result
static func register(world:Node)->Node3D:
	var collection:Node3D=world.register_model(KEY,mesh())
	if collection==null or not collection.configure_collision(BOUNDS,96,256,8):return null
	return collection
