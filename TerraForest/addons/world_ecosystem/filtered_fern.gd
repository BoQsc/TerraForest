# SPDX-License-Identifier: 0BSD
extends RefCounted
# Startup-only far-fern representation. Shared seven-frond geometry and area
# vectors; no texture atlas, temporal history or per-instance CPU updates.
# The near/low geometry, authored colors and existing woodland lighting remain.
const FAR_ERROR := 0.04

static func covariance_product(columns: Array[Vector3],v: Vector3) -> Vector3:
	return columns[0]*v.x+columns[1]*v.y+columns[2]*v.z

static func frond_proxies(saved: Dictionary) -> Dictionary:
	var original: PackedInt32Array=saved.lods[0.08]
	assert(original.size()==7*22*3,"Frond grouping must match the inspected original authoring layout")
	var proxies := [];var normal_areas: Array[Vector3]=[]
	for frond in 7:
		var triangles := [];var area_sum := 0.0;var center := Vector3.ZERO
		var tint := Color(0,0,0,0);var normal := Vector3.ZERO;var mean_uv := Vector2.ZERO
		var bins: Array[Vector3]=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
		var reference_normals: Array[Vector3]=[Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
		for triangle in 22:
			var points: Array[Vector3]=[];var uv := Vector2.ZERO
			var first: int=(frond*22+triangle)*3
			for corner in 3:
				points.append(saved.arrays[Mesh.ARRAY_VERTEX][original[first+corner]])
				uv+=saved.arrays[Mesh.ARRAY_TEX_UV][original[first+corner]]/3.0
			var area: float=(points[1]-points[0]).cross(points[2]-points[0]).length()*0.5
			if area<0.000000001:continue
			var centroid: Vector3=(points[0]+points[1]+points[2])/3.0
			var n: Vector3=saved.arrays[Mesh.ARRAY_NORMAL][original[first]]
			var group := 0 if triangle<6 else 1+(triangle-6)%4
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
		var first_axis := Vector3.UP
		for iteration in 20:first_axis=covariance_product(covariance,first_axis).normalized()
		var second_axis := Vector3.RIGHT if absf(first_axis.x)<0.8 else Vector3.FORWARD
		second_axis=(second_axis-first_axis*second_axis.dot(first_axis)).normalized()
		for iteration in 20:
			var next := covariance_product(covariance,second_axis)
			second_axis=(next-first_axis*next.dot(first_axis)).normalized()
		var eigen_a := maxf(first_axis.dot(covariance_product(covariance,first_axis)),0.00000001)
		var eigen_b := maxf(second_axis.dot(covariance_product(covariance,second_axis)),0.00000001)
		var a := first_axis*sqrt(8.0*eigen_a);var b := first_axis*sqrt(2.0*eigen_a);var c := second_axis*sqrt(6.0*eigen_b)
		proxies.append({"points":[center+a,center-b+c,center-b-c],"normal":normal.normalized(),"color":tint,"uv":mean_uv,"custom_w":[float(frond*5),0.0,0.0]})
		normal_areas.append_array(bins)
	return {"proxies":proxies,"normal_areas":normal_areas}

static func apply(mesh: ArrayMesh,authored: Array,lods: Dictionary,source_material: ShaderMaterial,far_error := FAR_ERROR) -> ShaderMaterial:
	var saved := {"arrays":authored,"lods":lods,"material":source_material,"bounds":mesh.custom_aabb}
	var inactive := PackedInt32Array([0,0,0])
	var opaque_lods := {0.025:saved.lods[0.025],far_error:inactive}
	var near_only := ArrayMesh.new()
	near_only.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,saved.arrays,[],saved.lods)
	near_only.surface_set_material(0,saved.material);near_only.custom_aabb=saved.bounds
	mesh.clear_surfaces();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,saved.arrays,[],opaque_lods)
	mesh.surface_set_material(0,saved.material)
	var vertices := PackedVector3Array();var normals := PackedVector3Array();var colors := PackedColorArray()
	var uvs := PackedVector2Array();var source_uvs := PackedVector2Array()
	var custom := [PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array()]
	var indices := PackedInt32Array()
	var groups := frond_proxies(saved);var records: Array=groups.proxies
	for record: Dictionary in records:
		var start := vertices.size();var points: Array=record.points
		for uv: Vector2 in [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]:
			vertices.append((points[0]+points[1]+points[2])/3.0)
			normals.append(record.normal);colors.append(record.color)
			uvs.append(uv);source_uvs.append(record.uv)
			for i in 3:custom[i].append_array(PackedFloat32Array([points[i].x,points[i].y,points[i].z,record.custom_w[i]]))
		indices.append_array(PackedInt32Array([start,start+2,start+1,start,start+3,start+2]))
	var arrays := [];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_TEX_UV]=uvs;arrays[Mesh.ARRAY_TEX_UV2]=source_uvs
	var empty_base := PackedInt32Array();empty_base.resize(indices.size()+3);arrays[Mesh.ARRAY_INDEX]=empty_base
	arrays[Mesh.ARRAY_CUSTOM0]=custom[0];arrays[Mesh.ARRAY_CUSTOM1]=custom[1];arrays[Mesh.ARRAY_CUSTOM2]=custom[2]
	var flags := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{far_error:indices},flags)
	var material := ShaderMaterial.new()
	material.shader=preload("res://addons/world_ecosystem/filtered_fern.gdshader")
	material.set_shader_parameter("filter_area_vectors",groups.normal_areas)
	for parameter in ["distance_fade_start","distance_fade_end","wind_strength","distant_self_shade","cover_eye","cover_clock"]:material.set_shader_parameter(parameter,saved.material.get_shader_parameter(parameter))
	mesh.surface_set_material(1,material)
	var far_only := ArrayMesh.new();far_only.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{far_error:indices},flags)
	far_only.surface_set_material(0,material);far_only.custom_aabb=saved.bounds
	mesh.set_meta("surface_lod_near",near_only);mesh.set_meta("surface_lod_far",far_only);mesh.set_meta("surface_lod_error",far_error)
	var shadow := ArrayMesh.new();shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,saved.arrays,[],saved.lods);shadow.custom_aabb=saved.bounds
	var empty_shadow := [];empty_shadow.resize(Mesh.ARRAY_MAX);empty_shadow[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,empty_shadow);mesh.shadow_mesh=shadow
	return material
