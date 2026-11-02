# SPDX-License-Identifier: 0BSD
extends RefCounted

static var meshes:Dictionary={}

static func build(stage:int)->Mesh:
	if meshes.has(stage):return meshes[stage]
	var wood:=StandardMaterial3D.new()
	wood.albedo_texture=load("res://addons/structures/textures/terraforest/wood_albedo.png")
	wood.vertex_color_use_as_albedo=true;wood.roughness=.95
	var metal:=StandardMaterial3D.new();metal.albedo_color=Color(.21,.18,.14);metal.metallic=.65;metal.roughness=.72
	var timber:=SurfaceTool.new();timber.begin(Mesh.PRIMITIVE_TRIANGLES);timber.set_material(wood)
	var nails:=SurfaceTool.new();nails.begin(Mesh.PRIMITIVE_TRIANGLES);nails.set_material(metal)
	var heights:=[.49,1.12,1.64]
	var angles:=[-5.0,7.0,-3.5]
	for index in clampi(stage,1,3):
		for side:float in [-1.0,1.0]:
			var pose:=Transform3D(Basis(Vector3.BACK,deg_to_rad(angles[index]*side)),Vector3(.5,heights[index],side*.075))
			var shade:float=.70+index*.12
			_box(timber,Vector3(.89-index*.025,.19+index*.035,.05),pose,Color(shade,shade*.96,shade*.87),Vector2(.12,index*.25+.025),true)
			for across:float in [-.35,.32]:
				var nail:=pose*Transform3D(Basis.IDENTITY,Vector3(across,.025*(index-1),side*.03))
				_box(nails,Vector3(.019,.023,.012),nail,Color.WHITE,Vector2.ZERO)
	var result:=ArrayMesh.new();timber.commit(result);nails.commit(result)
	meshes[stage]=result;return result

static func _box(surface:SurfaceTool,size:Vector3,pose:Transform3D,color:Color,uv_offset:Vector2,rough:bool=false)->void:
	var box:=BoxMesh.new();box.size=size
	var arrays:Array=box.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		var vertex:=vertices[index]
		var uv:=Vector2(vertex.x/size.x+.5,vertex.y/size.y+.5)*Vector2(.76,.20)+uv_offset
		if rough:vertex.x+=(.018 if vertex.x<0 else -.025)*(1 if vertex.y>0 else -.4)
		surface.set_normal(pose.basis*normals[index]);surface.set_uv(uv);surface.set_color(color)
		surface.add_vertex(pose*vertex)
