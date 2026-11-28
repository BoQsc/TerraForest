# SPDX-License-Identifier: 0BSD
extends RefCounted
const FAR_ERROR := 0.045
static var near_transition_shader:Shader
# Startup-only construction. Native pages retain ownership of instance buffers.
# Near/low geometry and its opaque material are preserved. Far triangles become
# analytic coverage quads; no atlas, temporal history or per-instance CPU updates.
static func apply(mesh: ArrayMesh, authored: Array, original_lods: Dictionary, material: ShaderMaterial, far_error := FAR_ERROR, horizon_error := 0.10, near_fade := false) -> ShaderMaterial:
	# Empty custom_aabb means automatic bounds. Freeze the original automatic box
	# before splitting surfaces so every variant has exactly the same LOD distance.
	mesh.custom_aabb=mesh.get_aabb()
	var inactive := PackedInt32Array([0,0,0])
	var shadow_authored:=authored
	var opaque_lods := {0.02:original_lods[0.02],far_error:inactive,horizon_error:inactive}
	if near_fade:
		# Startup only. The native owner still submits one opaque surface. Low
		# geometry replaces the pair only after every plant has finished fading.
		authored=authored.duplicate(true)
		var tiers:=PackedVector2Array();tiers.resize(authored[Mesh.ARRAY_VERTEX].size())
		for index in original_lods[0.02]:tiers[index]=Vector2(1,0)
		authored[Mesh.ARRAY_TEX_UV2]=tiers
		var combined:PackedInt32Array=authored[Mesh.ARRAY_INDEX].duplicate()
		combined.append_array(original_lods[0.02]);authored[Mesh.ARRAY_INDEX]=combined
		opaque_lods={0.02:original_lods[0.02],far_error:inactive,horizon_error:inactive}
		# Compile away the feature for every other species and ordinary asset.
		# A single cached grass variant keeps all shared lighting expressions.
		if near_transition_shader==null:
			near_transition_shader=Shader.new()
			near_transition_shader.code=material.shader.code.replace("const bool near_lod_transition = false;","const bool near_lod_transition = true;")
		material.shader=near_transition_shader
		mesh.set_meta("near_lod_transition",true)
	var shadow := ArrayMesh.new()
	shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,shadow_authored,[],original_lods)
	shadow.custom_aabb=mesh.custom_aabb
	var near_only := ArrayMesh.new()
	# The shadow pass selects a LOD index through the main surface too. Retain its
	# thresholds even where the color surface is inactive, or zoom changes casters.
	near_only.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,authored,[],opaque_lods)
	near_only.surface_set_material(0,material)
	near_only.custom_aabb=mesh.custom_aabb
	var near_shadow := ArrayMesh.new()
	near_shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,shadow_authored,[],original_lods)
	near_shadow.custom_aabb=mesh.custom_aabb
	near_only.shadow_mesh=near_shadow
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,authored,[],opaque_lods)
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
	var far_only := ArrayMesh.new()
	far_only.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],lods,flags)
	far_only.surface_set_material(0,filtered)
	far_only.custom_aabb=mesh.custom_aabb
	mesh.set_meta("surface_lod_near",near_only)
	mesh.set_meta("surface_lod_far",far_only)
	mesh.set_meta("surface_lod_error",far_error)
	# Camera LOD and shadow-map LOD differ. Preserve the original nearby casters.
	# Godot requires a matching shadow surface for each main surface, including
	# transparent ones. The filtered coverage never creates another grass caster.
	var empty_shadow := []; empty_shadow.resize(Mesh.ARRAY_MAX)
	empty_shadow[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,empty_shadow)
	mesh.shadow_mesh=shadow
	return filtered

static func configure_batch(batch: Node, mesh: ArrayMesh, enabled := true) -> bool:
	if enabled and mesh.get_surface_count()==2 and mesh.has_meta("surface_lod_near"):
		return batch.configure_surface_lod(mesh.get_meta("surface_lod_near"),mesh.get_meta("surface_lod_far"),mesh.get_meta("surface_lod_error"))
	return batch.configure_surface_lod(null,null,0.0)
