extends RefCounted
const Source=preload("res://addons/vegetation/source.gd")
var source=Source.new()
var meshes: Array[ArrayMesh]=[]
var materials: Array[ShaderMaterial]=[]
var bytes_views: int=0
var color_views: Texture2DArray
var normal_views: Texture2DArray
var outline: ImageTexture
var depth_views: Texture2DArray
var previous_normal_views: Texture2DArray
var previous_revision: bool=false
var proxy_materials: Array[ShaderMaterial]=[]
var gpu_optimized: bool=false
var compact_materials: bool=true
# Slots match source wood/foliage, middle, far, source shadow wood/foliage, proxy shadow.
const GPU5_SHADERS=["res://addons/vegetation/gpu5_bark.gdshader","res://addons/vegetation/gpu5_surface.gdshader","res://addons/vegetation/gpu5_middle.gdshader","res://addons/vegetation/gpu5_far.gdshader","res://addons/vegetation/gpu5_bark_shadow.gdshader","res://addons/vegetation/gpu5_surface_shadow.gdshader","res://addons/vegetation/gpu5_shadow.gdshader"]
const RC4_SHADERS=["res://addons/vegetation/bark.gdshader","res://addons/vegetation/surface.gdshader","res://addons/vegetation/proxy.gdshader","res://addons/vegetation/proxy.gdshader","res://addons/vegetation/bark.gdshader","res://addons/vegetation/surface.gdshader","res://addons/vegetation/proxy.gdshader"]

func set_gpu_optimized(value: bool)->bool:
	if previous_revision and not set_previous(false):return false
	gpu_optimized=value
	if materials.size()!=7:return false
	for i in range(materials.size()):
		var path: String=GPU5_SHADERS[i] if value else RC4_SHADERS[i]
		var shader: Shader=load(path) as Shader
		if shader==null:return false
		materials[i].shader=shader
	_uniform_cache.clear()
	return true


# RC6 compares channel-compacted source maps against the original maps. Both use
# the RC4 proxy/caster shaders; RC5 remains an explicit internal regression path.
func set_compact_materials(value: bool)->bool:
	if not source.set_compact_source(value):return false
	if not set_gpu_optimized(false):return false
	compact_materials=value
	for i in [0,1,4,5]:
		var prefix: String="Bark" if i==0 or i==4 else "Needles"
		var m: ShaderMaterial=materials[i]
		m.set_shader_parameter("base_tex",source.maps[prefix+"BaseColor"])
		m.set_shader_parameter("normal_tex",source.maps[prefix+"Normal"])
		m.set_shader_parameter("orm_tex",source.maps[prefix+"ORM"])
		if value and prefix=="Needles" and source.constant_needles_orm:
			m.shader=load("res://addons/vegetation/surface6.gdshader") as Shader
	_uniform_cache.clear()
	return true

func material_path()->String:
	return "RC6" if compact_materials else "RC4"

func material_payload()->Dictionary:
	return {"path":material_path(),"source_map_bytes":source.source_payload_bytes,"view_array_bytes":bytes_views,"source_map_info":source.source_map_info,"scope":"Image payload, not measured driver VRAM, frame bandwidth, or watts. Both source variants stay resident during A/B only."}

func array_file(path: String) -> Texture2DArray:
	var f: FileAccess=FileAccess.open(path,FileAccess.READ)
	if f==null:return null
	var magic: String=f.get_buffer(4).get_string_from_ascii()
	if magic!="F11V" and magic!="F11N":return null
	var w: int=f.get_32();var h: int=f.get_32();var count: int=f.get_32();var stride: int=f.get_32()
	if w!=128 or h!=256 or count!=320 or stride!=(174764 if magic=="F11N" else 43728) or f.get_length()!=20+count*stride:return null
	var images: Array[Image]=[]
	for i in range(count):images.append(Image.create_from_data(w,h,true,Image.FORMAT_RGBA8 if magic=="F11N" else Image.FORMAT_DXT5,f.get_buffer(stride)))
	f.close();var tex: Texture2DArray=Texture2DArray.new()
	if tex.create_from_images(images)!=OK:return null
	bytes_views+=count*stride;return tex

static func grid() -> Array:
	var v: PackedVector3Array=PackedVector3Array();var normals: PackedVector3Array=PackedVector3Array();var ix: PackedInt32Array=PackedInt32Array()
	for y in range(13):
		for x in range(9):v.append(Vector3((float(x)/8.0-0.5)*10.0,(float(y)/12.0-0.5)*20.0,-1));normals.append(Vector3(0,0,1))
	for y in range(12):
		for x in range(8):
			var a: int=y*9+x;ix.append_array(PackedInt32Array([a,a+9,a+1,a+1,a+9,a+10]))
	var a: Array=[];a.resize(Mesh.ARRAY_MAX);a[Mesh.ARRAY_VERTEX]=v;a[Mesh.ARRAY_NORMAL]=normals;a[Mesh.ARRAY_INDEX]=ix;return a

