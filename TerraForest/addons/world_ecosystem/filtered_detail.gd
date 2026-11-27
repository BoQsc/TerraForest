# SPDX-License-Identifier: 0BSD
extends RefCounted
# Shared startup-only far details. Authored near geometry, shadows and materials
# stay intact; no new textures, per-instance CPU updates or temporal buffers.
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

static func install_stone(mesh: ArrayMesh,saved: Dictionary) -> ShaderMaterial:
	var areas: Array[Vector3]=[];var low: PackedInt32Array=saved.lods.values()[0]
	for i in range(0,low.size(),3):
		var a: Vector3=saved.arrays[Mesh.ARRAY_VERTEX][low[i]];var b: Vector3=saved.arrays[Mesh.ARRAY_VERTEX][low[i+1]];var c: Vector3=saved.arrays[Mesh.ARRAY_VERTEX][low[i+2]]
		areas.append((b-a).cross(c-a)*0.5)
	assert(areas.size()==48,"stone area uniforms match authored low mesh")
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,0,0,0,0,0,0,0,0])
	var material := ShaderMaterial.new();material.shader=preload("res://addons/world_ecosystem/filtered_stone.gdshader")
	material.set_shader_parameter("stone_area_vectors",areas)
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

static func install_flower(mesh: ArrayMesh,saved: Dictionary) -> ShaderMaterial:
	var vertices := PackedVector3Array();var normals := PackedVector3Array();var colors := PackedColorArray()
	var uvs := PackedVector2Array();var source_uvs := PackedVector2Array();var indices := PackedInt32Array()
	var custom := [PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array()]
	var groups := flower_proxies(saved);var records: Array=groups.proxies
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
	var material := ShaderMaterial.new();material.shader=preload("res://addons/world_ecosystem/filtered_fern.gdshader")
	material.set_shader_parameter("filter_area_vectors",groups.normal_areas)
	return split(mesh,saved,arrays,indices,flags,material,0.04)

static func apply(mesh: ArrayMesh,authored: Array,lods: Dictionary,source_material: ShaderMaterial,species: int) -> ShaderMaterial:
	var saved := {"arrays":authored,"lods":lods,"material":source_material,"bounds":mesh.custom_aabb}
	return install_stone(mesh,saved) if species==0 else install_flower(mesh,saved)
