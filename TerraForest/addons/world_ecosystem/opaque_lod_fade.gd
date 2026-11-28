# SPDX-License-Identifier: 0BSD
extends RefCounted
# Startup-only construction. Each original index cutoff still retires its costly
# representation. Only the adjacent tier is added, on the same opaque surface.
static var shaders:Dictionary={}

static func prepare(arrays:Array,lods:Dictionary,second:bool) -> void:
	var keys:=lods.keys();keys.sort()
	var tiers:=PackedVector2Array();tiers.resize(arrays[Mesh.ARRAY_VERTEX].size())
	var low:PackedInt32Array=lods[keys[0]]
	for index in low:tiers[index]=Vector2(1,0)
	var base:PackedInt32Array=arrays[Mesh.ARRAY_INDEX].duplicate();base.append_array(low)
	arrays[Mesh.ARRAY_INDEX]=base
	if second:
		var far:PackedInt32Array=lods[keys[1]]
		for index in far:tiers[index]=Vector2(2,0)
		# A page can still use its base buffer while distant roots are in tier 2.
		base.append_array(far);arrays[Mesh.ARRAY_INDEX]=base
		low=low.duplicate();low.append_array(far);lods[keys[0]]=low
	arrays[Mesh.ARRAY_TEX_UV2]=tiers

static func finish(mesh:ArrayMesh,authored:Array,lods:Dictionary,material:ShaderMaterial,second:bool) -> void:
	if not shaders.has(second):
		var shader:=Shader.new()
		shader.code=material.shader.code.replace("const bool cover_lod_transition = false;","const bool cover_lod_transition = true;")
		if second:shader.code=shader.code.replace("const bool cover_lod_far_transition = false;","const bool cover_lod_far_transition = true;")
		shaders[second]=shader
	material.shader=shaders[second]
	var keys:=lods.keys();keys.sort()
	var first:float=keys[0]
	var next:float=keys[1] if second else 10000.0
	material.set_shader_parameter("cover_lod_edges",Vector4(first-.00275,first-.0002,next-.0055,next-.0002))
	var shadow:=ArrayMesh.new();shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,authored,[],lods);shadow.custom_aabb=mesh.custom_aabb
	if mesh.has_meta("surface_lod_near"):mesh.get_meta("surface_lod_near").shadow_mesh=shadow
	if mesh.get_surface_count()==2:
		var combined:=ArrayMesh.new();combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,authored,[],lods);combined.custom_aabb=mesh.custom_aabb
		var empty:=[];empty.resize(Mesh.ARRAY_MAX);empty[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
		combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,empty);mesh.shadow_mesh=combined
	else:mesh.shadow_mesh=shadow
	mesh.set_meta("opaque_lod_fade",true)
