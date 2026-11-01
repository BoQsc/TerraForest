# SPDX-License-Identifier: 0BSD
extends RefCounted
## One lazily loaded sheet (384 KiB); no runtime tile viewports.
static var selected:=-1
static var sheet:ImageTexture
static var regions:Dictionary={}
static func texture(shape:int,rotation:int)->Texture2D:
	if selected!=shape:
		var pixels:=Image.new()
		if pixels.load_png_from_buffer(FileAccess.get_file_as_bytes("res://addons/player_runtime/art/shape_orientations/shape_%02d.trtex"%shape))!=OK:return null
		sheet=ImageTexture.create_from_image(pixels);selected=shape;regions.clear()
	if not regions.has(rotation):
		var region:=AtlasTexture.new();region.atlas=sheet;region.region=Rect2((rotation%6)*64,(rotation/6)*64,64,64);region.filter_clip=true;regions[rotation]=region
	return regions[rotation]
