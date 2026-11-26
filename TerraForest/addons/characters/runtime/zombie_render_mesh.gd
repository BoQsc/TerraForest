# SPDX-License-Identifier: 0BSD
extends RefCounted
## Derived, immutable render surfaces for the original R4 geometry. Skin, UVs,
## normals, morphs and source-order vertices remain unchanged; only material
## submissions are combined. Collision continues using the original CPU packet.
static var cache:Dictionary={}
static var materials:Array[StandardMaterial3D]=[]
static var shared:ShaderMaterial
static var ready:=false
static var defaults:=StandardMaterial3D.new()
const SIZES:=[256,512,1024]
const CODE:="""
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform sampler2DArray colors256 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray colors512 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray colors1024 : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normals256 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normals512 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2DArray normals1024 : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec4 base_colors[32];
uniform vec4 pbr[32];
uniform vec4 layers[32];
uniform vec4 flags[32];
void fragment() {
    int surface_id = int(round(UV2.x));
    vec4 lookup = layers[surface_id];
    vec3 tint = vec3(1.0);
    if (lookup.x == 256.0) tint = texture(colors256, vec3(UV, lookup.y)).rgb;
    else if (lookup.x == 512.0) tint = texture(colors512, vec3(UV, lookup.y)).rgb;
    else if (lookup.x == 1024.0) tint = texture(colors1024, vec3(UV, lookup.y)).rgb;
    vec3 vertex_tint = COLOR.rgb;
    if (flags[surface_id].y > 0.5) {
        vertex_tint = mix(vertex_tint / 12.92, pow((vertex_tint + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), vertex_tint));
    }
    ALBEDO = tint * base_colors[surface_id].rgb * mix(vec3(1.0), vertex_tint, flags[surface_id].x);
    ROUGHNESS = pbr[surface_id].x;
    METALLIC = pbr[surface_id].y;
    SPECULAR = pbr[surface_id].z;
    vec3 normal_sample = vec3(0.5, 0.5, 1.0);
    if (lookup.z == 256.0) normal_sample = texture(normals256, vec3(UV, lookup.w)).rgb;
    else if (lookup.z == 512.0) normal_sample = texture(normals512, vec3(UV, lookup.w)).rgb;
    else if (lookup.z == 1024.0) normal_sample = texture(normals1024, vec3(UV, lookup.w)).rgb;
    NORMAL_MAP = normal_sample;
    NORMAL_MAP_DEPTH = pbr[surface_id].w;
}
"""
static func supported(material:Material)->bool:
	if not material is StandardMaterial3D or material.cull_mode!=BaseMaterial3D.CULL_DISABLED:return false
	for property:Dictionary in defaults.get_property_list():
		var key:String=property.name
		if not (property.usage&PROPERTY_USAGE_STORAGE) or key in ["resource_name","resource_local_to_scene","albedo_color","albedo_texture","roughness","metallic","metallic_specular","cull_mode","normal_enabled","normal_texture","normal_scale","vertex_color_use_as_albedo","vertex_color_is_srgb"]:continue
		if material.get(key)!=defaults.get(key):return false
	return true
static func configure(sources:Array)->bool:
	if ready:return shared!=null
	ready=true
	var images:Dictionary={};var indices:Dictionary={}
	for family:String in ["colors","normals"]:
		for size:int in SIZES:images[family+str(size)]=[]
	for mesh:Mesh in sources:
		for surface in mesh.get_surface_count():
			var material:=mesh.surface_get_material(surface)
			if not supported(material) or materials.has(material):continue
			if materials.size()>=32:return false
			materials.append(material)
	var colors:=PackedVector4Array();var pbr:=PackedVector4Array();var layers:=PackedVector4Array();var flags:=PackedVector4Array()
	for material:StandardMaterial3D in materials:
		var lookup:=Vector4.ZERO
		for family:String in ["colors","normals"]:
			var texture:Texture2D=material.albedo_texture if family=="colors" else (material.normal_texture if material.normal_enabled else null)
			if texture==null:continue
			if not indices.has(texture):
				var pixels:=texture.get_image()
				if pixels==null:return false
				pixels=pixels.duplicate()
				if pixels.is_compressed() and pixels.decompress()!=OK:return false
				var size:=pixels.get_width()
				if size not in SIZES or pixels.get_height()!=size:return false
				pixels.convert(Image.FORMAT_RGBA8)
				if not pixels.has_mipmaps():return false
				var key:=family+str(size);indices[texture]=Vector2(size,images[key].size());images[key].append(pixels)
			var location:Vector2=indices[texture]
			if family=="colors":lookup.x=location.x;lookup.y=location.y
			else:lookup.z=location.x;lookup.w=location.y
		var color:=material.albedo_color.srgb_to_linear()
		colors.append(Vector4(color.r,color.g,color.b,color.a));layers.append(lookup)
		pbr.append(Vector4(material.roughness,material.metallic,material.metallic_specular,material.normal_scale if material.normal_enabled else 0.0))
		flags.append(Vector4(float(material.vertex_color_use_as_albedo),float(material.vertex_color_is_srgb),0,0))
	colors.resize(32);pbr.resize(32);layers.resize(32);flags.resize(32)
	shared=ShaderMaterial.new();var shader:=Shader.new();shader.code=CODE;shared.shader=shader
	shared.set_shader_parameter("base_colors",colors);shared.set_shader_parameter("pbr",pbr);shared.set_shader_parameter("layers",layers);shared.set_shader_parameter("flags",flags)
	for key:String in images:
		var source:Array[Image]=[];source.assign(images[key])
		if source.is_empty():
			var blank:=Image.create(4,4,true,Image.FORMAT_RGBA8);blank.fill(Color.WHITE);source.append(blank)
		var texture:=Texture2DArray.new()
		if texture.create_from_images(source)!=OK:shared=null;return false
		shared.set_shader_parameter(key,texture)
	return true
