# SPDX-License-Identifier: 0BSD
extends SceneTree
const OUTPUT:="res://addons/player_runtime/assets/debris_geometry.res"
const RECEIPT:="res://addons/player_runtime/assets/debris_geometry.bake.json"
const SOURCES:=["res://tools/bake_debris_geometry.gd","res://addons/structures/native/block_world.cpp","res://addons/structures/native/block_world.hpp","res://addons/structures/native/block_shapes.hpp","res://addons/structures/native/block_word.hpp","res://addons/structures/native/modular_shapes.hpp","res://addons/structures/native/modular_mesher.hpp"]
func _initialize()->void:run.call_deferred()
func run()->void:
	var sources:Dictionary={}
	for path:String in SOURCES:
		sources[path]=FileAccess.get_sha256(path)
		if sources[path].is_empty():push_error("Missing debris geometry source: "+path);quit(1);return
	var engine:String=Engine.get_version_info().string
	var previous:Variant=JSON.parse_string(FileAccess.get_file_as_string(RECEIPT)) if FileAccess.file_exists(RECEIPT) else null
	if previous is Dictionary and previous.get("sources")==sources and previous.get("engine")==engine and previous.get("output_sha256")==FileAccess.get_sha256(OUTPUT):
		print("DEBRIS_GEOMETRY_BAKE current");quit();return
	if "--check-only" in OS.get_cmdline_user_args():push_error("Debris geometry bake is stale");quit(1);return
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld")
	var shapes:Dictionary={}
	for shape in range(1,65):
		if blocks.encode_block(shape,0,0)<0:break
		for rotation in range(24):
			var mesh:Mesh=blocks.preview_mesh(shape,rotation)
			if mesh==null:continue
			var convex:=mesh.create_convex_shape(true,true)
			if convex==null or convex.points.size()<4:push_error("Debris convex bake failed");blocks.free();quit(1);return
			shapes[Vector2i(shape,rotation)]=convex
		print("DEBRIS_GEOMETRY_BAKE shape=",shape," total=",shapes.size())
	blocks.free()
	var bundle:=Resource.new();bundle.set_meta("shapes",shapes)
	var pending:=OUTPUT.trim_suffix(".res")+".pending.res"
	if ResourceSaver.save(bundle,pending,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
	if DirAccess.rename_absolute(pending,OUTPUT)!=OK:quit(1);return
	var receipt:Dictionary={"schema":1,"engine":engine,"sources":sources,"output_sha256":FileAccess.get_sha256(OUTPUT),"shapes":shapes.size(),"recipe":"Same preview_mesh(shape,rotation).create_convex_shape(true,true) as legacy physical debris, evaluated offline. Original derived asset: CC0-1.0."}
	var file:=FileAccess.open(RECEIPT+".pending",FileAccess.WRITE);file.store_string(JSON.stringify(receipt,"  ")+"\n");file.close()
	if DirAccess.rename_absolute(RECEIPT+".pending",RECEIPT)!=OK:quit(1);return
	print("DEBRIS_GEOMETRY_BAKE complete shapes=",shapes.size());quit()
