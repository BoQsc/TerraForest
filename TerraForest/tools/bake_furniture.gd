# SPDX-License-Identifier: 0BSD
# Offline asset authoring only. Runtime loads baked meshes into native batches.
extends SceneTree
func _initialize() -> void:
	var assets: Dictionary={
		"table": [AABB(Vector3(-0.8,0.68,-0.45),Vector3(1.6,0.12,0.9))],
		"chair": [AABB(Vector3(-0.24,0.42,-0.24),Vector3(0.48,0.08,0.48)),AABB(Vector3(-0.24,0.5,0.17),Vector3(0.48,0.48,0.07))],
		"shelf": [AABB(Vector3(-0.6,0,-0.2),Vector3(0.08,1.8,0.4)),AABB(Vector3(0.52,0,-0.2),Vector3(0.08,1.8,0.4)),AABB(Vector3(-0.52,0,0.15),Vector3(1.04,1.8,0.05))]
	}
	for x in [-0.72,0.62]:
		for z in [-0.37,0.27]: assets.table.append(AABB(Vector3(x,0,z),Vector3(0.1,0.68,0.1)))
	for x in [-0.22,0.14]:
		for z in [-0.22,0.14]: assets.chair.append(AABB(Vector3(x,0,z),Vector3(0.08,0.42,0.08)))
	for y in [0.0,0.55,1.1,1.72]: assets.shelf.append(AABB(Vector3(-0.52,y,-0.2),Vector3(1.04,0.08,0.4)))
	for name: String in assets:
		var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var boxes: Array[AABB]=[]
		for bounds: AABB in assets[name]:
			var box:=BoxMesh.new();box.size=bounds.size
			surface.append_from(box,0,Transform3D(Basis.IDENTITY,bounds.get_center()))
			boxes.append(bounds)
		var material:=StandardMaterial3D.new();material.albedo_color=Color("98754e");material.roughness=0.9
		material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.albedo_texture=load("res://addons/structures/textures/terraforest/wood_albedo.png")
		surface.set_material(material)
		var mesh:=surface.commit();mesh.resource_name="Wooden "+name
		mesh.set_meta("collision_boxes",boxes)
		var error:=ResourceSaver.save(mesh,"res://addons/structures/prefabs/"+name+"_model.tres")
		if error!=OK: quit(1);return
		print("BAKED ",name," boxes=",boxes.size()," triangles=",boxes.size()*12)
	quit()
