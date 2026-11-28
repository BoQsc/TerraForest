# SPDX-License-Identifier: 0BSD
extends RefCounted
## One cached render mesh per original pack mesh; unsupported PBR surfaces stay exact.
static var native:RefCounted=ClassDB.instantiate("NativePackMesh")
static var cache: Dictionary={}
static var shaders: Dictionary={}
static var defaults:=StandardMaterial3D.new()
static var shared_signature:=PackedInt64Array()
static var shared_texture: Texture2DArray
static var shared_materials: Dictionary={}
static var shared_layers: Dictionary={}
static var shared_size:=Vector2i.ZERO
static var shared_mipmaps:=false
static var preparation_profile:Dictionary={"surface_reads":0,"surface_read_us":0,"lod_calls":0,"lod_us":0}

static func read_surface(source:Mesh,index:int)->Dictionary:
	var began:=Time.get_ticks_usec()
	var data:=RenderingServer.mesh_get_surface(source.get_rid(),index)
	preparation_profile.surface_reads+=1;preparation_profile.surface_read_us+=Time.get_ticks_usec()-began
	return data

static func source_image(texture:Texture2D,images:Dictionary)->Image:
	if texture==null:return null
	if not images.has(texture):images[texture]=texture.get_image()
	return images[texture]
const PARAMETERS:="""
uniform sampler2DArray surfaces : source_color, filter_linear_mipmap, repeat_enable;
void fragment() {
    vec3 low = COLOR.rgb / 12.92;
    vec3 high = pow((COLOR.rgb + vec3(0.055)) / 1.055, vec3(2.4));
    vec3 tint = mix(low, high, step(vec3(0.04045), COLOR.rgb));
    ALBEDO = tint * texture(surfaces, vec3(UV, round(COLOR.a * 255.0))).rgb;
    ROUGHNESS = UV2.x;
    METALLIC = UV2.y;
    SPECULAR = 0.5;
}
"""
static func common_shader(culling: int) -> Shader:
	if not shaders.has(culling):
		var shader:=Shader.new();shader.code="shader_type spatial;\nrender_mode diffuse_burley, specular_schlick_ggx, "+("cull_back" if culling==BaseMaterial3D.CULL_BACK else "cull_disabled")+";\n"+PARAMETERS;shaders[culling]=shader
	return shaders[culling]

static func configure(sources: Array) -> void:
	var signature:=PackedInt64Array()
	for source: Mesh in sources: signature.append(source.get_instance_id())
	if signature==shared_signature: return
	shared_signature=signature;shared_texture=null;shared_materials={};shared_layers={};shared_size=Vector2i.ZERO;cache.clear()
	var textures: Array[Texture2D]=[]
	for source: Mesh in sources:
		for index in source.get_surface_count():
			var material:=source.surface_get_material(index)
			if material is StandardMaterial3D and material.albedo_texture!=null and not textures.has(material.albedo_texture): textures.append(material.albedo_texture)
	var images: Array[Image]=[];var hashes: Dictionary={}
	for texture: Texture2D in textures:
		if not (texture is ImageTexture or texture is CompressedTexture2D): continue
		var image:=texture.get_image()
		if image==null or image.is_compressed() or image.get_format() not in [Image.FORMAT_RGB8,Image.FORMAT_RGBA8]: continue
		if shared_size==Vector2i.ZERO:
			shared_size=image.get_size();shared_mipmaps=image.has_mipmaps()
			var white:=Image.create(shared_size.x,shared_size.y,shared_mipmaps,Image.FORMAT_RGBA8);white.fill(Color.WHITE);images.append(white);shared_layers[null]=0
		if image.get_size()!=shared_size or image.has_mipmaps()!=shared_mipmaps: continue
		image=image.duplicate();image.convert(Image.FORMAT_RGBA8)
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data());var key:=hash.finish().hex_encode()
		if not hashes.has(key):
			if images.size()>=256: shared_layers.clear();shared_size=Vector2i.ZERO;return
			hashes[key]=images.size();images.append(image)
		shared_layers[texture]=hashes[key]
	if images.is_empty(): return
	shared_texture=Texture2DArray.new()
	if shared_texture.create_from_images(images)!=OK: shared_texture=null;shared_layers.clear();return
	for culling in [BaseMaterial3D.CULL_BACK,BaseMaterial3D.CULL_DISABLED]:
		var material:=ShaderMaterial.new();material.shader=common_shader(culling);material.set_shader_parameter("surfaces",shared_texture);shared_materials[culling]=material
