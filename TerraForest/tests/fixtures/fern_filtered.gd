# SPDX-License-Identifier: 0BSD
extends RefCounted
# Lab-only extension of the existing triangle coverage kernel. No production
# renderer imports this file. Keep fern normals, colors and woodland lighting.
const Stages=preload("res://tests/fixtures/grass_filtered.gd")

static func capture(mesh: ArrayMesh) -> Dictionary:
	var asset=preload("res://addons/world_ecosystem/woodland_mesh.gd").new()
	asset.fern(false);var full_end: int=asset.vertices.size()
	asset.fern(true);var low_end: int=asset.vertices.size()
	asset.fern(true,true);var far_end: int=asset.vertices.size()
	var lods := {};var base := PackedInt32Array()
	for i in full_end:base.append(i)
	for row in [[0.025,full_end,low_end],[0.08,low_end,far_end]]:
		var indices := PackedInt32Array()
		for i in range(row[1],row[2]):indices.append(i)
		lods[row[0]]=indices
	var arrays := mesh.surface_get_arrays(0)
	arrays[Mesh.ARRAY_INDEX]=base;arrays[Mesh.ARRAY_VERTEX]=asset.vertices
	arrays[Mesh.ARRAY_NORMAL]=asset.normals;arrays[Mesh.ARRAY_COLOR]=asset.colors
	arrays[Mesh.ARRAY_TEX_UV]=asset.uvs;arrays[Mesh.ARRAY_TANGENT]=asset.tangents
	var shadow := ArrayMesh.new();shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],lods);shadow.custom_aabb=mesh.custom_aabb
	return {"arrays":arrays,"lods":lods,"material":mesh.surface_get_material(0),"original_shadow":shadow,"bounds":mesh.custom_aabb}

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

static func shader_code(authored: String,cluster := false,variant := "original") -> String:
	var kernel := FileAccess.get_file_as_string("res://addons/world_ecosystem/filtered_grass.gdshader")
	var vertex := Stages.extract_stage(authored,"vertex")
	var fragment := Stages.extract_stage(vertex[0],"fragment")
	var varyings := kernel.substr(kernel.find("varying flat vec2 center_px;"),kernel.find("varying flat float shade;")-kernel.find("varying flat vec2 center_px;"))
	var bend := kernel.substr(kernel.find("vec3 bend("),kernel.find("void vertex()")-kernel.find("vec3 bend(")).replace("bend(","filter_bend(")
	var projection := kernel.substr(kernel.find("    vec3 a=bend("),kernel.find("    float distance_to_eye=")-kernel.find("    vec3 a=bend("))
	projection=projection.replace("bend(","filter_bend(").replace("UV*2.0","filter_corner*2.0")
	var moments := """
    float ua=CUSTOM0.w,ub=CUSTOM1.w,uc=CUSTOM2.w;
    float mean_u=(ua+ub+uc)/3.0;
    filter_edge_squared=4.0*(ua*ua+ub*ub+uc*uc+ua*ub+ua*uc+ub*uc)/6.0-4.0*mean_u+1.0;
    vec2 ab=pb-pa,ac=pc-pa;
    float projected_det=ab.x*ac.y-ab.y*ac.x;
    float safe_det=(projected_det<0.0?-1.0:1.0)*max(abs(projected_det),0.000001);
    filter_uv_width=abs(((ub-ua)*ac.y-(uc-ua)*ab.y)/safe_det)+abs(((uc-ua)*ab.x-(ub-ua)*ac.x)/safe_det);
"""
	var body: String=fragment[1]
	if cluster:
		varyings+="\nuniform vec3 filter_area_vectors[35];\n"
		# Five signed-normal groups retain projected leaf/stem area separately;
		# one averaged normal would cancel coverage at grazing viewing angles.
		moments="""
    filter_edge_squared=1.0/3.0;
    filter_uv_width=1.0;
    vec3 row_w=vec3(mvp[0].w,mvp[1].w,mvp[2].w);
    vec3 jac_x=(vec3(mvp[0].x,mvp[1].x,mvp[2].x)*clip.w-clip.x*row_w)/(clip.w*clip.w)*VIEWPORT_SIZE.x*0.5;
    vec3 jac_y=(vec3(mvp[0].y,mvp[1].y,mvp[2].y)*clip.w-clip.y*row_w)/(clip.w*clip.w)*VIEWPORT_SIZE.y*0.5;
    vec3 projected_normal=cross(jac_x,jac_y);
    int group=int(CUSTOM0.w+0.5);
    float projected_area=0.0;
    for(int bin=0;bin<5;bin++){projected_area+=abs(dot(projected_normal,filter_area_vectors[group+bin]));}
    amplitude=projected_area/(6.28318530718*sqrt(determinant));
"""
	body=body.replace("if(coverage<=threshold)discard;","")
	body=body.replace("max(fwidth(UV.x), 0.008)","max(filter_uv_width, 0.008)")
	body=body.replace("edge * edge","filter_edge_squared")
	body=body.replace("0.96 + 0.04 * sin((UV.y - abs(UV.x - 0.5) * 0.35) * 95.0)","0.96")
	var alpha := """
    vec2 delta=point_px-center_px;
    float quadratic=inverse_cov.x*delta.x*delta.x+2.0*inverse_cov.y*delta.x*delta.y+inverse_cov.z*delta.y*delta.y;
    ALPHA=clamp(amplitude*exp(-0.5*quadratic),0.0,1.0)*coverage;
"""
	body=alpha+"\nif(ALPHA<1.0/255.0)discard;\n"+body if variant=="trim" else body+alpha
	body+="\nif(dot(NORMAL,VIEW)<0.0)NORMAL=-NORMAL;\n"
	if variant=="vertex":
		fragment[0]=fragment[0].replace("diffuse_burley;","diffuse_burley, vertex_lighting;")
		moments+="\nif(dot(MODELVIEW_NORMAL_MATRIX*NORMAL,-(MODELVIEW_MATRIX*vec4(VERTEX,1.0)).xyz)<0.0)NORMAL=-NORMAL;\nROUGHNESS=0.84;\n"
	if variant=="unlit":fragment[0]=fragment[0].replace("diffuse_burley;","unshaded;")
	var result := fragment[0]+varyings+"\nvarying flat float filter_edge_squared;\nvarying flat float filter_uv_width;\n"+bend+"\nvoid vertex(){\nvec2 filter_corner=UV;UV=UV2;\n"+vertex[1]+projection+moments+"\n}\nvoid fragment(){\n"+body+"\n}\n"
	return result.replace("TIME","comparison_time") if authored.contains("uniform float comparison_time") else result

