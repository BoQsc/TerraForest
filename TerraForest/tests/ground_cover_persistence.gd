# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var saved:=false
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	var slot:=""
	var reading:=false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--slot="): slot=arg.trim_prefix("--slot=")
		if arg=="--read": reading=true
	if not slot.begins_with("ground_edits_test_") or not slot.is_valid_identifier(): quit(2);return
	var terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true
	terrain.backend.disk_cache.enabled=false;terrain.backend.world_generator=3;terrain.backend.world_seed=1703
	root.add_child(terrain)
	var cover=load("res://addons/world_ecosystem/ground_cover.gd").new()
	var persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	check(cover.prepare(persistence) and persistence.attach(terrain)==OK,"ground-cover edit provider attaches to real terrain archive")
	terrain.save_completed.connect(func(success: bool): saved=success)
	check(terrain.start(StandardMaterial3D.new(),false)==OK,"terrain worker starts")
	var deadline:=Time.get_ticks_msec()+30000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(terrain.world_ready,"world archive restore completes")
	if terrain.world_ready:
		var state: RefCounted=cover.removed
		check(state.bind_world(1703,1),"restored generation profile matches world")
		if reading:
			var expected:=FileAccess.get_file_as_bytes("res://reports/ground_cover/"+slot+".bin")
			check(not expected.is_empty() and expected==state.capture_storage_snapshot(),"new process restores exact profile removals placements and ID sequence")
			check(state.contains(12) and not state.contains(13),"individual natural removal survives disk archive")
			check(state.query(Vector2i(30,30))[0].ids==PackedInt64Array([4294967296]),"authored stone survives fresh-process restore")
			check(state.add(2,Transform3D(Basis.IDENTITY,Vector3(980,30,980)))==4294967297,"next authored identity survives restore")
		else:
			check(state.mark(12) and state.add(0,Transform3D(Basis.IDENTITY,Vector3(970,30,970)))==4294967296,"removal and placement enter registered state")
			DirAccess.make_dir_recursive_absolute("res://reports/ground_cover")
			var file:=FileAccess.open("res://reports/ground_cover/"+slot+".bin",FileAccess.WRITE)
			file.store_buffer(state.capture_storage_snapshot());file.close()
			terrain.changed_since_save=true;terrain.save_world()
			deadline=Time.get_ticks_msec()+15000
			while not saved and Time.get_ticks_msec()<deadline: await process_frame
			check(saved,"manual save publishes verified terrain and ground-cover archive")
	# Shutdown cannot create the archive whose restoration is being tested.
	terrain.backend.disable_snapshot_writes();terrain.shutdown()
	terrain.free();cover.free();persistence=null
	print("GROUND_COVER_PERSISTENCE ","read" if reading else "write"," failures=",failures)
	quit(1 if failures else 0)
