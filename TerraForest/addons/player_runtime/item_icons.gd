# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline 128px tiles; one shared GPU texture and cached regions, no live viewports.
const KEYS=["1","2","3","4","101","102","103","104","201","202","203","204","205","206","207","208","209","210","301","302","303","Metal beam","Floor panel","Doorway","Wooden table","Wooden chair","Wooden shelf","Wooden ladder","Wooden storage chest (E open)","211"]
static var atlas: ImageTexture
static var regions: Dictionary={}
static var bucket_icon:ImageTexture
static func texture(key: Variant) -> Texture2D:
	if str(key).is_valid_int() and int(key)>=401 and int(key)<=411:
		if bucket_icon==null:
			var image:=Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://addons/volumetric_water/bucket_icon.trtex"))!=OK:return null
			bucket_icon=ImageTexture.create_from_image(image)
		return bucket_icon
	var name:=str(key)
	var index:=KEYS.find(name)
	if index<0:return null
	if regions.has(name):return regions[name]
	if atlas==null:
		var image:=Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes("res://addons/player_runtime/art/item_icons.trtex"))!=OK:return null
		atlas=ImageTexture.create_from_image(image)
	var tile:=AtlasTexture.new();tile.atlas=atlas;tile.region=Rect2((index%8)*128,(index/8)*128,128,128);tile.filter_clip=true
	regions[name]=tile
	return tile