static func install(mesh: ArrayMesh,saved: Dictionary,far_error: float,cluster := false,variant := "original") -> ShaderMaterial:
	if cluster and variant=="original":
		var material := preload("res://addons/world_ecosystem/filtered_fern.gd").apply(mesh,saved.arrays,saved.lods,saved.material,far_error)
		if saved.material.shader.code.contains("uniform float comparison_time"):
			var shader := Shader.new();shader.code=material.shader.code.replace("shader_type spatial;","shader_type spatial;\nuniform float comparison_time=0.0;").replace("TIME","comparison_time");material.shader=shader
		return material
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
	var indices := PackedInt32Array();var original: PackedInt32Array=saved.lods[0.08]
	var records := [];var groups := {}
	if cluster:
		groups=frond_proxies(saved);records=groups.proxies
	else:
		for offset in range(0,original.size(),3):
			var points: Array[Vector3]=[];var texcoords: Array[Vector2]=[]
			for i in 3:
				points.append(saved.arrays[Mesh.ARRAY_VERTEX][original[offset+i]])
				texcoords.append(saved.arrays[Mesh.ARRAY_TEX_UV][original[offset+i]])
			records.append({"points":points,"normal":saved.arrays[Mesh.ARRAY_NORMAL][original[offset]],"color":saved.arrays[Mesh.ARRAY_COLOR][original[offset]],"uv":(texcoords[0]+texcoords[1]+texcoords[2])/3.0,"custom_w":[texcoords[0].x,texcoords[1].x,texcoords[2].x]})
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
	var material := ShaderMaterial.new();var shader := Shader.new()
	shader.code=shader_code(saved.material.shader.code,cluster,variant);material.shader=shader
	if cluster:material.set_shader_parameter("filter_area_vectors",groups.normal_areas)
	for parameter in ["distance_fade_start","distance_fade_end","wind_strength","distant_self_shade","cover_eye","cover_clock"]:material.set_shader_parameter(parameter,saved.material.get_shader_parameter(parameter))
	mesh.surface_set_material(1,material)
	var far_only := ArrayMesh.new();far_only.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{far_error:indices},flags)
	far_only.surface_set_material(0,material);far_only.custom_aabb=saved.bounds
	mesh.set_meta("surface_lod_near",near_only);mesh.set_meta("surface_lod_far",far_only);mesh.set_meta("surface_lod_error",far_error)
	var shadow := ArrayMesh.new();shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,saved.arrays,[],saved.lods);shadow.custom_aabb=saved.bounds
	var empty_shadow := [];empty_shadow.resize(Mesh.ARRAY_MAX);empty_shadow[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	shadow.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,empty_shadow);mesh.shadow_mesh=shadow
	return material
