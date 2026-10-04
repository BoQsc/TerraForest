# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	root.add_child(game)
	var deadline=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active and game.terrain.world_ready,"main scene finishes loading")
	check(game.world_vehicle._scene_requested,"unused vehicle scene has an outstanding preload")
	game.shutdown_requested=true
	check(await game.terrain.shutdown_after_edits(),"terrain drains on shutdown")
	# Keep the child briefly to verify exit consumes the request. Also inspect
	# the verbose process log for leaked objects after the final script print.
	var vehicle=game.world_vehicle
	game.remove_child(vehicle)
	check(not vehicle._scene_requested,"unused vehicle preload consumed on exit")
	vehicle.free()
	game.free()
	for frame in range(2): await process_frame
	print("SCENE_LIFETIME ",JSON.stringify({"checks":4,"failures":failures}))
	quit(1 if failures else 0)
