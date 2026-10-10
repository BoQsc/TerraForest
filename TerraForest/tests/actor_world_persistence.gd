# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var messages: Array[String]=[]
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var slot:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
	var reopen: bool="--reopen-actors" in OS.get_cmdline_user_args()
	if not slot.begins_with("actor_world_test_") or not slot.is_valid_identifier():quit(2);return
	if FileAccess.file_exists("user://worlds/"+slot+".trw")!=reopen:quit(2);return
	var game=load("res://demo/world.tscn").instantiate()
	game.terrain.message_changed.connect(func(message: String):messages.append(message));root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"main world ready")
	game.set_physics_process(false);game._clear_motion()
	var actors=game.actors
	check(actors.pool==null and actors.renderer==null,"disabled simulation creates no collision pool or renderer")
	DirAccess.make_dir_recursive_absolute("res://reports/actor_world_persistence")
	var path:="res://reports/actor_world_persistence/"+slot+".bin"
	var expected:=PackedByteArray()
	if not reopen:
		check(actors.spawn(Vector3(800,50,1300))>0 and actors.spawn(Vector3(802,50,1300))>0,"author two persistent actors")
		expected=actors.store.capture_storage_snapshot()
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(expected);file.close()
	else:
		expected=FileAccess.get_file_as_bytes(path)
		check(actors.store.capture_storage_snapshot()==expected,"fresh process restores exact actors while simulation disabled")
	check(actors.enable(4) and actors.select_near(Vector3(800,50,1300)).active==2,"explicit activation binds restored records")
	var before: PackedInt64Array=actors.pool.active_handles()
	if not reopen:
		messages.clear();game.terrain.save_world();deadline=Time.get_ticks_msec()+20000
		while not messages.any(func(m):return m.begins_with("World saved and verified")) and Time.get_ticks_msec()<deadline:await process_frame
		check(messages.any(func(m):return m.begins_with("World saved and verified")),"manual world save verifies actor component")
	var epoch: int=game.terrain.epoch
	game.terrain.reload_world();deadline=Time.get_ticks_msec()+30000
	while (not game.terrain.world_ready or game.terrain.epoch==epoch) and Time.get_ticks_msec()<deadline:await process_frame
	check(game.terrain.epoch>epoch and game.terrain.world_ready,"normal world reload completes")
	check(actors.pool.active_handles().is_empty() and actors.renderer.multimesh.visible_instance_count==0,"reload retires old proxies and visible instances")
	check(actors.store.capture_storage_snapshot()==expected and not actors.store.contains(before[0]),"reload preserves records and invalidates old handles")
	check(actors.select_near(Vector3(800,50,1300)).active==2,"pool reactivates new handles after reload")
	game.terrain.backend.disable_snapshot_writes();game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
