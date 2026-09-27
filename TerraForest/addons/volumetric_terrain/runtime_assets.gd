# SPDX-License-Identifier: 0BSD
# Direct file loading: launch a fresh extracted project without an editor import.
# Uses only built-in Godot Image/Shader APIs. Mipmaps are still generated in full.
extends RefCounted

const TEXTURE_PATHS: Dictionary = {
	"grass": "res://addons/volumetric_terrain/terrain_textures/grass_albedo.trtex",
	"gravel": "res://addons/volumetric_terrain/terrain_textures/gravel_albedo.trtex",
	"sand": "res://addons/volumetric_terrain/terrain_textures/sand_albedo.trtex",
	"snow": "res://addons/volumetric_terrain/terrain_textures/snow_albedo.trtex",
}

static func load_terrain_shader() -> Shader:
	var path: String = "res://addons/volumetric_terrain/terrain.gdshader"
	if not FileAccess.file_exists(path):
		push_error("Missing terrain shader: " + path)
		return null
	var code: String = FileAccess.get_file_as_string(path)
	if code.is_empty():
		push_error("Terrain shader is empty or unreadable: " + path)
		return null
	var shader := Shader.new()
	shader.code = code
	return shader

static func load_terrain_image(path: String) -> Image:
	var image := Image.new()
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.size() < 8:
		push_error("Missing/empty raw terrain texture: " + path)
		return null
	# .trtex stores the original PNG/JPEG bytes and is explicitly included in
	# export_presets.cfg. This works both in a fresh ZIP and an exported PCK;
	# Image.load(res://addons/volumetric_terrain/*.png) emits the export/import warning seen in v0.4.3.
	var error: Error = ERR_FILE_UNRECOGNIZED
	if bytes[0] == 137 and bytes[1] == 80 and bytes[2] == 78 and bytes[3] == 71:
		error = image.load_png_from_buffer(bytes)
	elif bytes[0] == 255 and bytes[1] == 216:
		error = image.load_jpg_from_buffer(bytes)
	if error != OK or image.is_empty():
		push_error("Cannot decode terrain texture %s (error %d). Extract the complete ZIP." % [path, error])
		return null
	image.convert(Image.FORMAT_RGBA8)
	if not image.has_mipmaps():
		error = image.generate_mipmaps()
		if error != OK:
			push_error("Cannot generate mipmaps for %s (error %d)." % [path, error])
			return null
	return image

static func make_terrain_material() -> ShaderMaterial:
	var shader: Shader = load_terrain_shader()
	if shader == null:
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	for key: String in TEXTURE_PATHS:
		var path: String = TEXTURE_PATHS[key]
		var image: Image = load_terrain_image(path)
		if image == null:
			return null
		var texture: ImageTexture = ImageTexture.create_from_image(image)
		if texture == null:
			push_error("Cannot create terrain texture: " + path)
			return null
		material.set_shader_parameter(key, texture)
	return material
