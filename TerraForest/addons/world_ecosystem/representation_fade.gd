# SPDX-License-Identifier: 0BSD
extends RefCounted
# Startup configuration only. Native pages retain their instance buffers and
# retire the outgoing surface after its per-root transition has finished.
static var shaders:Dictionary={}

static func variant(source:Shader,features:Array[String]) -> Shader:
	var code:=source.code
	for feature in features:code=code.replace("const bool "+feature+" = false;","const bool "+feature+" = true;")
	if not shaders.has(code):
		var result:=Shader.new();result.code=code;shaders[code]=result
	return shaders[code]

static func apply(mesh:ArrayMesh,species:int) -> void:
	var opaque:ShaderMaterial=mesh.surface_get_material(0)
	var features:Array[String]=["shadow_distance_transition"]
	var has_proxy:=mesh.has_meta("surface_lod_error")
	if has_proxy:features.append("proxy_lod_transition")
	opaque.shader=variant(opaque.shader,features)
	opaque.set_shader_parameter("shadow_fade_edges",Vector2(16,24) if species==2 else Vector2(36,48))
	if has_proxy:
		var end:float=mesh.get_meta("surface_lod_error")
		var begin:=end-.008
		var edges:=Vector2(begin,end-.0002)
		# Near-only is safe only while the farthest point of the page is inside
		# begin. Far-only still uses the original closest-point end threshold.
		mesh.set_meta("surface_lod_begin",begin)
		opaque.set_shader_parameter("proxy_lod_edges",edges)
		var filtered:ShaderMaterial=mesh.surface_get_material(1)
		var filtered_features:Array[String]=["proxy_lod_transition"]
		if species==2:filtered_features.append("horizon_lod_transition")
		filtered.shader=variant(filtered.shader,filtered_features)
		filtered.set_shader_parameter("proxy_lod_edges",edges)
	mesh.set_meta("representation_fade",true)
