# SPDX-License-Identifier: 0BSD
extends RefCounted
# Original diagnostic mesh transformation. Source near/low arrays stay exact.
static func extract_stage(code: String, name: String) -> Array[String]:
	var start := code.find("void "+name+"()")
	var opening := code.find("{",start)
	var cursor := opening+1; var depth := 1
	while depth > 0:
		if code[cursor] == "{": depth += 1
		elif code[cursor] == "}": depth -= 1
		cursor += 1
	return [code.substr(0,start)+code.substr(cursor),code.substr(opening+1,cursor-opening-2)]

static func capture(mesh: ArrayMesh) -> Dictionary:
	var asset := preload("res://addons/world_ecosystem/woodland_mesh.gd").new()
	asset.grass(false); var near_end: int = asset.vertices.size()
	asset.grass(true); var low_end: int = asset.vertices.size()
	asset.grass_far(); var far_end: int = asset.vertices.size()
	asset.grass_horizon(); var end: int = asset.vertices.size()
	var lods := {}
	for row in [[0.02,near_end,low_end],[0.12,low_end,far_end],[0.2,far_end,end]]:
		var indices := PackedInt32Array()
		for index in range(row[1],row[2]): indices.append(index)
		lods[row[0]] = indices
	# Reuse original authoring arrays, avoiding decode/re-encode rounding of the
	# packed normals returned by surface_get_arrays(). This matters to near parity.
	var arrays := mesh.surface_get_arrays(0)
	arrays[Mesh.ARRAY_VERTEX]=asset.vertices; arrays[Mesh.ARRAY_NORMAL]=asset.normals
	arrays[Mesh.ARRAY_COLOR]=asset.colors; arrays[Mesh.ARRAY_TEX_UV]=asset.uvs
	arrays[Mesh.ARRAY_TANGENT]=asset.tangents
	var shadow := ArrayMesh.new()
	shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],lods)
	shadow.custom_aabb=mesh.custom_aabb
	return {"arrays":arrays,"material":mesh.surface_get_material(0),"lods":lods,"original_shadow":mesh.shadow_mesh,"shadow":shadow}

static func restore(mesh: ArrayMesh, saved: Dictionary) -> void:
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,saved.arrays,[],saved.lods)
	mesh.surface_set_material(0,saved.material)
	mesh.shadow_mesh=saved.original_shadow

