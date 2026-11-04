# SPDX-License-Identifier: 0BSD
extends RefCounted
## Build-only extraction of the same visible equipment used by the held tools.
const Human=preload("res://addons/characters/runtime/human_view.gd")
const IDS=[1,2]
const RECEIPT="res://addons/player_runtime/art/drops/current_tools.bake.json"
const SHADER=preload("res://addons/player_runtime/art/drops/current_tool.gdshader")
static func snapshot()->Dictionary:
	var result:Dictionary={}
	for path:String in [Human.MODEL.resource_path,Human.MODEL.resource_path+".import","res://addons/characters/runtime/human_view.gd","res://addons/player_runtime/tool_view.gd","res://tools/tool_drop_bake.gd","res://tools/bake_tool_drops.gd",SHADER.resource_path]:
		result[path]=FileAccess.get_sha256(path)
	return result
static func current(state:Dictionary)->bool:
	if not FileAccess.file_exists(RECEIPT):return false
	var receipt:Variant=JSON.parse_string(FileAccess.get_file_as_string(RECEIPT))
	if not receipt is Dictionary or receipt.get("sources")!=state:return false
	for item:int in IDS:
		var path:="res://addons/player_runtime/art/drops/%d.res"%item
		if receipt.get("outputs",{}).get(path)!=FileAccess.get_sha256(path):return false
	return true
static func parts(view:Node,item:int)->Array[MeshInstance3D]:
	view.human.equip(item)
	var result:Array[MeshInstance3D]=[]
	for mesh:MeshInstance3D in view.human.meshes:
		if String(mesh.name).to_lower().replace("_",".").begins_with("equipment.") and mesh.visible:result.append(mesh)
	return result
static func build(view:Node,item:int)->ArrayMesh:
	var meshes:=parts(view,item)
	var bounds:=AABB();var first:=true
	for mesh:MeshInstance3D in meshes:
		var box:AABB=mesh.global_transform*mesh.mesh.get_aabb()
		bounds=box if first else bounds.merge(box);first=false
	if first or bounds.size.length_squared()<.000001:return null
	var factor:=.35/maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
	var normalized:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*factor),-bounds.get_center()*factor)
	var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var material:=ShaderMaterial.new();material.shader=SHADER
	var triangle_count:=0
	for mesh:MeshInstance3D in meshes:
		var pose:Transform3D=normalized*mesh.global_transform
		var normal_basis:=pose.basis.inverse().transposed()
		for index in mesh.mesh.get_surface_count():
			var source:StandardMaterial3D=mesh.get_active_material(index)
			if source==null:return null
			var wood:bool=source.albedo_texture!=null
			if wood:
				# Bundle current embedded textures into the drop asset, not cache paths.
				material.set_shader_parameter("wood_albedo",ImageTexture.create_from_image(source.albedo_texture.get_image()))
				if source.normal_texture!=null:material.set_shader_parameter("wood_normal",ImageTexture.create_from_image(source.normal_texture.get_image()))
				material.set_shader_parameter("wood_normal_strength",source.normal_scale)
			var arrays:=mesh.mesh.surface_get_arrays(index)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var uvs:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for vertex in vertices.size():indices.append(vertex)
			triangle_count+=indices.size()/3
			for vertex:int in indices:
				# StandardMaterial's color uniform is sRGB; shader vertex data is linear.
				var color:=source.albedo_color.srgb_to_linear();color.a=source.metallic
				surface.set_color(color);surface.set_uv(uvs[vertex] if not uvs.is_empty() else Vector2.ZERO)
				surface.set_uv2(Vector2(source.roughness,1 if wood else 0))
				surface.set_normal((normal_basis*normals[vertex]).normalized());surface.add_vertex(pose*vertices[vertex])
	surface.generate_tangents();surface.set_material(material)
	var output:=surface.commit()
	output.set_meta("source_model",Human.MODEL.resource_path)
	output.set_meta("source_model_sha256",FileAccess.get_sha256(Human.MODEL.resource_path))
	output.set_meta("source_item",item);output.set_meta("source_triangles",triangle_count)
	return output
