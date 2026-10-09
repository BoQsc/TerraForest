# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func verify(game: Node,expected: Dictionary) -> void:
	check(game.ground_cover.removed.capture_storage_snapshot()==expected.ground,"ground edit state restores exactly")
	check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"plant grass and other inventory restores exactly")
	check(game.ground_cover.removed.contains(expected.natural_id),"removed natural identity remains absent")
	check(game.terrain.backend.world_seed==expected.seed,"saved seed owns restored edits")
func run() -> void:
	var slot:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-slot="): slot=arg.trim_prefix("--world-slot=")
	if not slot.begins_with("ground_world_test_") or not slot.is_valid_identifier(): quit(2);return
	var file:=FileAccess.open("res://reports/ground_cover/"+slot+".expected",FileAccess.READ)
	var expected: Dictionary=file.get_var();file.close()
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active and game.terrain.world_ready,"fresh process restores main world")
	game.set_physics_process(false);game._clear_motion()
	verify(game,expected)
	if game.ground_enabled:
		game.camera.global_position=expected.target+Vector3(0.7,1.5,1)
		game.camera.look_at(expected.target+Vector3(0,0.2,0))
		deadline=Time.get_ticks_msec()+15000
		while game.ground_cover.resident.size()<49 and Time.get_ticks_msec()<deadline: await process_frame
		check(game.ground_cover.resident.size()==49,"saved area repopulates bounded residency")
		check(not game.ground_cover.batches[expected.species].get_ids().has(expected.natural_id),"removed natural object is not recreated by streaming")
		check(game.ground_cover.batches[expected.species].get_ids().has(4294967296),"saved authored replacement renders with same identity")
	else:
		check(game.ground_cover.resident.is_empty(),"disabled rendering keeps generated records unloaded")
	var old_epoch: int=game.terrain.epoch
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var key:=InputEventKey.new();key.pressed=true;key.physical_keycode=KEY_F9
	game._unhandled_input(key)
	deadline=Time.get_ticks_msec()+60000
	while (game.terrain.epoch==old_epoch or not game.terrain.world_ready or game.loading_active) and Time.get_ticks_msec()<deadline: await process_frame
	check(game.terrain.epoch>old_epoch and game.terrain.world_ready,"normal F9 reload completes")
	verify(game,expected)
	var saved: Array=[]
	game.terrain.save_completed.connect(func(ok: bool):saved.append(ok))
	game.terrain.save_world();deadline=Time.get_ticks_msec()+15000
	while saved.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(not saved.is_empty() and saved[0],"normal save retains registered edits whether rendering is enabled or disabled")
	check(load("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"reopen and reload run at fullscreen 1080p with 60 FPS cap")
	game.shutdown_requested=true
	await game.terrain.shutdown_after_edits();game.free()
	for frame in range(2): await process_frame
	print("GROUND_COVER_WORLD_REOPEN ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
