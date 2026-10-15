# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void:
	var boxes: Array[AABB]=[]
	for z in [-0.93,0.93]:boxes.append(AABB(Vector3(-0.09,0,z-0.07),Vector3(0.18,1.3,0.14)))
	for y in [0.32,0.72,1.12]:boxes.append(AABB(Vector3(-0.06,y,-0.86),Vector3(0.12,0.12,1.72)))
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bounds: AABB in boxes:
		var box:=BoxMesh.new();box.size=bounds.size
		surface.append_from(box,0,Transform3D(Basis.IDENTITY,bounds.get_center()))
	var material:=StandardMaterial3D.new();material.albedo_color=Color("b39b7a");material.roughness=0.95
	material.albedo_texture=load("res://addons/structures/textures/terraforest/wood_albedo.png")
	surface.set_material(material);var mesh:=surface.commit();mesh.resource_name="Wooden fence section"
	var error:=ResourceSaver.save(mesh,"res://addons/structures/prefabs/fence_model.tres")
	print("FENCE_BAKE result=",error);quit(0 if error==OK else 1)
