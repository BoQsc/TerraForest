extends SceneTree
## Offline asset authoring only; runtime collision/placement runs in C++.
func _initialize() -> void:
	var parts: Array[AABB] = [
		AABB(Vector3(-2,0,-0.25),Vector3(1,3,0.5)),
		AABB(Vector3(1,0,-0.25),Vector3(1,3,0.5)),
		AABB(Vector3(-1,2,-0.25),Vector3(2,1,0.5))]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for part in parts:
		var box := BoxMesh.new()
		box.size=part.size
		var arrays := box.get_mesh_arrays()
		var offset := vertices.size()
		for vertex in arrays[Mesh.ARRAY_VERTEX]:
			vertices.append(vertex+part.get_center())
		normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		uv.append_array(arrays[Mesh.ARRAY_TEX_UV])
		for index in arrays[Mesh.ARRAY_INDEX]:
			indices.append(index+offset)
	var surface := []
	surface.resize(Mesh.ARRAY_MAX)
	surface[Mesh.ARRAY_VERTEX]=vertices
	surface[Mesh.ARRAY_NORMAL]=normals
	surface[Mesh.ARRAY_TEX_UV]=uv
	surface[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,surface)
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("8a9b9a")
	material.roughness=0.85
	mesh.surface_set_material(0,material)
	mesh.set_meta("collision_boxes",parts)
	var result := ResourceSaver.save(mesh,"res://addons/structures/prefabs/doorway_model.tres")
	print("Doorway model saved: ",result)
	quit(0 if result==OK else 1)