static func forget(reference:WeakRef)->void:
	var source:Mesh=reference.get_ref()
	if source!=null:cache.erase(source)
static func prepare(source:ArrayMesh,packet:Dictionary)->Dictionary:
	if cache.has(source):return cache[source]
	if shared==null or source.get_surface_count()<2 or packet.is_empty():return {}
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var morphs:Array=[]
	for index in source.get_blend_shape_count():
		var morph:Array=[];morph.resize(Mesh.ARRAY_MAX);morphs.append(morph)
	var identifiers:=PackedVector2Array();var indices:=PackedInt32Array();var vertices:=0
	var lod_sources:Array[Dictionary]=[];var lod_keys:Dictionary={};var full_indices:Array[PackedInt32Array]=[]
	var source_format:=0
	var imported:=ImporterMesh.from_mesh(source)
	for surface in source.get_surface_count():
		var material:=source.surface_get_material(surface)
		var material_index:=materials.find(material)
		if material_index<0 or source.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES:return {}
		var values:Array=packet.surfaces[surface]
		if values[Mesh.ARRAY_TEX_UV2]!=null and not values[Mesh.ARRAY_TEX_UV2].is_empty():return {}
		for channel in range(Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM3+1):
			if values[channel]!=null and not values[channel].is_empty():return {}
		var format:=source.surface_get_format(surface)&Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		if surface>0 and format!=source_format:return {}
		source_format=format
		var count:int=values[Mesh.ARRAY_VERTEX].size()
		var ids:=PackedVector2Array();ids.resize(count);ids.fill(Vector2(material_index,0));identifiers.append_array(ids)
		var faces:PackedInt32Array=values[Mesh.ARRAY_INDEX] if values[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		if faces.is_empty():
			faces.resize(count)
			for index in count:faces[index]=index
		for index in faces.size():faces[index]+=vertices
		indices.append_array(faces)
		full_indices.append(faces)
		var shifted:Dictionary={}
		for level in imported.get_surface_lod_count(surface):
			var distance:float=imported.get_surface_lod_size(surface,level)
			var lod_indices:PackedInt32Array=imported.get_surface_lod_indices(surface,level)
			for index in lod_indices.size():lod_indices[index]+=vertices
			shifted[distance]=lod_indices;lod_keys[distance]=true
		lod_sources.append(shifted)
		for channel in Mesh.ARRAY_MAX:
			if channel==Mesh.ARRAY_INDEX or values[channel]==null:continue
			if arrays[channel]==null:arrays[channel]=values[channel].duplicate()
			else:arrays[channel].append_array(values[channel])
		for index in morphs.size():
			for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT]:
				var values_morph:Variant=packet.morphs[surface][index][channel]
				if values_morph==null:continue
				if morphs[index][channel]==null:morphs[index][channel]=values_morph.duplicate()
				else:morphs[index][channel].append_array(values_morph)
		vertices+=count
	arrays[Mesh.ARRAY_INDEX]=indices;arrays[Mesh.ARRAY_TEX_UV2]=identifiers
	var mesh:=ArrayMesh.new();mesh.blend_shape_mode=source.blend_shape_mode
	for index in source.get_blend_shape_count():mesh.add_blend_shape(source.get_blend_shape_name(index))
	var format:=source_format
	# Preserve every original index-LOD transition. Each combined threshold uses
	# the last eligible source LOD for each material, including unchanged full
	# indices for surfaces that have not reached their first transition.
	var combined_lods:Dictionary={}
	var distances:Array=lod_keys.keys();distances.sort()
	for distance:float in distances:
		var faces:=PackedInt32Array()
		for surface in lod_sources.size():
			var selected:PackedInt32Array=full_indices[surface];var selected_distance:=-INF
			for threshold:float in lod_sources[surface]:
				if threshold<=distance and threshold>selected_distance:selected=lod_sources[surface][threshold];selected_distance=threshold
			faces.append_array(selected)
		combined_lods[distance]=faces
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,morphs,combined_lods,format);mesh.surface_set_material(0,shared)
	if mesh.get_surface_count()!=1:return {}
	mesh.custom_aabb=source.get_aabb()
	# Both resource identities propagate invalidation to the existing geometry
	# listeners; changing derived data cannot leave stale hit-test geometry.
	mesh.changed.connect(source.emit_changed)
	var result:={"mesh":mesh,"packet":{"surfaces":[arrays],"morphs":[morphs],"formats":[0]}}
	cache[source]=result
	source.changed.connect(forget.bind(weakref(source)),CONNECT_ONE_SHOT)
	return result