static func supported(material: Material, arrays: Array) -> bool:
	if not material is StandardMaterial3D: return false
	for value: float in [material.albedo_color.r,material.albedo_color.g,material.albedo_color.b]:
		if not is_finite(value) or value<0 or value>1 or absf(value-snappedf(value,1.0/255.0))>.000001: return false
	for channel in [Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_BONES,Mesh.ARRAY_WEIGHTS,Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3]:
		if arrays[channel]!=null and not arrays[channel].is_empty(): return false
	if arrays[Mesh.ARRAY_NORMAL]==null or arrays[Mesh.ARRAY_TEX_UV]==null: return false
	for property: Dictionary in defaults.get_property_list():
		var name: String=property.name
		if not (property.usage&PROPERTY_USAGE_STORAGE) or name in ["resource_name","resource_local_to_scene","albedo_color","albedo_texture","roughness","metallic","cull_mode"]: continue
		if material.get(name)!=defaults.get(name): return false
	return material.cull_mode in [BaseMaterial3D.CULL_BACK,BaseMaterial3D.CULL_DISABLED]
static func prepare(source: Mesh) -> Mesh:
	if cache.has(source): return cache[source]
	if not source is ArrayMesh or source.get_blend_shape_count()>0 or source.get_surface_count()<2 or source.shadow_mesh!=null: return source
	# Renderer reads can synchronize with the GPU. Keep only the bounds from
	# the existing LOD inspection; re-reading full buffers for bounds is wasteful.
	var surface_bounds:Array[AABB]=[]
	for index in source.get_surface_count():
		var data:=read_surface(source,index)
		if not data.get("lods",{}).is_empty(): return source
		surface_bounds.append(data.aabb)
	# Coincident one-/two-sided authored surfaces rely on the original material
	# ordering (for example the inner and outer fabric of a lamp shade). Shared
	# materials change renderer sorting, so keep that mesh's materials intact.
	for index in source.get_surface_count():
		var material:=source.surface_get_material(index)
		if not material is StandardMaterial3D: continue
		var bounds: AABB=surface_bounds[index]
		for other in range(index+1,source.get_surface_count()):
			var other_material:=source.surface_get_material(other)
			if not other_material is StandardMaterial3D or material.cull_mode==other_material.cull_mode: continue
			var other_bounds: AABB=surface_bounds[other]
			var overlap:=bounds.intersection(other_bounds).get_volume()
			if overlap>0 and overlap>=.9*maxf(bounds.get_volume(),other_bounds.get_volume()): return finish_mesh(source,source as ArrayMesh)
	var groups: Dictionary={};var retained: Array[int]=[]
	# These caches live for this synchronous preparation call only. No new
	# cross-call invalidation assumptions or persistent image copies are needed.
	var arrays_by_surface:Array[Array]=[];var source_images:Dictionary={}
	var width:=shared_size.x if shared_texture!=null else 0;var height:=shared_size.y if shared_texture!=null else 0;var mipmaps:=shared_mipmaps if shared_texture!=null else false
	# Preserve image resolution, UV wrapping and filtering instead of resampling.
	for index in source.get_surface_count():
		if width!=0: break
		var material: Material=source.surface_get_material(index)
		if material is StandardMaterial3D and material.albedo_texture!=null:
			var image: Image=source_image(material.albedo_texture,source_images)
			if image!=null and not image.is_compressed(): width=image.get_width();height=image.get_height();mipmaps=image.has_mipmaps();break
	if width==0: width=4;height=4
	for index in source.get_surface_count():
		var arrays:=source.surface_get_arrays(index);var material: Material=source.surface_get_material(index)
		arrays_by_surface.append(arrays)
		if source.surface_get_primitive_type(index)!=Mesh.PRIMITIVE_TRIANGLES or not supported(material,arrays): retained.append(index);continue
		var image: Image=source_image(material.albedo_texture,source_images)
		if material.albedo_texture!=null and (image==null or not (material.albedo_texture is ImageTexture or material.albedo_texture is CompressedTexture2D)): retained.append(index);continue
		if image!=null and (image.is_compressed() or image.get_width()!=width or image.get_height()!=height or image.has_mipmaps()!=mipmaps or image.get_format() not in [Image.FORMAT_RGB8,Image.FORMAT_RGBA8]): retained.append(index);continue
		var key: int=material.cull_mode
		if not groups.has(key): groups[key]=[]
		groups[key].append(index)
	var merge_count:=0
	for indices: Array in groups.values(): merge_count+=maxi(0,indices.size()-1)
	if merge_count==0: return finish_mesh(source,source as ArrayMesh,arrays_by_surface)
	var result:=ArrayMesh.new()
	var prepared_arrays:Array[Array]=[]
	for key: int in groups:
		var indices: Array=groups[key]
		if indices.size()==1: retained.append(indices[0]);continue
		var use_shared:=shared_texture!=null
		for surface: int in indices: use_shared=use_shared and shared_layers.has((source.surface_get_material(surface) as StandardMaterial3D).albedo_texture)
		var images: Array[Image]=[];var layers: Dictionary={}
		if use_shared: layers=shared_layers
		var group_arrays:Array=[];var tints:=PackedColorArray();var properties:=PackedVector2Array()
		for surface: int in indices:
			var arrays:=arrays_by_surface[surface];var material: StandardMaterial3D=source.surface_get_material(surface)
			var texture: Texture2D=material.albedo_texture
			if not layers.has(texture):
				var image: Image=source_image(texture,source_images).duplicate() if texture!=null else Image.create(width,height,mipmaps,Image.FORMAT_RGBA8)
				if texture==null: image.fill(Color.WHITE)
				else: image.convert(Image.FORMAT_RGBA8) # RGB8 -> RGBA8 adds opaque alpha, retaining RGB bytes.
				layers[texture]=images.size();images.append(image)
			if int(layers[texture])>=256: return finish_mesh(source,source as ArrayMesh,arrays_by_surface)
			var tint: Color=material.albedo_color;tint.a=float(layers[texture])/255.0
			group_arrays.append(arrays);tints.append(tint);properties.append(Vector2(material.roughness,material.metallic))
		var textures:=shared_texture if use_shared else Texture2DArray.new()
		if not use_shared and textures.create_from_images(images)!=OK: cache[source]=source;return source
		var arrays:Array=native.merge(group_arrays,tints,properties)
		if arrays.is_empty():return finish_mesh(source,source as ArrayMesh,arrays_by_surface)
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var pbr_material: ShaderMaterial=shared_materials[key] if use_shared else ShaderMaterial.new()
		if not use_shared: pbr_material.shader=common_shader(key);pbr_material.set_shader_parameter("surfaces",textures)
		result.surface_set_material(result.get_surface_count()-1,pbr_material)
	for index: int in retained:
		result.add_surface_from_arrays(source.surface_get_primitive_type(index),arrays_by_surface[index]);result.surface_set_material(result.get_surface_count()-1,source.surface_get_material(index))
	result.resource_name=source.resource_name;result.custom_aabb=source.custom_aabb
	return finish_mesh(source,result)

