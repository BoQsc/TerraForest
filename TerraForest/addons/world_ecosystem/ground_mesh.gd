# SPDX-License-Identifier: 0BSD
extends RefCounted
# Three shared startup assets. No per-instance script, alpha texture or physics.
var vertices:=PackedVector3Array()
var normals:=PackedVector3Array()
var colors:=PackedColorArray()

func triangle(a: Vector3,b: Vector3,c: Vector3,tint: Color) -> void:
	var normal: Vector3=(b-a).cross(c-a).normalized()
	# Godot front faces use clockwise winding; keep outward normals explicit.
	vertices.append_array(PackedVector3Array([a,c,b]))
	normals.append_array(PackedVector3Array([normal,normal,normal]))
	for point in [a,c,b]:
		var shade: float=clampf(0.65+point.y*0.65,0.5,1.0)
		colors.append(Color(tint.r*shade,tint.g*shade,tint.b*shade,1))

static func build(species: int) -> ArrayMesh:
	if species<0 or species>2:return null
	var asset=load("res://addons/world_ecosystem/ground_mesh.gd").new()
	if species==0:
		var rings: Array[Vector3]=[]
		for ring in 3:
			for i in 9:
				var angle: float=TAU*i/9.0+0.11*ring
				var radius: float=[0.18,0.31,0.21][ring]*(0.88+0.12*sin(i*3.17+ring*1.3))
				rings.append(Vector3(cos(angle)*radius,[-0.14,0.015,0.13][ring]+0.014*sin(i*2.1),sin(angle)*radius))
		for i in 9:
			var j: int=(i+1)%9
			asset.triangle(Vector3(0,-0.18,0),rings[i],rings[j],Color("76796f"))
			asset.triangle(Vector3(0.02,0.18,-0.025),rings[18+j],rings[18+i],Color("91958c"))
			for ring in 2:
				var a: Vector3=rings[ring*9+i];var b: Vector3=rings[ring*9+j]
				var c: Vector3=rings[(ring+1)*9+i];var d: Vector3=rings[(ring+1)*9+j]
				asset.triangle(a,c,b,Color("85877e"))
				asset.triangle(b,c,d,Color("85877e"))
	else:
		for i in (5 if species==2 else 7):
			var angle: float=i*2.399963
			var direction:=Vector3(cos(angle),0,sin(angle))
			var side:=Vector3(-direction.z,0,direction.x)
			var variation: float=0.8+0.2*sin(i*1.7+0.4)
			if species==1:
				var base: Vector3=direction*0.025+Vector3.UP*0.015
				var middle: Vector3=direction*0.19+Vector3.UP*(0.33*variation)
				var tip: Vector3=direction*0.36+Vector3.UP*(0.64*variation)
				var left: Vector3=middle-side*0.11;var right: Vector3=middle+side*0.11
				var ridge: Vector3=middle+Vector3.UP*0.045
				asset.triangle(base,left,ridge,Color("668d3c"));asset.triangle(base,ridge,right,Color("729742"))
				asset.triangle(left,tip,ridge,Color("668d3c"));asset.triangle(ridge,tip,right,Color("729742"))
			else:
				var base: Vector3=direction*0.07
				var middle: Vector3=direction*0.12+Vector3.UP*(0.28*variation)
				var tip: Vector3=direction*0.28+Vector3.UP*(0.39*variation)
				var a: Vector3=base-side*0.025;var b: Vector3=base+side*0.025
				var c: Vector3=middle-side*0.014;var d: Vector3=middle+side*0.014
				var tint:=Color("899847") if i%2 else Color("6b853f")
				asset.triangle(a,b,c,tint);asset.triangle(b,d,c,tint);asset.triangle(c,d,tip,tint)
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=asset.vertices;arrays[Mesh.ARRAY_NORMAL]=asset.normals;arrays[Mesh.ARRAY_COLOR]=asset.colors
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.vertex_color_is_srgb=true;material.roughness=1
	if species!=0:material.cull_mode=BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0,material)
	return mesh
