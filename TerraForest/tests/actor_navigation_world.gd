# SPDX-License-Identifier: 0BSD
# World wiring check. The obstacle/route movement contract has separate fixtures.
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	game.background_fps=60
	var deadline:=Time.get_ticks_msec()+20000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	game.set_physics_process(false);game._clear_motion()
	check(not game.loading_active and game.actors.pool!=null,"main world loads with actor navigation")
	if game.actors.pool!=null:
		var point: Vector3=game.terrain.focus+Vector3.UP*5
		var identity: int=game.actors.spawn(point)
		var handle: int=game.actors.store.resolve_identity(identity)
		game.actors.select_near(point)
		game.actors.orders.set_target(identity,point+Vector3.RIGHT*100)
		game.actors.pool.settle(1.0/60,func(_bounds: AABB):return true)
		check(game.actors.pool.navigation_status(handle).state=="search_limit","main-world pool enables bounded planner")
		game.structures.changed.emit()
		check(game.actors.pool.navigation_status(handle).state=="idle","structure edit signal invalidates native navigation")
		game.actors.pool.settle(1.0/60,func(_bounds: AABB):return true)
		game.terrain.region_changed.emit(AABB(point-Vector3.ONE,Vector3.ONE*2),0)
		check(game.actors.pool.navigation_status(handle).state=="idle","terrain publication invalidates native navigation")
		game.actors.pool.settle(1.0/60,func(_bounds: AABB):return true)
		game.lakes.exclusion_changed.emit(AABB(point-Vector3.ONE,Vector3.ONE*2))
		check(game.actors.pool.navigation_status(handle).state=="idle","lake change invalidates native navigation")
		game.actors.update_simulation(1.0/60,point,false,game._actor_collision_ready)
		check(game.actors.pool.active_handles().is_empty(),"main-world unavailability suspends navigation and collision")
	game.terrain.shutdown();game.free();await process_frame
	print("ACTOR_NAVIGATION_WORLD failures=",failures);quit(1 if failures else 0)
