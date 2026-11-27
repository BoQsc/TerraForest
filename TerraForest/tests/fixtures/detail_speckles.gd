# SPDX-License-Identifier: 0BSD
extends RefCounted
# Lab-only controls. Each changes one far-distance mechanism; production remains
# untouched until measured coverage, tone, nearby parity and cost pass.
const Species := [0,3,4,5]
static var stone_lookup: ImageTexture
static var stone_lookup_error := 0.0
static var stone_lookup_build_us := 0

static func projected_area(direction: Vector3,areas: Array[Vector3]) -> float:
	var result := 0.0
	for area in areas:result+=absf(direction.dot(area))*0.5
	return result

static func area_lookup(areas: Array[Vector3]) -> ImageTexture:
	if stone_lookup:return stone_lookup
	var began := Time.get_ticks_usec()
	# Duplicate longitude endpoint and retain both poles: interpolation is bounded
	# and continuous at the wrap, without mipmaps or per-instance CPU work.
	var image := Image.create(129,65,false,Image.FORMAT_RF)
	for y in 65:
		var theta := float(y)*PI/64.0
		for x in 129:
			var phi := float(x)*TAU/128.0
			var value := projected_area(Vector3(cos(phi)*sin(theta),cos(theta),sin(phi)*sin(theta)),areas)
			image.set_pixel(x,y,Color(value,0,0))
	# Mid-cell validation, deliberately not the exact table nodes.
	for y in 64:
		var theta := (float(y)+0.5)*PI/64.0
		for x in 128:
			var phi := (float(x)+0.5)*TAU/128.0
			var exact := projected_area(Vector3(cos(phi)*sin(theta),cos(theta),sin(phi)*sin(theta)),areas)
			var sampled := (image.get_pixel(x,y).r+image.get_pixel(x+1,y).r+image.get_pixel(x,y+1).r+image.get_pixel(x+1,y+1).r)*0.25
			stone_lookup_error=maxf(stone_lookup_error,absf(sampled-exact)/exact)
	stone_lookup=ImageTexture.create_from_image(image);stone_lookup_build_us=Time.get_ticks_usec()-began
	return stone_lookup

static func capture(mesh: ArrayMesh,species: int) -> Dictionary:
	var asset := preload("res://addons/world_ecosystem/woodland_mesh.gd").new()
	var method: String={0:"stone_mesh",3:"white_flower",4:"gold_flower",5:"violet_flower"}[species]
	asset.call(method,false);var full_end: int=asset.vertices.size();asset.call(method,true)
	var arrays := mesh.surface_get_arrays(0);var base := PackedInt32Array();var indices := PackedInt32Array()
	for i in full_end:base.append(i)
	for i in range(full_end,asset.vertices.size()):indices.append(i)
	arrays[Mesh.ARRAY_VERTEX]=asset.vertices;arrays[Mesh.ARRAY_NORMAL]=asset.normals;arrays[Mesh.ARRAY_COLOR]=asset.colors
	arrays[Mesh.ARRAY_TEX_UV]=asset.uvs;arrays[Mesh.ARRAY_TANGENT]=asset.tangents;arrays[Mesh.ARRAY_INDEX]=base
	var lods := {0.03 if species==0 else 0.02:indices}
	var shadow := ArrayMesh.new();shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],lods);shadow.custom_aabb=mesh.custom_aabb
	return {"arrays":arrays,"lods":lods,"material":mesh.surface_get_material(0),"bounds":mesh.custom_aabb,"shadow":shadow}

static func restore(mesh: ArrayMesh,saved: Dictionary) -> void:
	mesh.clear_surfaces();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,saved.arrays,[],saved.lods)
	mesh.surface_set_material(0,saved.material);mesh.shadow_mesh=saved.shadow;mesh.custom_aabb=saved.bounds

