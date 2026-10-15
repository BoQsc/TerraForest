# SPDX-License-Identifier: 0BSD
# Offline authoring; runtime uses shared native model batches.
extends SceneTree
func _initialize() -> void:
	var mesh:=ArrayMesh.new()
	var frame:=StandardMaterial3D.new()
	frame.albedo_color=Color("98754e");frame.roughness=0.9
	frame.albedo_texture=load("res://addons/structures/textures/terraforest/wood_albedo.png")
	var glass:=StandardMaterial3D.new()
	glass.albedo_color=Color(0.65,0.82,0.86,0.22)
	glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness=0.16
	var boxes: Array[AABB]=[
		AABB(Vector3(-1,0,-0.1),Vector3(0.1,2,0.2)),
		AABB(Vector3(0.9,0,-0.1),Vector3(0.1,2,0.2)),
		AABB(Vector3(-0.9,0,-0.1),Vector3(1.8,0.1,0.2)),
		AABB(Vector3(-0.9,1.9,-0.1),Vector3(1.8,0.1,0.2)),
		AABB(Vector3(-0.035,0.1,-0.08),Vector3(0.07,1.8,0.16))]
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bounds: AABB in boxes:
		var box:=BoxMesh.new();box.size=bounds.size
		surface.append_from(box,0,Transform3D(Basis.IDENTITY,bounds.get_center()))
	surface.set_material(frame);surface.commit(mesh)
	surface=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pane:=BoxMesh.new();pane.size=Vector3(1.8,1.8,0.025)
	surface.append_from(pane,0,Transform3D(Basis.IDENTITY,Vector3(0,1,0)))
	surface.set_material(glass);surface.commit(mesh)
	mesh.resource_name="Wood framed glass window"
	var error:=ResourceSaver.save(mesh,"res://addons/structures/prefabs/window_model.tres")
	print("WINDOW_BAKE result=",error)
	quit(0 if error==OK else 1)
