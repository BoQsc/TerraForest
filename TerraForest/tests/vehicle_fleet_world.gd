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
	var reopen: bool="--reopen-fleet" in OS.get_cmdline_user_args()
	if not slot.begins_with("fleet_world_test_") or not slot.is_valid_identifier():quit(2);return
	if FileAccess.file_exists("user://worlds/"+slot+".trw")!=reopen:quit(2);return
	var game=load("res://demo/world.tscn").instantiate()
	game.terrain.message_changed.connect(func(message: String):messages.append(message));root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"main world ready")
	game.set_physics_process(false);game._clear_motion()
	var session=game.world_vehicle
	DirAccess.make_dir_recursive_absolute("res://reports/vehicle_fleet_world")
	var path:="res://reports/vehicle_fleet_world/"+slot+".bin"
	var expected:=PackedByteArray()
	if not reopen:
		var pose:=Transform3D(Basis.IDENTITY,Vector3(800,60,1300))
		check(session.restore_snapshot(session.storage.encode(pose)),"legacy car migrates through actual world owner")
		check(session.fleet.spawn(Transform3D(Basis.IDENTITY,Vector3(1200,70,1300)))==2,"second parked vehicle receives stable identity")
		expected=session.capture_snapshot()
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(expected);file.close()
	else:
		expected=FileAccess.get_file_as_bytes(path)
		check(session.capture_snapshot()==expected,"fresh process restores both exact parked records")
	check(session.fleet.statistics().records==2 and session.car_identity==1,"two records retained with explicit single live slot")
	var old_car: int=session.car.get_instance_id()
	if not reopen:
		messages.clear();game.terrain.save_world();deadline=Time.get_ticks_msec()+20000
		while not messages.any(func(m):return m.begins_with("World saved and verified")) and Time.get_ticks_msec()<deadline:await process_frame
		check(messages.any(func(m):return m.begins_with("World saved and verified")),"manual world save verifies vehicle fleet component")
	var epoch: int=game.terrain.epoch
	game.terrain.reload_world();deadline=Time.get_ticks_msec()+30000
	while (not game.terrain.world_ready or game.terrain.epoch==epoch) and Time.get_ticks_msec()<deadline:await process_frame
	check(game.terrain.epoch>epoch and game.terrain.world_ready,"normal world reload completes")
	check(session.capture_snapshot()==expected,"normal reload preserves entire fleet archive")
	check(session.car.get_instance_id()==old_car and session.car.freeze,"reload reuses and parks live vehicle")
	check(session.fleet.get_record(2).pose.origin==Vector3(1200,70,1300),"uninstantiated parked vehicle survives reload")
	game.terrain.backend.disable_snapshot_writes();game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
