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
	print("SCENE_STARTUP ",JSON.stringify(game.terrain.backend.startup_diagnostics()))
	# Inspect cache state only after startup publication. The cache belongs to
	# the worker; use counters delivered by terrain instead of reading it here.
	print("SCENE_CACHE ",JSON.stringify(game.terrain.derived_metrics))
	check(game.world_vehicle._scene_requested,"unused vehicle scene has an outstanding preload")
	game.terrain.changed_since_save=false
	var supply: int=game.pickups.spawn(102,Vector3(800,100,1310))
	check(supply>0 and game.terrain.changed_since_save,"actual world marks supply placement for autosave")
	game.terrain.changed_since_save=false
	var collected: Dictionary=game.pickups.collect_near(Vector3(800,100,1310),game.player_hud.inventory,func(_point: Vector3): return true)
	check(collected.ok and game.terrain.changed_since_save,"actual world marks collection for autosave")
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
	print("SCENE_LIFETIME ",JSON.stringify({"checks":6,"failures":failures}))
	quit(1 if failures else 0)
