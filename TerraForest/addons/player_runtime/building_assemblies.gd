# SPDX-License-Identifier: 0BSD
extends RefCounted
static var atlas:ImageTexture
static var regions:Dictionary={}
static func texture(shape:int)->Texture2D:
	if shape<19:return null
	var index:=0 if shape<=23 else (1 if shape<=25 else (2 if shape<=27 else (3 if shape<=31 else 4)))
	if atlas==null:
		var pixels:=Image.new()
		if pixels.load_png_from_buffer(FileAccess.get_file_as_bytes("res://addons/player_runtime/art/building_assemblies.trtex"))!=OK:return null
		atlas=ImageTexture.create_from_image(pixels)
	if not regions.has(index):
		var region:=AtlasTexture.new();region.atlas=atlas;region.region=Rect2(index*256,0,256,160);region.filter_clip=true;regions[index]=region
	return regions[index]
