# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for bounds: AABB in [AABB(Vector3(0,0,-0.06),Vector3(1,2.2,0.12)),AABB(Vector3(0.07,0.12,-0.07),Vector3(0.86,0.08,0.14)),AABB(Vector3(0.07,2,-0.07),Vector3(0.86,0.08,0.14))]:
		var box:=BoxMesh.new();box.size=bounds.size
		surface.append_from(box,0,Transform3D(Basis.IDENTITY,bounds.get_center()))
	var material:=StandardMaterial3D.new();material.albedo_color=Color("98754e");material.roughness=0.85
	material.albedo_texture=load("res://addons/structures/textures/terraforest/wood_albedo.png")
	surface.set_material(material);var mesh:=surface.commit()
	surface=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var handle:=BoxMesh.new();handle.size=Vector3(0.16,0.04,0.22)
	surface.append_from(handle,0,Transform3D(Basis.IDENTITY,Vector3(0.82,1,0)))
	var metal:=StandardMaterial3D.new();metal.albedo_color=Color("565b60");metal.metallic=0.8;metal.roughness=0.4
	surface.set_material(metal);surface.commit(mesh)
	mesh.resource_name="Hinged wooden door"
	var error:=ResourceSaver.save(mesh,"res://addons/structures/prefabs/door_model.tres")
	print("DOOR_BAKE result=",error);quit(0 if error==OK else 1)