static func polygon() -> Array:
	var v: PackedVector3Array=PackedVector3Array();var n: PackedVector3Array=PackedVector3Array();var ix: PackedInt32Array=PackedInt32Array()
	for i in range(13):v.append(Vector3(0,0,i));n.append(Vector3(0,0,1))
	for i in range(12):ix.append_array(PackedInt32Array([12,(i+1)%12,i]))
	var a: Array=[];a.resize(Mesh.ARRAY_MAX);a[Mesh.ARRAY_VERTEX]=v;a[Mesh.ARRAY_NORMAL]=n;a[Mesh.ARRAY_INDEX]=ix;return a

func packed_array12(path: String, magic_expected: String, format: Image.Format, mips: bool, stride_expected: int) -> Texture2DArray:
	var f: FileAccess=FileAccess.open(path,FileAccess.READ)
	if f==null:return null
	var magic: String=f.get_buffer(4).get_string_from_ascii()
	var w: int=f.get_32();var h: int=f.get_32();var count: int=f.get_32();var stride: int=f.get_32()
	if magic!=magic_expected or w!=128 or h!=256 or count!=320 or stride!=stride_expected or f.get_length()!=20+count*stride:return null
	var images: Array[Image]=[]
	for i in range(count):
		var image: Image=Image.create_from_data(w,h,mips,format,f.get_buffer(stride))
		if image==null:return null
		images.append(image)
	f.close()
	var tex: Texture2DArray=Texture2DArray.new()
	if tex.create_from_images(images)!=OK:return null
	bytes_views+=count*stride
	return tex

func set_previous(value: bool)->bool:
	# Legacy comparison assets are intentionally excluded from the runtime package.
	return not value

func build() -> bool:
	if not source.open():return false
	color_views=array_file("res://addons/vegetation/data/views.color.bin")
	normal_views=packed_array12("res://addons/vegetation/data/views.normals.565","F12N",Image.FORMAT_RGB565,true,87382)
	depth_views=packed_array12("res://addons/vegetation/data/views.depth.r8","F12D",Image.FORMAT_R8,false,32768)
	if color_views==null or normal_views==null or depth_views==null:return false
	var f: FileAccess=FileAccess.open("res://addons/vegetation/data/views.outline.bin",FileAccess.READ)
	if f==null or f.get_buffer(4).get_string_from_ascii()!="F11E" or f.get_32()!=13 or f.get_32()!=320:return false
	outline=ImageTexture.create_from_image(Image.create_from_data(13,320,false,Image.FORMAT_RGBAF,f.get_buffer(13*320*16)));f.close()
	for kind in range(5):
		var mesh: ArrayMesh
		if kind==0 or kind==3:
			var ms: Array[ShaderMaterial]=[source.material("res://addons/vegetation/bark.gdshader",0),source.material("res://addons/vegetation/surface.gdshader",1)]
			for m in ms:m.set_shader_parameter("shadow_only",kind==3);materials.append(m)
			mesh=source.mesh(ms)
		else:
			var m: ShaderMaterial=ShaderMaterial.new();m.shader=load("res://addons/vegetation/proxy.gdshader") as Shader;m.set_shader_parameter("color_views",color_views);m.set_shader_parameter("normal_depth_views",normal_views);m.set_shader_parameter("depth_views",depth_views);m.set_shader_parameter("outline_texture",outline);m.set_shader_parameter("depth_shape",kind==1);m.set_shader_parameter("distant",kind==2);m.set_shader_parameter("shadow_only",kind==4)
			materials.append(m);proxy_materials.append(m);mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,grid() if kind==1 else polygon());mesh.surface_set_material(0,m)
			mesh.custom_aabb=AABB(Vector3(-13,-4,-13),Vector3(26,28,26))
		meshes.append(mesh)
	return set_compact_materials(compact_materials)

var _uniform_cache: Dictionary={}
var uniform_writes: int=0

func _set_shared(name: String,value: Variant)->void:
	if _uniform_cache.has(name) and _uniform_cache[name]==value:return
	_uniform_cache[name]=value
	for m in materials:
		m.set_shader_parameter(name,value)
		uniform_writes+=1

func uniforms(eye: Vector3,sun: Vector3,t: float,wind: float,range_m: float,animate: bool=true)->void:
	_set_shared("eye_world",eye)
	_set_shared("sun_direction",sun)
	_set_shared("wind_amount",wind)
	_set_shared("far_distance",range_m)
	if animate or wind!=0.0 or not _uniform_cache.has("clock_seconds"):
		_set_shared("clock_seconds",fposmod(t,4096.0))