static func split(mesh: ArrayMesh,saved: Dictionary,arrays: Array,indices: PackedInt32Array,flags: int,material: ShaderMaterial,far_error: float) -> ShaderMaterial:
	var opaque_lods: Dictionary=saved.lods.duplicate();opaque_lods[far_error]=PackedInt32Array([0,0,0])
	var near_only := ArrayMesh.new();near_only.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,saved.arrays,[],opaque_lods)
	near_only.surface_set_material(0,saved.material);near_only.custom_aabb=saved.bounds
	var shadow_lods: Dictionary=saved.lods.duplicate();shadow_lods[far_error]=saved.lods.values()[0]
	var near_shadow := ArrayMesh.new();near_shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,saved.arrays,[],shadow_lods)
	near_shadow.custom_aabb=saved.bounds;near_only.shadow_mesh=near_shadow
	mesh.clear_surfaces();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,saved.arrays,[],opaque_lods)
	mesh.surface_set_material(0,saved.material)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{far_error:indices},flags);mesh.surface_set_material(1,material)
	var far_only := ArrayMesh.new();far_only.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{far_error:indices},flags)
	far_only.surface_set_material(0,material);far_only.custom_aabb=saved.bounds
	mesh.set_meta("surface_lod_near",near_only);mesh.set_meta("surface_lod_far",far_only);mesh.set_meta("surface_lod_error",far_error)
	var shadow := ArrayMesh.new();shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,saved.arrays,[],shadow_lods);shadow.custom_aabb=saved.bounds
	var empty := [];empty.resize(Mesh.ARRAY_MAX);empty[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,empty);mesh.shadow_mesh=shadow
	for parameter in ["stone_color","stone_normal","distance_fade_start","distance_fade_end","cover_eye","cover_clock","wind_strength","distant_self_shade"]:
		var value: Variant=saved.material.get_shader_parameter(parameter)
		if value!=null:material.set_shader_parameter(parameter,value)
	return material

static func install_stone(mesh: ArrayMesh,saved: Dictionary,use_lookup := false,early_exit := false) -> ShaderMaterial:
	var areas: Array[Vector3]=[];var low: PackedInt32Array=saved.lods.values()[0]
	for i in range(0,low.size(),3):
		var a: Vector3=saved.arrays[Mesh.ARRAY_VERTEX][low[i]];var b: Vector3=saved.arrays[Mesh.ARRAY_VERTEX][low[i+1]];var c: Vector3=saved.arrays[Mesh.ARRAY_VERTEX][low[i+2]]
		areas.append((b-a).cross(c-a)*0.5)
	assert(areas.size()==48,"stone area uniforms match authored low mesh")
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,0,0,0,0,0,0,0,0])
	var material := ShaderMaterial.new();material.shader=preload("res://tests/fixtures/stone_filtered.gdshader")
	if use_lookup:
		var shader := Shader.new()
		shader.code=material.shader.code.replace("uniform vec3 stone_area_vectors[48];","uniform sampler2D stone_area_lookup : filter_linear, repeat_disable;")
		shader.code=shader.code.replace("float area=0.0;\n    for(int i=0;i<48;i++){area+=abs(dot(projected_normal,stone_area_vectors[i]))*0.5;}","vec3 direction=normalize(projected_normal);\n    vec2 lookup=vec2(fract(atan(direction.z,direction.x)/6.28318530718),acos(clamp(direction.y,-1.0,1.0))/3.14159265359);\n    lookup=(lookup*vec2(128.0,64.0)+vec2(0.5))/vec2(129.0,65.0);\n    float area=textureLod(stone_area_lookup,lookup,0.0).r*length(projected_normal);")
		material.shader=shader;material.set_shader_parameter("stone_area_lookup",area_lookup(areas))
	else:material.set_shader_parameter("stone_area_vectors",areas)
	if early_exit:
		var shader := Shader.new();var code := material.shader.code
		var start := code.find("    vec3 origin=MODEL_MATRIX[3].xyz;")
		var end := code.find("    variation=",start)
		var visibility := code.substr(start,end-start)
		code=code.substr(0,start)+code.substr(end)
		code=code.replace("void vertex(){", "void vertex(){\n"+visibility+"if(coverage<=0.0){POSITION=vec4(2.0,2.0,2.0,1.0);}else{")
		code=code.replace("void fragment(){","}\nvoid fragment(){")
		shader.code=code;material.shader=shader
	return split(mesh,saved,arrays,PackedInt32Array([0,2,1,0,3,2]),0,material,0.045)

