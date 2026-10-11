# SPDX-License-Identifier: 0BSD
extends RefCounted
# Original temperate woodland sample. Shared startup authoring only;
# all runtime transforms, identity and rendering remain in native batches.
var vertices:=PackedVector3Array()
var normals:=PackedVector3Array()
var colors:=PackedColorArray()
var uvs:=PackedVector2Array()
var tangents:=PackedFloat32Array()

func tri(a: Vector3,b: Vector3,c: Vector3,tint: Color,ta:=Vector2.ZERO,tb:=Vector2.RIGHT,tc:=Vector2.UP,smooth:=false) -> void:
	var normal: Vector3=(b-a).cross(c-a).normalized()
	var du: Vector2=tb-ta;var dv: Vector2=tc-ta
	var det: float=du.x*dv.y-du.y*dv.x
	var tangent: Vector3=((b-a)*dv.y-(c-a)*du.y)/det if absf(det)>0.000001 else Vector3.RIGHT
	var bitangent: Vector3=((c-a)*du.x-(b-a)*dv.x)/det if absf(det)>0.000001 else Vector3.FORWARD
	for point: Vector3 in [a,c,b]:
		vertices.append(point)
		var n: Vector3=Vector3(point.x,point.y*2.3,point.z).normalized() if smooth else normal
		normals.append(n)
		var t: Vector3=(tangent-n*n.dot(tangent)).normalized()
		tangents.append_array(PackedFloat32Array([t.x,t.y,t.z,-1.0 if n.cross(t).dot(bitangent)<0 else 1.0]))
		# Shader vertex colours are linear, unlike the previous StandardMaterial.
		colors.append(tint.srgb_to_linear())
	uvs.append_array(PackedVector2Array([ta,tc,tb]))

func ribbon(points: Array[Vector3],widths: Array[float],side: Vector3,tint: Color,fold: float) -> void:
	for i in range(points.size()-1):
		var t0: float=float(i)/(points.size()-1);var t1: float=float(i+1)/(points.size()-1)
		var a: Vector3=points[i]-side*widths[i];var b: Vector3=points[i]+side*widths[i]
		var c: Vector3=points[i+1]-side*widths[i+1];var d: Vector3=points[i+1]+side*widths[i+1]
		var middle: Vector3=points[i]+Vector3.UP*widths[i]*fold
		var end: Vector3=points[i+1]+Vector3.UP*widths[i+1]*fold
		if widths[i]<0.00001:
			tri(middle,end,c,tint,Vector2(0.5,t0),Vector2(0.5,t1),Vector2(0,t1))
			tri(middle,d,end,tint,Vector2(0.5,t0),Vector2(1,t1),Vector2(0.5,t1))
		elif widths[i+1]<0.00001:
			tri(a,middle,end,tint,Vector2(0,t0),Vector2(0.5,t0),Vector2(0.5,t1))
			tri(middle,b,end,tint,Vector2(0.5,t0),Vector2(1,t0),Vector2(0.5,t1))
		else:
			tri(a,middle,c,tint,Vector2(0,t0),Vector2(0.5,t0),Vector2(0,t1))
			tri(middle,end,c,tint,Vector2(0.5,t0),Vector2(0.5,t1),Vector2(0,t1))
			tri(middle,b,end,tint,Vector2(0.5,t0),Vector2(1,t0),Vector2(0.5,t1))
			tri(b,d,end,tint,Vector2(1,t0),Vector2(1,t1),Vector2(0.5,t1))

func rock_point(u: float,v: float) -> Vector3:
	var a:=TAU*u;var elevation:=PI*v
	var radius: float=1.0+0.07*sin(a*3.0+elevation)*sin(elevation)+0.035*cos(a*7.0-elevation*2.0)*sin(elevation)
	return Vector3(cos(a)*sin(elevation)*0.31*radius,cos(elevation)*0.175,sin(a)*sin(elevation)*0.255*radius)

func stone_mesh(low: bool) -> void:
	var sides: int=8 if low else 20;var rings: int=4 if low else 10
	for y in rings:
		for x in sides:
			var a:=Vector2(float(x)/sides,float(y)/rings);var b:=Vector2(float(x+1)/sides,float(y)/rings)
			var c:=Vector2(float(x)/sides,float(y+1)/rings);var d:=Vector2(float(x+1)/sides,float(y+1)/rings)
			if y>0:tri(rock_point(a.x,a.y),rock_point(b.x,b.y),rock_point(c.x,c.y),Color.WHITE,a,b,c,true)
			if y<rings-1:tri(rock_point(b.x,b.y),rock_point(d.x,d.y),rock_point(c.x,c.y),Color.WHITE,b,d,c,true)

