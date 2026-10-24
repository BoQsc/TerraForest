# SPDX-License-Identifier: 0BSD
extends RefCounted
## Authoring/build dependency receipt. Never loaded by the packaged game UI.
const Icons=preload("res://addons/player_runtime/item_icons.gd")
const ATLAS="res://addons/player_runtime/art/item_icons.trtex"
const RECEIPT="res://addons/player_runtime/art/item_icons.bake.json"
const GROUPS={"tools":["1","2"],"vehicle":["501"]}
const ROOTS={"tools":["res://addons/player_runtime/tool_view.gd"],"vehicle":["res://vehicle_demo/scenes/car.tscn"]}
const RECIPE=["res://tests/bake_item_icons.gd","res://addons/player_runtime/item_icons.gd","res://tools/item_icon_cache.gd","res://project.godot"]

static func collect(path:String,files:Dictionary)->void:
	path=path.simplify_path()
	if not path.begins_with("res://") or path.begins_with("res://.godot/") or path.begins_with("res://reports/") or path in [ATLAS,RECEIPT] or path.ends_with("/") or files.has(path) or DirAccess.dir_exists_absolute(path):return
	files[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"
	if files[path]=="missing":return
	if FileAccess.file_exists(path+".import"):collect(path+".import",files)
	var extension:=path.get_extension()
	if extension in ["gd","tscn","tres","res","glb","gltf","gdshader","gdextension"]:
		for dependency:String in ResourceLoader.get_dependencies(path):
			collect(dependency.get_slice("::",2) if dependency.contains("::") else dependency,files)
	if extension in ["gd","tscn","tres","gltf","gdshader","gdshaderinc","gdextension","import"]:
		var refs:=RegEx.new();refs.compile("res://[^\\\"'\\s)\\]]+")
		for reference:RegExMatch in refs.search_all(FileAccess.get_file_as_string(path)):collect(reference.get_string(),files)
	if extension=="glb":
		# Embedded bytes are covered by the GLB hash; follow external image/buffer URIs.
		var file:=FileAccess.open(path,FileAccess.READ)
		if file==null or file.get_length()<20 or file.get_32()!=0x46546c67:return
		file.get_32();file.get_32()
		var length:=file.get_32();var kind:=file.get_32()
		if kind!=0x4e4f534a or length>file.get_length()-20:return
		var document=JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
		if document is Dictionary:
			for list:String in ["images","buffers"]:
				for entry:Dictionary in document.get(list,[]):
					var uri:String=entry.get("uri","")
					if not uri.is_empty() and not uri.begins_with("data:"):collect(path.get_base_dir().path_join(uri.uri_decode()),files)

static func snapshot()->Dictionary:
	var recipe:Dictionary={}
	for path:String in RECIPE:recipe[path]=FileAccess.get_sha256(path)
	var state:Dictionary={}
	for group:String in GROUPS:
		var files:Dictionary={}
		for path:String in ROOTS[group]:collect(path,files)
		state[group]={"engine":Engine.get_version_info().string,"recipe":recipe,"files":files}
	return state

static func receipt()->Dictionary:
	if not FileAccess.file_exists(RECEIPT):return {}
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(RECEIPT))
	return parsed if parsed is Dictionary and parsed.get("sources") is Dictionary else {}

static func plan(state:Dictionary)->Dictionary:
	var image:=Image.new()
	var valid:=FileAccess.file_exists(ATLAS) and image.load_png_from_buffer(FileAccess.get_file_as_bytes(ATLAS))==OK and image.get_size()==Vector2i(1024,ceili(Icons.KEYS.size()/8.0)*128)
	if not valid:return {"ids":Icons.KEYS,"full":true,"reason":"missing or invalid atlas"}
	var saved:=receipt();var ids:Array=[]
	var output_changed:bool=saved.get("schema",0)!=1 or saved.get("atlas_sha256","")!=FileAccess.get_sha256(ATLAS)
	for group:String in GROUPS:
		if output_changed or saved.get("sources",{}).get(group,{})!=state[group]:ids.append_array(GROUPS[group])
	return {"ids":ids,"full":false,"reason":"changed model/material/recipe or output" if not ids.is_empty() else "current"}

static func publish(image:Image,state:Dictionary,baked:Array)->Error:
	# Never label a bake current if an author changed its inputs during rendering.
	if state!=snapshot():push_error("Icon inputs changed while baking; retry the launch/build");return ERR_BUSY
	var temporary:=ATLAS+".tmp"
	var error:=image.save_png(temporary)
	if error!=OK:return error
	error=DirAccess.rename_absolute(temporary,ATLAS)
	if error!=OK:return error
	var saved:=receipt();var sources:Dictionary=saved.get("sources",{})
	for group:String in GROUPS:
		var complete:=true
		for id:String in GROUPS[group]:
			if id not in baked:complete=false
		if complete:sources[group]=state[group]
	var output:=FileAccess.open(RECEIPT+".tmp",FileAccess.WRITE)
	if output==null:return FileAccess.get_open_error()
	output.store_string(JSON.stringify({"schema":1,"atlas_sha256":FileAccess.get_sha256(ATLAS),"sources":sources},"  ")+"\n")
	output.close()
	return DirAccess.rename_absolute(RECEIPT+".tmp",RECEIPT)