static func flower_proxies(saved: Dictionary) -> Dictionary:
	var original: PackedInt32Array=saved.lods.values()[0]
	var per_head := original.size()/6
	assert(per_head in [27,33],"Flower grouping matches two authored low crowns")
	var proxies := [];var normal_areas: Array[Vector3]=[]
	for frond in 4:
		var begin: int=(frond/2)*per_head+(12 if frond%2 else 0)
		var count: int=(per_head-12) if frond%2 else 12
		var triangles := [];var area_sum := 0.0;var center := Vector3.ZERO
		var tint := Color(0,0,0,0);var normal := Vector3.ZERO;var mean_uv := Vector2.ZERO
		var bins: Array[Vector3]=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
		var reference_normals: Array[Vector3]=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
		for triangle in count:
			var points: Array[Vector3]=[];var uv := Vector2.ZERO
			var first: int=(begin+triangle)*3
			for corner in 3:
				points.append(saved.arrays[Mesh.ARRAY_VERTEX][original[first+corner]])
				uv+=saved.arrays[Mesh.ARRAY_TEX_UV][original[first+corner]]/3.0
			var area: float=(points[1]-points[0]).cross(points[2]-points[0]).length()*0.5
			if area<0.000000001:continue
			var centroid: Vector3=(points[0]+points[1]+points[2])/3.0
			var n: Vector3=saved.arrays[Mesh.ARRAY_NORMAL][original[first]]
			var group := 0 if absf(n.y)>0.98 else ((1 if n.x>=0 else 2) if absf(n.x)>=absf(n.z) else (3 if n.z>=0 else 4))
			if reference_normals[group]==Vector3.ZERO:reference_normals[group]=n
			bins[group]+=n*area*(-1.0 if n.dot(reference_normals[group])<0 else 1.0)
			normal+=n*area*(-1.0 if n.y<0 else 1.0)
			center+=centroid*area;tint+=saved.arrays[Mesh.ARRAY_COLOR][original[first]]*area;mean_uv+=uv*area;area_sum+=area
			triangles.append({"points":points,"center":centroid,"area":area})
		center/=area_sum;tint/=area_sum;mean_uv/=area_sum
		var covariance: Array[Vector3]=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
		for triangle: Dictionary in triangles:
			var offset: Vector3=triangle.center-center
			for axis in 3:
				var moment := offset*offset[axis]
				for point: Vector3 in triangle.points:
					var d: Vector3=point-triangle.center;moment+=d*d[axis]/12.0
				covariance[axis]+=moment*(triangle.area/area_sum)
		var first_axis := Vector3.RIGHT if covariance[0].x>=maxf(covariance[1].y,covariance[2].z) else (Vector3.UP if covariance[1].y>=covariance[2].z else Vector3.FORWARD)
		for iteration in 20:first_axis=preload("res://addons/world_ecosystem/filtered_fern.gd").covariance_product(covariance,first_axis).normalized()
		var second_axis := Vector3.RIGHT if absf(first_axis.x)<0.8 else Vector3.FORWARD
		second_axis=(second_axis-first_axis*second_axis.dot(first_axis)).normalized()
		for iteration in 20:
			var next := preload("res://addons/world_ecosystem/filtered_fern.gd").covariance_product(covariance,second_axis)
			second_axis=(next-first_axis*next.dot(first_axis)).normalized()
		var eigen_a := maxf(first_axis.dot(preload("res://addons/world_ecosystem/filtered_fern.gd").covariance_product(covariance,first_axis)),0.00000001)
		var eigen_b := maxf(second_axis.dot(preload("res://addons/world_ecosystem/filtered_fern.gd").covariance_product(covariance,second_axis)),0.00000001)
		var a := first_axis*sqrt(8.0*eigen_a);var b := first_axis*sqrt(2.0*eigen_a);var c := second_axis*sqrt(6.0*eigen_b)
		proxies.append({"points":[center+a,center-b+c,center-b-c],"normal":normal.normalized(),"color":tint,"uv":mean_uv,"custom_w":[float(frond*5),0.0,0.0]})
		normal_areas.append_array(bins)
	normal_areas.resize(35)
	return {"proxies":proxies,"normal_areas":normal_areas}