func fern(low: bool) -> void:
	for frond in 7:
		var angle: float=frond*2.399963
		var direction:=Vector3(cos(angle),0,sin(angle));var side:=Vector3(-direction.z,0,direction.x)
		var height: float=0.42+0.14*(0.5+0.5*sin(frond*1.77))
		var stem: Array[Vector3]=[];var widths: Array[float]=[]
		for i in 7:
			var t: float=i/6.0
			stem.append(direction*(0.285*t*t)+Vector3.UP*(0.02+height*sin(t*1.35)))
			widths.append(0.0035*(1.0-t)+0.0004)
		ribbon(stem,widths,side,Color("70783c"),0.0)
		var pairs: int=4 if low else 8
		for pair in pairs:
			var t: float=0.18+0.77*pair/float(pairs)
			var root_point: Vector3=direction*(0.285*t*t)+Vector3.UP*(0.02+height*sin(t*1.35))
			var length: float=0.105*sin(PI*(t*0.88+0.04))*(1.0-t*0.5)
			for sign_value in [-1.0,1.0]:
				var axis: Vector3=(side*sign_value+direction*0.48+Vector3.UP*0.18).normalized()
				var cross_axis: Vector3=Vector3(-axis.z,0,axis.x).normalized()
				var leaf: Array[Vector3]=[];var leaf_widths: Array[float]=[]
				var segments: int=2 if low else 4
				for j in range(segments+1):
					var s: float=float(j)/segments
					leaf.append(root_point+axis*(length*s)+Vector3.UP*(sin(s*PI)*0.008-s*s*0.007))
					leaf_widths.append(0.024*(1.0-t*0.35)*sin(PI*s) if j<segments else 0.0)
				ribbon(leaf,leaf_widths,cross_axis,Color("46713b").lerp(Color("789649"),t*0.55+0.08*sin(frond)),0.22)

func grass(low: bool) -> void:
	var blades: int=12 if low else 28
	for blade in blades:
		var angle: float=blade*2.399963
		var direction:=Vector3(cos(angle),0,sin(angle));var side:=Vector3(-direction.z,0,direction.x)
		var height: float=0.20+0.29*(0.5+0.5*sin(blade*1.71+0.5))
		var lean: float=0.07+0.16*(0.5+0.5*cos(blade*2.13))
		var segments: int=2 if low else 5
		var points: Array[Vector3]=[];var widths: Array[float]=[]
		for j in range(segments+1):
			var t: float=float(j)/segments
			points.append(direction*(0.025+lean*t*t)+Vector3.UP*(0.005+height*(t-0.14*t*t*t)))
			widths.append(0.007*(1.0-t)*(.7+.3*sin(blade*1.3+0.7)))
		var tint:=Color("858255") if blade%7==0 else Color("4b713b").lerp(Color("85984e"),0.5+0.5*sin(blade*2.17))
		ribbon(points,widths,side,tint,0.35)

static func build(species: int,with_lod: bool=true) -> ArrayMesh:
	if species<0 or species>2:return null
	var asset=load("res://addons/world_ecosystem/woodland_mesh.gd").new()
	var method: String=["stone_mesh","fern","grass"][species]
	asset.call(method,false)
	var full_count: int=asset.vertices.size();var indices:=PackedInt32Array()
	for i in full_count:indices.append(i)
	var lods: Dictionary={}
	if with_lod:
		asset.call(method,true)
		var distant:=PackedInt32Array()
		for i in range(full_count,asset.vertices.size()):distant.append(i)
		lods[[0.03,0.025,0.02][species]]=distant
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=asset.vertices;arrays[Mesh.ARRAY_NORMAL]=asset.normals;arrays[Mesh.ARRAY_COLOR]=asset.colors;arrays[Mesh.ARRAY_TEX_UV]=asset.uvs;arrays[Mesh.ARRAY_INDEX]=indices
	arrays[Mesh.ARRAY_TANGENT]=asset.tangents
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],lods)
	mesh.custom_aabb=AABB(Vector3(-0.4,-0.2 if species==0 else 0,-0.4),Vector3(0.8,0.4 if species==0 else 0.75,0.8))
	var material:=ShaderMaterial.new();material.shader=preload("res://addons/world_ecosystem/woodland.gdshader");material.set_shader_parameter("stone",species==0)
	if species==0:
		for channel in ["color","normal"]:
			var image:=Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://addons/world_ecosystem/art/stone_"+channel+".trtex"))!=OK:return null
			image.generate_mipmaps(channel=="normal")
			material.set_shader_parameter("stone_"+channel,ImageTexture.create_from_image(image))
	mesh.surface_set_material(0,material)
	return mesh
