# SPDX-License-Identifier: 0BSD
extends RefCounted
# Startup-only construction. Native pages retain ownership of instance buffers.
# Near/low geometry and its opaque material are preserved. Far triangles become
# analytic coverage quads; no atlas, temporal history or per-instance CPU updates.
static func apply(mesh: ArrayMesh, authored: Array, original_lods: Dictionary, material: ShaderMaterial, far_error := 0.06, horizon_error := 0.10) -> ShaderMaterial:
	var shadow := ArrayMesh.new()
	shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,authored,[],original_lods)
	shadow.custom_aabb=mesh.custom_aabb
	mesh.clear_surfaces()
	var inactive := PackedInt32Array([0,0,0])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,authored,[],{0.02:original_lods[0.02],far_error:inactive,horizon_error:inactive})
	mesh.surface_set_material(0,material)
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var colors := PackedColorArray(); var uvs := PackedVector2Array()
	var custom := [PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array()]
	var lods := {}
	for pair in [[far_error,0.12],[horizon_error,0.2]]:
		var indices := PackedInt32Array(); var original: PackedInt32Array = original_lods[pair[1]]
		for offset in range(0,original.size(),3):
			var start := vertices.size()
			var points := [authored[Mesh.ARRAY_VERTEX][original[offset]],authored[Mesh.ARRAY_VERTEX][original[offset+1]],authored[Mesh.ARRAY_VERTEX][original[offset+2]]]
			for uv: Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				vertices.append((points[0]+points[1]+points[2])/3.0)
				normals.append(authored[Mesh.ARRAY_NORMAL][original[offset]])
				colors.append(authored[Mesh.ARRAY_COLOR][original[offset]])
				uvs.append(uv)
				for i in 3: custom[i].append_array(PackedFloat32Array([points[i].x,points[i].y,points[i].z,0]))
			indices.append_array(PackedInt32Array([start,start+2,start+1,start,start+3,start+2]))
		lods[pair[0]]=indices
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_TEX_UV]=uvs
	# LOD buffers must be shorter than the base buffer. Degenerate base triangles
	# emit no nearby fragments. The separate opaque surface retains normal depth.
	var empty_base := PackedInt32Array(); empty_base.resize(lods[far_error].size()+3)
	arrays[Mesh.ARRAY_INDEX]=empty_base
	arrays[Mesh.ARRAY_CUSTOM0]=custom[0]; arrays[Mesh.ARRAY_CUSTOM1]=custom[1]; arrays[Mesh.ARRAY_CUSTOM2]=custom[2]
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],lods,flags)
	var filtered := ShaderMaterial.new(); filtered.shader=preload("res://addons/world_ecosystem/filtered_grass.gdshader")
	mesh.surface_set_material(1,filtered)
	# Camera LOD and shadow-map LOD differ. Preserve the original nearby casters.
	# Godot requires a matching shadow surface for each main surface, including
	# transparent ones. The filtered coverage never creates another grass caster.
	var empty_shadow := []; empty_shadow.resize(Mesh.ARRAY_MAX)
	empty_shadow[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,empty_shadow)
	mesh.shadow_mesh=shadow
	return filtered
