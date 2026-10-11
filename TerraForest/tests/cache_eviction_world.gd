# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var path: String=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--derived-cache="):path=arg.trim_prefix("--derived-cache=")
	if not path.begins_with("user://cache_eviction_world_") or not preload("res://addons/volumetric_terrain/derived_cache.gd")._safe_component(path.trim_prefix("user://")) or DirAccess.dir_exists_absolute(path):
		push_error("Pass --derived-cache=user://cache_eviction_world_UNIQUE with a new directory");quit(2);return
	# Seed two real obsolete-signature packets into this newly created test root.
	# Their combined size exceeds the quota, exercising actual startup reclamation.
	var old_dir: String=path.path_join("a".repeat(64)).path_join("b".repeat(64))
	DirAccess.make_dir_recursive_absolute(old_dir)
	var seeded_bytes:=0
	for name in ["0_0_256","0_256_256"]:
		var data:=FileAccess.get_file_as_bytes("res://addons/volumetric_terrain/base_cache/"+name+".trm")
		var head:=PackedByteArray();head.resize(8);head.encode_u32(0,0x36435254);head.encode_u32(4,data.size());head.append_array(preload("res://addons/volumetric_terrain/derived_cache.gd").digest(data))
		var seed_file:=FileAccess.open(old_dir.path_join(name+".trc"),FileAccess.WRITE);seed_file.store_buffer(head);seed_file.store_buffer(data);seed_file.close();seeded_bytes+=head.size()+data.size()
	check(seeded_bytes>2*1024*1024,"disposable obsolete cache exceeds declared 2MiB quota")
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	# Configure before worker start; the explicit command-line path overrides the facade default.
	game.terrain.backend.disk_cache.byte_limit=2*1024*1024
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"actual world becomes playable with 2MiB cache budget")
	game.set_physics_process(false);game._clear_motion()
	deadline=Time.get_ticks_msec()+20000
	while (game.terrain.derived_metrics.get("evictions",0)==0 or game.terrain.derived_metrics.get("writes",0)==0) and Time.get_ticks_msec()<deadline:await process_frame
	check(game.terrain.backend.cache_path==path,"worker uses required disposable cache path")
	var before: Dictionary=game.terrain.derived_metrics.duplicate(true)
	check(before.get("evictions",0)>0,"real worker performs idle cache eviction")
	check(before.get("lease_owned",false) and before.get("accounting_complete",false),"real worker retains exclusive ownership and valid accounting")
	check(before.get("disk_bytes",0)<=2*1024*1024 and before.get("writes",0)>0,"real generated mesh cache obeys small quota")
	var presentation: Dictionary=load("res://addons/presentation/fullscreen_policy.gd").measurement(root)
	check(presentation.fair_graphical_sample and Engine.max_fps==60,"fullscreen1080p cap60 configured")
	DirAccess.make_dir_recursive_absolute("res://reports/cache_eviction_world")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/cache_eviction_world/world.png")
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"temporary world shuts down cleanly")
	var final_stats: Dictionary=game.terrain.backend.disk_cache.counters()
	check(final_stats.write_failures==0 and final_stats.disk_bytes<=final_stats.byte_limit,"cache completes without write failures or quota overrun")
	var file:=FileAccess.open("res://reports/cache_eviction_world/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"before":before,"final":final_stats,"path":ProjectSettings.globalize_path(game.terrain.backend.disk_cache.base_path),"seeded_bytes":seeded_bytes,"presentation":presentation,"scope":"Actual world worker, generated geometry and small disposable cache quota. No manual save, no mining/frame-time/endurance qualification."},"  "));file.close()
	game.free();await process_frame;quit(1 if failures else 0)
