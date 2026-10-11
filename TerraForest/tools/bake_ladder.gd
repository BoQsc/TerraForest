# SPDX-License-Identifier: 0BSD
# Offline authoring: one shared mesh, 168 triangles, one runtime collision proxy.
extends SceneTree
func _initialize() -> void:
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var boxes: Array[AABB]=[AABB(Vector3(-0.45,0,-0.06),Vector3(0.08,3.6,0.12)),AABB(Vector3(0.37,0,-0.06),Vector3(0.08,3.6,0.12))]
	for rung in 12: boxes.append(AABB(Vector3(-0.37,0.15+rung*0.28,-0.045),Vector3(0.74,0.065,0.09)))
	for bounds in boxes:
		var box:=BoxMesh.new();box.size=bounds.size
		surface.append_from(box,0,Transform3D(Basis.IDENTITY,bounds.get_center()))
	var material:=StandardMaterial3D.new();material.albedo_color=Color("98754e");material.roughness=0.9
	material.albedo_texture=load("res://addons/structures/textures/terraforest/wood_albedo.png")
	material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	surface.set_material(material)
	var mesh:=surface.commit();mesh.resource_name="Wooden ladder"
	var result:=ResourceSaver.save(mesh,"res://addons/structures/prefabs/ladder_model.tres")
	print("BAKED ladder triangles=168 result=",result)
	quit(0 if result==OK else 1)
