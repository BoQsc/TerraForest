# SPDX-License-Identifier: 0BSD
extends SceneTree
var events: Array=[]
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var mode:="cold"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cache-expect="):mode=arg.trim_prefix("--cache-expect=")
	var game=load("res://demo/world.tscn").instantiate()
	game.terrain.lake_cache_result.connect(func(event: String,identity: String):
		if event!="disabled":events.append({"event":event,"identity":identity}))
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while (game.loading_active or game.lakes.statistics().ready!=4) and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active and game.lakes.statistics().ready==4,"four lakes become usable")
	var sampled:=0;var hashes: Array=[]
	var identity:=PackedByteArray();identity.resize(32)
	for item: Dictionary in game.lakes._lakes.values():
		if item.volume==null:continue
		sampled+=item.volume.statistics().sampled_nodes
		hashes.append(preload("res://addons/volumetric_terrain/derived_cache.gd").digest(item.volume.capture_bake(identity)).hex_encode())
	var hits:=events.filter(func(row):return row.event=="hit").size()
	var stores:=events.filter(func(row):return row.event=="stored").size()
	check((hits==4 and sampled==0) if mode=="warm" else (hits==3 and stores==1 and sampled>0) if mode=="corrupt" else (hits==0 and sampled>0),"expected "+mode+" cache path")
	var dir:="res://reports/lake_cache_world/";DirAccess.make_dir_recursive_absolute(dir)
	if mode!="cold":
		var baseline: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(dir+"cold.json"))
		check(hashes==baseline.hashes,"cached occupancy and shoreline match cold bake exactly")
	deadline=Time.get_ticks_msec()+10000
	while not game.terrain.derived_metrics.get("accounting_complete",false) and Time.get_ticks_msec()<deadline:await process_frame
	for frame in 30:await process_frame
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"world saves normally")
	var cache_path: String=game.terrain.backend.disk_cache.base_path.path_join(game.terrain.backend.disk_cache.signature).path_join("lakes_v1")
	var cached:=0
	for row: Dictionary in events:
		if row.event in ["miss","hit"] and FileAccess.file_exists(cache_path.path_join(row.identity+".trl")):cached+=1
	check(cached==4,"all four completed bakes stored")
	var report:={"failures":failures,"events":events,"hits":hits,"stores":stores,"sampled":sampled,"hashes":hashes,"cache_directory":ProjectSettings.globalize_path(game.terrain.backend.disk_cache.base_path.path_join(game.terrain.backend.disk_cache.signature).path_join("lakes_v1")),"scope":"Four saved generated lakes through actual world worker and persistence; no frame or thermal qualification."}
	var file:=FileAccess.open(dir+mode+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print(JSON.stringify(report));game.free();await process_frame;quit(1 if failures else 0)