static func install_flower(mesh: ArrayMesh,saved: Dictionary,clustered := false) -> ShaderMaterial:
	# Keep the authored petal colors, normals and area. Sparse flowers can first
	# test individual triangles; accept only if paired total GPU cost also passes.
	var low: PackedInt32Array=saved.lods.values()[0]
	var vertices := PackedVector3Array();var normals := PackedVector3Array();var colors := PackedColorArray()
	var uvs := PackedVector2Array();var source_uvs := PackedVector2Array();var indices := PackedInt32Array()
	var custom := [PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array()]
	var records := [];var groups := {}
	if clustered:groups=flower_proxies(saved);records=groups.proxies
	else:
		for first in range(0,low.size(),3):
			var points: Array[Vector3]=[];var coords: Array[Vector2]=[]
			for i in 3:
				points.append(saved.arrays[Mesh.ARRAY_VERTEX][low[first+i]]);coords.append(saved.arrays[Mesh.ARRAY_TEX_UV][low[first+i]])
			records.append({"points":points,"normal":saved.arrays[Mesh.ARRAY_NORMAL][low[first]],"color":saved.arrays[Mesh.ARRAY_COLOR][low[first]],"uv":(coords[0]+coords[1]+coords[2])/3.0,"custom_w":[coords[0].x,coords[1].x,coords[2].x]})
	for record: Dictionary in records:
		var points: Array=record.points;var start := vertices.size()
		for corner: Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
			vertices.append((points[0]+points[1]+points[2])/3.0);normals.append(record.normal)
			colors.append(record.color);uvs.append(corner);source_uvs.append(record.uv)
			for i in 3:custom[i].append_array(PackedFloat32Array([points[i].x,points[i].y,points[i].z,record.custom_w[i]]))
		indices.append_array(PackedInt32Array([start,start+2,start+1,start,start+3,start+2]))
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_TEX_UV2]=source_uvs
	var base := PackedInt32Array();base.resize(indices.size()+3);arrays[Mesh.ARRAY_INDEX]=base
	for i in 3:arrays[Mesh.ARRAY_CUSTOM0+i]=custom[i]
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	var material := ShaderMaterial.new();var shader := Shader.new()
	shader.code=preload("res://tests/fixtures/fern_filtered.gd").shader_code(saved.material.shader.code,clustered);material.shader=shader
	if clustered:material.set_shader_parameter("filter_area_vectors",groups.normal_areas)
	return split(mesh,saved,arrays,indices,flags,material,0.04)

static func mean_color(material: ShaderMaterial) -> Vector3:
	var texture: Texture2D=material.get_shader_parameter("stone_color")
	var image := texture.get_image();var sum := Vector3.ZERO;var count := 0
	for y in range(0,image.get_height(),8):
		for x in range(0,image.get_width(),8):
			var color := image.get_pixel(x,y).srgb_to_linear();sum+=Vector3(color.r,color.g,color.b);count+=1
	return sum/float(count)

static func control_code(original: String,probe: String) -> String:
	var code := original.replace("void vertex() {","varying flat float lab_detail_distance;\nvoid vertex() {\nlab_detail_distance=distance(MODEL_MATRIX[3].xyz,cover_eye);")
	var far := "lab_detail_distance>=55.0"
	var tail := ""
	if probe.ends_with("no_specular"):tail="if("+far+")SPECULAR=0.0;"
	if probe.ends_with("no_normal"):tail="if("+far+")NORMAL_MAP_DEPTH=0.0;"
	if probe.ends_with("flat_color"):
		if probe.begins_with("stone"):
			code=code.replace("shader_type spatial;","shader_type spatial;\nuniform vec3 lab_stone_mean;")
			code=code.replace("vec4 rock = texture(stone_color, UV);","vec4 rock = texture(stone_color, UV); if("+far+")rock.rgb=lab_stone_mean;")
		else:tail="if("+far+")ALBEDO=COLOR.rgb*variation*root_shade*canopy_shade;"
	if probe.ends_with("no_wind"):code=code.replace("* wind_strength","* ("+far+"?0.0:wind_strength)")
	if probe.ends_with("no_fade"):code=code.replace("if(coverage<=threshold)discard;","if(!("+far+") && coverage<=threshold)discard;")
	if probe.ends_with("bounded_edge"):code=code.replace("float edge = abs(UV.x - 0.5) * 2.0;","float edge = abs(UV.x - 0.5) * 2.0; if("+far+")edge=min(edge,1.0);")
	if probe.ends_with("bounded_canopy"):code=code.replace("ALBEDO *= canopy_shade;","ALBEDO *= "+far+"?clamp(canopy_shade,1.0-distant_self_shade,1.0):canopy_shade;")
	if probe.ends_with("no_ribs"):code=code.replace("float ribs = 0.96 + 0.04 * sin((UV.y - abs(UV.x - 0.5) * 0.35) * 95.0);","float ribs = 0.96 + 0.04 * sin((UV.y - abs(UV.x - 0.5) * 0.35) * 95.0); if("+far+")ribs=0.96;")
	if probe.ends_with("removed"):tail="if("+far+" && lab_detail_distance<=120.0)discard;"
	if probe.ends_with("unlit"):tail="if("+far+"){EMISSION=ALBEDO;ALBEDO=vec3(0.0);SPECULAR=0.0;BACKLIGHT=vec3(0.0);}"
	var ending := code.rfind("}")
	return code.substr(0,ending)+tail+"\n}"
