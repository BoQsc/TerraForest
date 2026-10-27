extends RefCounted

const Icons=preload("res://addons/player_runtime/shape_icons.gd")
const RECEIPT="res://addons/player_runtime/art/shape_icons.bake.json"
const SOURCES=["res://addons/structures/shape_catalog.gd","res://addons/structures/native/block_shapes.hpp","res://addons/structures/native/modular_shapes.hpp","res://addons/structures/native/block_world.cpp","res://addons/structures/bin/structures.windows.template_debug.x86_64.dll","res://addons/player_runtime/shape_icons.gd","res://tools/bake_shape_icons.gd","res://tools/shape_icon_cache.gd"]

static func snapshot()->Dictionary:
	var state:Dictionary={}
	for path:String in SOURCES:state[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	state["engine"]=Engine.get_version_info().string
	return state

static func current(state:Dictionary)->bool:
	if not FileAccess.file_exists(RECEIPT) or not FileAccess.file_exists(Icons.ATLAS):return false
	var saved=JSON.parse_string(FileAccess.get_file_as_string(RECEIPT))
	if not saved is Dictionary or saved.get("sources",{})!=state or saved.get("atlas_sha256","")!=FileAccess.get_sha256(Icons.ATLAS):return false
	var pixels:=Image.new()
	return pixels.load_png_from_buffer(FileAccess.get_file_as_bytes(Icons.ATLAS))==OK and pixels.get_size()==Vector2i(Icons.COLUMNS*Icons.TILE,ceili(Icons.Catalog.NAMES.size()/float(Icons.COLUMNS))*Icons.TILE)

static func publish(pixels:Image,state:Dictionary)->Error:
	if state!=snapshot():return ERR_BUSY
	var error:=pixels.save_png(Icons.ATLAS+".tmp")
	if error!=OK:return error
	error=DirAccess.rename_absolute(Icons.ATLAS+".tmp",Icons.ATLAS)
	if error!=OK:return error
	var file:=FileAccess.open(RECEIPT+".tmp",FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"sources":state,"atlas_sha256":FileAccess.get_sha256(Icons.ATLAS)},"  ")+"\n");file.close()
	return DirAccess.rename_absolute(RECEIPT+".tmp",RECEIPT)
