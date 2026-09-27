extends RefCounted
var arrays: Array[Array] = []
var maps: Dictionary = {}
var source_triangles: int = 0
var compact_source: bool = true
var source_payload_bytes: int = 0
var maps_compact: Dictionary = {}
var maps_reference: Dictionary = {}
var source_map_info: Dictionary = {}
# This exact asset is constant in every source pixel. Changed assets use full maps.
const CONSTANT_NEEDLES_ORM_SHA: String = "45b13ba55ff895d5d2069996a4736425e376dba3528324438916d88fdc143ad7"
var constant_needles_orm: bool = false

func map_variant(compact: bool)->Dictionary:
	var cache: Dictionary=maps_compact if compact else maps_reference
	if not cache.is_empty():return cache
	var info: Dictionary={};var total: int=0
	for prefix in ["Bark","Needles"]:
		for channel in ["BaseColor","Normal","ORM"]:
			var key: String=prefix+channel
			# Albedo/coverage is byte-identical and shared, not reloaded for the A/B.
			if channel=="BaseColor" and maps_compact.has(key):
				cache[key]=maps_compact[key]
				var old: Dictionary=source_map_info["compact"][key]
				info[key]=old.duplicate();total+=int(old["bytes"]);continue
			var path: String="res://addons/vegetation/data/"+prefix+"."+channel+".trtex"
			var image := Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:return {}
			if image==null:return {}
			var original_size: Vector2i=image.get_size()
			var constant: bool=prefix=="Needles" and channel=="ORM" and FileAccess.get_sha256(path)==CONSTANT_NEEDLES_ORM_SHA
			if constant:constant_needles_orm=true
			if compact and constant:
				image=Image.create(1,1,false,Image.FORMAT_RGB8)
				image.fill(Color(1.0,194.0/255.0,0.0,1.0))
			else:
				# Normalize/generate the ORIGINAL mip chain before dropping any channels.
				image.generate_mipmaps(channel=="Normal")
				if compact and (channel=="Normal" or channel=="ORM"):
					image.convert(Image.FORMAT_RG8)
			if image.is_empty():return {}
			var bytes: int=image.get_data_size()
			info[key]={"format":image.get_format(),"size":[image.get_width(),image.get_height()],"original_size":[original_size.x,original_size.y],"mipmaps":image.get_mipmap_count(),"bytes":bytes,"constant_verified":constant,"consumed_channels":"RG" if channel!="BaseColor" else "RGBA"}
			total+=bytes
			cache[key]=ImageTexture.create_from_image(image)
	source_map_info["compact" if compact else "reference"]=info
	source_map_info["compact_bytes" if compact else "reference_bytes"]=total
	return cache

func set_compact_source(value: bool)->bool:
	var selected: Dictionary=map_variant(value)
	if selected.size()!=6:return false
	maps=selected;compact_source=value
	source_payload_bytes=int(source_map_info["compact_bytes" if value else "reference_bytes"])
	return true


func open() -> bool:
	var f: FileAccess = FileAccess.open("res://addons/vegetation/data/source.bin",FileAccess.READ)
	if f==null or f.get_buffer(4).get_string_from_ascii()!="F11M": return false
	var count: int=f.get_32()
	if count!=2:return false
	for part in range(count):
		var n: int=f.get_32();var ni: int=f.get_32();var material_index: int=f.get_32()
		if n<1 or n>100000 or ni<3 or ni>1000000 or ni%3!=0 or material_index!=part: return false
		if f.get_length()-f.get_position()<n*64+ni*4:return false
		var p: PackedFloat32Array=f.get_buffer(n*12).to_float32_array()
		var nr: PackedFloat32Array=f.get_buffer(n*12).to_float32_array()
		var tangent: PackedFloat32Array=f.get_buffer(n*16).to_float32_array()
		var u: PackedFloat32Array=f.get_buffer(n*8).to_float32_array()
		var co: PackedFloat32Array=f.get_buffer(n*16).to_float32_array()
		var ix: PackedInt32Array=f.get_buffer(ni*4).to_int32_array()
		var positions: PackedVector3Array=PackedVector3Array();var normals: PackedVector3Array=PackedVector3Array();var uv: PackedVector2Array=PackedVector2Array();var colors: PackedColorArray=PackedColorArray()
		positions.resize(n);normals.resize(n);uv.resize(n);colors.resize(n)
		for k in range(n):
			positions[k]=Vector3(p[k*3],p[k*3+1],p[k*3+2]);normals[k]=Vector3(nr[k*3],nr[k*3+1],nr[k*3+2]);uv[k]=Vector2(u[k*2],u[k*2+1]);colors[k]=Color(co[k*4],co[k*4+1],co[k*4+2],co[k*4+3])
		var a: Array=[];a.resize(Mesh.ARRAY_MAX);a[Mesh.ARRAY_VERTEX]=positions;a[Mesh.ARRAY_NORMAL]=normals;a[Mesh.ARRAY_TANGENT]=tangent;a[Mesh.ARRAY_TEX_UV]=uv;a[Mesh.ARRAY_COLOR]=colors;a[Mesh.ARRAY_INDEX]=ix
		for index in ix:
			if index<0 or index>=n:return false
		arrays.append(a);source_triangles+=ni/3
	f.close()
	if not set_compact_source(compact_source):return false
	return arrays.size()==2 and source_triangles==6592

func mesh(materials: Array[ShaderMaterial]) -> ArrayMesh:
	var result: ArrayMesh=ArrayMesh.new()
	for i in range(arrays.size()):
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays[i]);result.surface_set_material(i,materials[i])
	return result

func material(shader_path: String,part: int) -> ShaderMaterial:
	var m: ShaderMaterial=ShaderMaterial.new();m.shader=load(shader_path) as Shader
	var prefix: String="Needles" if part==1 else "Bark"
	m.set_shader_parameter("base_tex",maps[prefix+"BaseColor"]);m.set_shader_parameter("normal_tex",maps[prefix+"Normal"]);m.set_shader_parameter("orm_tex",maps[prefix+"ORM"]);m.set_shader_parameter("foliage",part==1);m.set_shader_parameter("normal_strength",0.48 if part==1 else 0.4);m.set_shader_parameter("ao_strength",0.45 if part==1 else 0.65)
	return m