static func finish_mesh(source: Mesh,mesh: ArrayMesh,known_arrays:Array[Array]=[]) -> Mesh:
	# Godot's core mesh processor retains the full-detail surface and adds index
	# LODs. Work runs once during catalog preparation, never during player frames.
	if mesh!=source:
		for key: StringName in source.get_meta_list(): mesh.set_meta(key,source.get_meta(key))
	# Preserve the renderer's packed-normal roundtrip before native LODs. Read
	# a newly merged mesh once; reuse that exact array for validation and LODs.
	if known_arrays.is_empty():
		for index in mesh.get_surface_count():known_arrays.append(mesh.surface_get_arrays(index))
	for index in mesh.get_surface_count():
		var material:=mesh.surface_get_material(index)
		var arrays:=known_arrays[index]
		if (material is ShaderMaterial and not shaders.values().has(material.shader)) or (arrays[Mesh.ARRAY_BONES]!=null and not arrays[Mesh.ARRAY_BONES].is_empty()):
			cache[source]=mesh;return mesh
	var began:=Time.get_ticks_usec()
	var importer:=ImporterMesh.new()
	for index in mesh.get_surface_count():
		importer.add_surface(mesh.surface_get_primitive_type(index),known_arrays[index],[],{},mesh.surface_get_material(index),mesh.surface_get_name(index))
	importer.generate_lods(60,0,[])
	var result:=importer.get_mesh()
	result.resource_name=source.resource_name;result.custom_aabb=(source as ArrayMesh).custom_aabb
	for key: StringName in source.get_meta_list(): result.set_meta(key,source.get_meta(key))
	var levels:=0
	for index in importer.get_surface_count(): levels+=importer.get_surface_lod_count(index)
	result.set_meta("pack_lod_levels",levels)
	preparation_profile.lod_calls+=1;preparation_profile.lod_us+=Time.get_ticks_usec()-began
	cache[source]=result;return result
