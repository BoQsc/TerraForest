# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var library=preload("res://addons/structures/prefab_library.gd").new()
	library.directory="user://frontage_async_%d" % Time.get_ticks_usec()
	var source=ClassDB.instantiate("NativeBlockPrefab")
	var cottage=load("res://addons/structures/prefabs/brick_cottage.tres")
	source.configure(cottage.get_records())
	var start:=Time.get_ticks_usec()
	check(library.begin_frontage(source,64,8,3,1703,"Large frontage").ok,"maximum frontage worker admitted")
	var submit_us:=Time.get_ticks_usec()-start
	check(not library.begin_frontage(source,1,8,3,1703,"Duplicate").ok,"outstanding work cannot be replaced")
	source.configure(PackedInt32Array([0,0,0,1]))
	var result: Dictionary={};var max_poll_us:=0;var frames:=0
	var deadline:=Time.get_ticks_msec()+10000
	while result.is_empty() and Time.get_ticks_msec()<deadline:
		start=Time.get_ticks_usec();result=library.poll_frontage();max_poll_us=maxi(max_poll_us,Time.get_ticks_usec()-start)
		frames+=1;await process_frame
	check(not result.is_empty() and result.get("ok",false),"worker completes and persists result")
	if result.get("ok",false):
		check(result.asset.get_cell_count()==128*468,"editing source during generation does not alter captured layout")
		var expected=ClassDB.instantiate("NativeBlockPrefab");expected.compose_frontage([cottage],64,8,3,1703)
		check(expected.get_records()==result.asset.get_records(),"asynchronous geometry matches deterministic native reference")
		check(library.poll_frontage().is_empty(),"result consumed exactly once")
		DirAccess.remove_absolute(result.path)
	check(library.begin_frontage(source,64,8,3,1703,"Discarded").ok,"next job admitted after consumption")
	library.shutdown_frontage()
	check(library.poll_frontage().is_empty() and library.assets.size()==1 and DirAccess.get_files_at(library.directory).is_empty(),"shutdown drains and removes unpublished asset file")
	DirAccess.remove_absolute(library.directory)
	print("FRONTAGE_ASYNC ",{"submit_us":submit_us,"max_poll_and_save_us":max_poll_us,"frames":frames})
	quit(1 if failures else 0)
