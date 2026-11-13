# SPDX-License-Identifier: CC0-1.0
# Retained independent reference from characters/runtime/zombie.gd, before native skinning.
extends RefCounted
static func bake(actor:Node3D,source: MeshInstance3D, to_local: Transform3D) -> ArrayMesh:
	# Standard CPU linear-blend skinning avoids a GPU readback and works headless.
	# Meshes in the supplied GLB are identity children of the imported actor.skeleton.
	var result := ArrayMesh.new()
	var binds: Array[Transform3D] = []
	var skin := source.skin
	if skin != null:
		for bind in skin.get_bind_count():
			var name := skin.get_bind_name(bind)
			var index:int = actor.skeleton.find_bone(name) if name != &"" else skin.get_bind_bone(bind)
			var transform:Transform3D = actor._current_bone_pose(index) * skin.get_bind_pose(bind) if index >= 0 else Transform3D.IDENTITY
			binds.append(to_local * actor.skeleton.global_transform * transform)
	var unskinned := to_local * source.global_transform
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var count := vertices.size()
		# Head BiteOpen is a native glTF morph, evaluated before skinning. Keep
		# that mouth pose when a head is severed or sampled for a real bite.
		if source.mesh is ArrayMesh and source.mesh.get_blend_shape_count() > 0:
			var morphs: Array = (source.mesh as ArrayMesh).surface_get_blend_shape_arrays(surface)
			var base_vertices := vertices.duplicate()
			var base_normals := normals.duplicate()
			var relative := (source.mesh as ArrayMesh).blend_shape_mode == Mesh.BLEND_SHAPE_MODE_RELATIVE
			for morph in mini(morphs.size(), source.mesh.get_blend_shape_count()):
				var amount := source.get_blend_shape_value(morph)
				if not is_finite(amount) or absf(amount) < 0.000001:
					continue
				var shape_arrays: Array = morphs[morph]
				if shape_arrays.size() < Mesh.ARRAY_MAX:
					continue
				var morph_vertices: PackedVector3Array = shape_arrays[Mesh.ARRAY_VERTEX] if shape_arrays[Mesh.ARRAY_VERTEX] != null else PackedVector3Array()
				var morph_normals: PackedVector3Array = shape_arrays[Mesh.ARRAY_NORMAL] if shape_arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
				for vertex in count:
					if morph_vertices.size() == count:
						vertices[vertex] += (morph_vertices[vertex] if relative else morph_vertices[vertex] - base_vertices[vertex]) * amount
					if morph_normals.size() == count and normals.size() == count:
						normals[vertex] += (morph_normals[vertex] if relative else morph_normals[vertex] - base_normals[vertex]) * amount
		var influences := bones.size() / count if count > 0 else 0
		for vertex in count:
			var position := Vector3.ZERO
			var normal := Vector3.ZERO
			var tangent := Vector3.ZERO
			var total := 0.0
			var initial_normal := normals[vertex] if normals.size() == count else Vector3.UP
			var initial_tangent := Vector3(tangents[vertex * 4], tangents[vertex * 4 + 1], tangents[vertex * 4 + 2]) if tangents.size() == count * 4 else Vector3.RIGHT
			for influence in influences:
				var weight := weights[vertex * influences + influence]
				var bind := bones[vertex * influences + influence]
				if weight <= 0.0 or bind < 0 or bind >= binds.size():
					continue
				var transform: Transform3D = binds[bind]
				position += (transform * vertices[vertex]) * weight
				normal += (transform.basis * initial_normal) * weight
				tangent += (transform.basis * initial_tangent) * weight
				total += weight
			if total <= 0.00001:
				position = unskinned * vertices[vertex]
				normal = unskinned.basis * initial_normal
				tangent = unskinned.basis * initial_tangent
			else:
				position /= total
			vertices[vertex] = position
			if normals.size() == count:
				normals[vertex] = normal.normalized()
			if tangents.size() == count * 4:
				tangent = tangent.normalized()
				tangents[vertex * 4] = tangent.x
				tangents[vertex * 4 + 1] = tangent.y
				tangents[vertex * 4 + 2] = tangent.z
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals if not normals.is_empty() else null
		arrays[Mesh.ARRAY_TANGENT] = tangents if not tangents.is_empty() else null
		arrays[Mesh.ARRAY_BONES] = null
		arrays[Mesh.ARRAY_WEIGHTS] = null
		# Imported extra UV sets can occupy FLOAT custom channels. Their format
		# bits must survive the copy; omitting them makes Godot expect byte data.
		var custom_formats := 0
		if source.mesh is ArrayMesh:
			custom_formats = (source.mesh as ArrayMesh).surface_get_format(surface) & (4095 << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, custom_formats)
		result.surface_set_material(result.get_surface_count() - 1, source.get_active_material(surface))
	return result
