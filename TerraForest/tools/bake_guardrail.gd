# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void:
	var boxes: Array[AABB]=[]
	for y in [0.12,1.02]:boxes.append(AABB(Vector3(-0.045,y,-2),Vector3(0.09,0.08,4)))
	for z in [-1.96,-1,0,1,1.96]:boxes.append(AABB(Vector3(-0.04,0,z-0.04),Vector3(0.08,1.1,0.08)))
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bounds: AABB in boxes:
		var box:=BoxMesh.new();box.size=bounds.size
		surface.append_from(box,0,Transform3D(Basis.IDENTITY,bounds.get_center()))
	var material:=StandardMaterial3D.new();material.albedo_color=Color("424d54");material.metallic=0.65;material.roughness=0.6
	surface.set_material(material);var mesh:=surface.commit();mesh.resource_name="Metal guardrail"
	var error:=ResourceSaver.save(mesh,"res://addons/structures/prefabs/guardrail_model.tres")
	print("GUARDRAIL_BAKE result=",error);quit(0 if error==OK else 1)
