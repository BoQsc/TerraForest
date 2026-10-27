extends RefCounted

const Catalog=preload("res://addons/structures/shape_catalog.gd")
const ATLAS="res://addons/player_runtime/art/shape_icons.trtex"
const TILE=128
const COLUMNS=6
static var atlas:ImageTexture
static var regions:Dictionary={}

static func texture(shape:int)->Texture2D:
	if shape<1 or shape>Catalog.NAMES.size():return null
	if regions.has(shape):return regions[shape]
	if atlas==null:
		var pixels:=Image.new()
		if pixels.load_png_from_buffer(FileAccess.get_file_as_bytes(ATLAS))!=OK:return null
		atlas=ImageTexture.create_from_image(pixels)
	var tile:=AtlasTexture.new();tile.atlas=atlas;tile.region=Rect2(((shape-1)%COLUMNS)*TILE,((shape-1)/COLUMNS)*TILE,TILE,TILE);tile.filter_clip=true
	regions[shape]=tile;return tile
