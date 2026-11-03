# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline 128px tiles; one shared GPU texture and cached regions, no live viewports.
const KEYS=["1","2","3","4","101","102","103","104","201","202","203","204","205","206","207","208","209","210","301","302","303","Metal beam","Floor panel","Doorway","Wooden table","Wooden chair","Wooden shelf","Wooden ladder","Wooden storage chest (E open)","211","Wood framed window","Wooden door (E open / close)","Metal guardrail","Wooden fence","212","501","5","6","214","215","216","217","218","219","304","305","306"]
const SALVAGE={"224":preload("res://addons/player_runtime/art/salvage/224.svg"),"225":preload("res://addons/player_runtime/art/salvage/225.svg"),"226":preload("res://addons/player_runtime/art/salvage/226.svg"),"227":preload("res://addons/player_runtime/art/salvage/227.svg")}
static var atlas: ImageTexture
static var regions: Dictionary={}
static var bucket_icon:ImageTexture
static func texture(key: Variant) -> Texture2D:
	if SALVAGE.has(str(key)):return SALVAGE[str(key)]
	if str(key)=="8":return preload("res://addons/player_runtime/art/ranger.svg")
	if str(key)=="223":return preload("res://addons/player_runtime/art/ranger_cartridges.svg")
	if str(key)=="7":return preload("res://addons/player_runtime/art/carbine.svg")
	if str(key)=="221":return preload("res://addons/player_runtime/art/cartridge.svg")
	if str(key)=="222":return preload("res://addons/player_runtime/art/explosive_barrel.svg")
	if str(key)=="220":return preload("res://addons/player_runtime/art/coal.svg")
	if str(key) in preload("res://addons/structures/mine_rail_catalog.gd").PARTS.values():return preload("res://addons/player_runtime/art/mine_rail.svg")
	if str(key)=="213":return preload("res://addons/player_runtime/art/lockpick.svg")
	if str(key)=="601":return preload("res://addons/player_runtime/art/coins.svg")
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