static func install(mesh: ArrayMesh, saved: Dictionary, early := false, single := false) -> ShaderMaterial:
	if not single:
		var material := preload("res://addons/world_ecosystem/filtered_grass.gd").apply(mesh,saved.arrays,saved.lods,saved.material,preload("res://addons/world_ecosystem/filtered_grass.gd").FAR_ERROR if early else 0.12,0.10 if early else 0.20)
		var shader := Shader.new();shader.code=material.shader.code.replace("shader_type spatial;","shader_type spatial;\nuniform float comparison_time=0.0;").replace("TIME","comparison_time")
		material.shader=shader
		return material
	mesh.clear_surfaces()
	var inactive := PackedInt32Array([0,0,0])
	var far_error := 0.06 if early else 0.12
	var horizon_error := 0.10 if early else 0.20
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,saved.arrays,[],{0.02:saved.lods[0.02],far_error:inactive,horizon_error:inactive})
	mesh.surface_set_material(0,saved.material)
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var colors := PackedColorArray(); var uvs := PackedVector2Array()
	var custom := [PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array()]
	var lods := {}
	for key: float in [0.12,0.2]:
		var indices := PackedInt32Array(); var original: PackedInt32Array = saved.lods[key]
		for offset in range(0,original.size(),3):
			var start := vertices.size()
			var points := [saved.arrays[Mesh.ARRAY_VERTEX][original[offset]],saved.arrays[Mesh.ARRAY_VERTEX][original[offset+1]],saved.arrays[Mesh.ARRAY_VERTEX][original[offset+2]]]
			for uv: Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
				vertices.append((points[0]+points[1]+points[2])/3.0)
				normals.append(saved.arrays[Mesh.ARRAY_NORMAL][original[offset]])
				colors.append(saved.arrays[Mesh.ARRAY_COLOR][original[offset]])
				uvs.append(uv)
				for i in 3: custom[i].append_array(PackedFloat32Array([points[i].x,points[i].y,points[i].z,0]))
			indices.append_array(PackedInt32Array([start,start+2,start+1,start,start+3,start+2]))
		lods[key]=indices
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals
	# Godot requires every LOD index buffer to be shorter than the base buffer.
	# Degenerate base indices emit no near fragments but retain valid LOD lengths.
	var empty_base := PackedInt32Array(); empty_base.resize(lods[0.12].size()+3)
	arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_INDEX]=empty_base
	arrays[Mesh.ARRAY_CUSTOM0]=custom[0]; arrays[Mesh.ARRAY_CUSTOM1]=custom[1]; arrays[Mesh.ARRAY_CUSTOM2]=custom[2]
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	if single:
		mesh.clear_surfaces()
		var combined: Array = saved.arrays.duplicate(true)
		var base_count: int = combined[Mesh.ARRAY_VERTEX].size()
		for pair in [[Mesh.ARRAY_VERTEX,vertices],[Mesh.ARRAY_NORMAL,normals],[Mesh.ARRAY_COLOR,colors],[Mesh.ARRAY_TEX_UV,uvs]]:
			combined[pair[0]].append_array(pair[1])
		for vertex in vertices.size(): combined[Mesh.ARRAY_TANGENT].append_array(PackedFloat32Array([1,0,0,1]))
		for channel in 3:
			var attributes := PackedFloat32Array(); attributes.resize(base_count*4)
			for vertex in vertices.size(): custom[channel][vertex*4+3]=1.0
			attributes.append_array(custom[channel]); combined[Mesh.ARRAY_CUSTOM0+channel]=attributes
		var combined_lods := {0.02:saved.lods[0.02]}
		for pair in [[far_error,0.12],[horizon_error,0.2]]:
			var indices := PackedInt32Array()
			for index: int in lods[pair[1]]: indices.append(base_count+index)
			combined_lods[pair[0]]=indices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,combined,[],combined_lods,flags)
		var source: String = saved.material.shader.code
		source=source.replace("diffuse_burley;","diffuse_burley, depth_prepass_alpha;")
		var authored_vertex := extract_stage(source,"vertex")
		var authored_fragment := extract_stage(authored_vertex[0],"fragment")
		var gaussian: String = preload("res://tests/fixtures/grass_filtered.gdshader").code
		gaussian=gaussian.replace("shader_type spatial;","").replace("render_mode cull_disabled, diffuse_burley;","").replace("uniform vec3 cover_eye;","").replace("uniform float comparison_time = 0.0;","")
		gaussian=gaussian.replace("variation","filtered_variation").replace("root_shade","filtered_root_shade")
		var filtered_vertex := extract_stage(gaussian,"vertex")
		var filtered_fragment := extract_stage(filtered_vertex[0],"fragment")
		var shader := Shader.new()
		shader.code=authored_fragment[0]+"\n"+filtered_fragment[0]+"\nvarying flat float is_filtered;\nvoid vertex(){is_filtered=CUSTOM0.w;if(is_filtered>0.5){"+filtered_vertex[1]+"}else{"+authored_vertex[1]+"POSITION=PROJECTION_MATRIX*(MODELVIEW_MATRIX*vec4(VERTEX,1.0));}}\nvoid fragment(){if(is_filtered>0.5){"+filtered_fragment[1]+"}else{"+authored_fragment[1]+"ALPHA=1.0;}}\n"
		var material: ShaderMaterial = saved.material.duplicate()
		material.shader=shader;mesh.surface_set_material(0,material);mesh.shadow_mesh=saved.shadow
		return material
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{far_error:lods[0.12],horizon_error:lods[0.2]},flags)
	var material := ShaderMaterial.new(); material.shader=preload("res://tests/fixtures/grass_filtered.gdshader")
	mesh.surface_set_material(1,material)
	# Shadow-map projection can select a coarse LOD even for nearby camera grass.
	# Keep its original caster geometry instead of inheriting the empty far indices.
	mesh.shadow_mesh=saved.shadow
	return material
