# SPDX-License-Identifier: 0BSD
extends SceneTree
const OUTPUT:="res://addons/characters/runtime/assets/Zombie.geometry.res"
const RECEIPT:="res://addons/characters/runtime/assets/Zombie.geometry.bake.json"
const GeometryData=preload("res://addons/characters/runtime/zombie_geometry_data.gd")
const SOURCES:=["res://tools/bake_zombie_geometry.gd","res://addons/characters/runtime/zombie_geometry_data.gd","res://addons/characters/runtime/zombie.gd","res://addons/characters/runtime/assets/Zombie.r4.glb","res://addons/characters/runtime/assets/Zombie.r4.glb.import","res://addons/world_runtime/native/zombie_anatomy.cpp","res://addons/world_runtime/native/zombie_anatomy.hpp","res://addons/world_runtime/native/zombie_geometry.cpp"]
func _initialize()->void:run.call_deferred()
func run()->void:
	var sources:Dictionary={}
	for path:String in SOURCES:
		sources[path]=FileAccess.get_sha256(path)
		if sources[path].is_empty():push_error("Missing zombie geometry source: "+path);quit(1);return
	var engine:String=Engine.get_version_info().string
	var previous:Variant=JSON.parse_string(FileAccess.get_file_as_string(RECEIPT)) if FileAccess.file_exists(RECEIPT) else null
	if previous is Dictionary and previous.get("sources")==sources and previous.get("engine")==engine and previous.get("output_sha256")==FileAccess.get_sha256(OUTPUT):
		print("ZOMBIE_GEOMETRY_BAKE current");quit();return
	if "--check-only" in OS.get_cmdline_user_args():push_error("Zombie geometry bake is stale");quit(1);return
	var Zombie=load("res://addons/characters/runtime/zombie.gd")
	var zombie:Node3D=Zombie.new()
	zombie.geometry_source=null
	zombie.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(zombie)
	if not zombie.initialized:push_error("Zombie reference anatomy failed");zombie.free();quit(1);return
	var bundle:=GeometryData.new()
	bundle.source_model=Zombie.DEFAULT_MODEL
	bundle.data=zombie.anatomy.capture_geometry_data()
	var stats:Dictionary=zombie.anatomy.geometry_stats()
	zombie.free()
	if bundle.data.is_empty():push_error("Zombie geometry data unavailable");quit(1);return
	var pending:=OUTPUT.trim_suffix(".res")+".pending.res"
	if ResourceSaver.save(bundle,pending,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
	if DirAccess.rename_absolute(pending,OUTPUT)!=OK:quit(1);return
	var receipt:Dictionary={"schema":1,"engine":engine,"sources":sources,"output_sha256":FileAccess.get_sha256(OUTPUT),"vertices":stats.vertices,"parts":14,"recipe":"Exact existing R4 raw vertices, triangle indices, skin weights and morph arrays from native anatomy; no simplification or collision change. Derived data retains inherited character provenance GAP-002; original preparation code is 0BSD."}
	var file:=FileAccess.open(RECEIPT+".pending",FileAccess.WRITE);file.store_string(JSON.stringify(receipt,"  ")+"\n");file.close()
	if DirAccess.rename_absolute(RECEIPT+".pending",RECEIPT)!=OK:quit(1);return
	print("ZOMBIE_GEOMETRY_BAKE complete vertices=",stats.vertices);quit()
