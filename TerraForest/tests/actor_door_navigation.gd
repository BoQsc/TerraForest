# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var focus: Vector3
var handle: int
var peak_work:=0
func advance(seconds: float,until_arrived: bool=false) -> void:
	var delta:=1.0/Engine.physics_ticks_per_second
	for tick in int(seconds/delta):
		await physics_frame
		game.actors.update_simulation(delta,focus,true,game._actor_collision_ready)
		peak_work=maxi(peak_work,int(game.actors.simulation_status.route_work))
		if until_arrived and game.actors.pool.navigation_status(handle).state=="arrived":break
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"enclosed settlement loads"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false
	if game.actors.pool==null:check(game.actors.enable(),"actor simulation enables")
	var batch: Node3D=game.doors.collection
	var id: int=batch.get_ids()[0]
	var p: PackedFloat32Array=batch.get_instance(id)
	var pose:=Transform3D(Basis(Vector3(p[0],p[4],p[8]),Vector3(p[1],p[5],p[9]),Vector3(p[2],p[6],p[10])).orthonormalized(),Vector3(p[3],p[7],p[11]))
	var start: Vector3=pose*Vector3(0.5,-1.07,3.5)
	var goal: Vector3=pose*Vector3(0.5,0.93,-2.5)
	focus=pose.origin;game.player.position=pose*Vector3(3,1,4)
	game.terrain.focus=focus;game.structures.blocks.set_focus(focus);game.structures.set_model_focus(focus)
	check(await wait_for(func():return game._actor_collision_ready(AABB(focus-Vector3(6,3,8),Vector3(12,10,16)))) ,"actor route collision ready")
	var identity: int=game.actors.spawn(start);handle=game.actors.store.resolve_identity(identity)
	game.actors.orders.set_target(identity,goal)
	await advance(3)
	check((pose.affine_inverse()*game.actors.store.get_position(handle)).z>0,"closed door prevents actor entering")
	check(game.doors.state.toggle(batch,id,AABB()).ok,"door opens through native hinge path")
	await advance(8,true)
	print("DOOR_ROUTE_ENTRY ",game.actors.pool.navigation_status(handle)," position=",game.actors.store.get_position(handle)," goal=",goal)
	check(game.actors.store.get_position(handle).distance_to(goal)<0.3,"opening invalidates blocked route and actor reaches furnished interior")
	check(game.doors.state.toggle(batch,id,AABB()).ok,"door closes with actor safely inside")
	game.actors.orders.set_target(identity,start)
	await advance(3)
	check((pose.affine_inverse()*game.actors.store.get_position(handle)).z<0,"closed door prevents actor leaving")
	check(game.doors.state.toggle(batch,id,AABB()).ok,"door reopens")
	await advance(8,true)
	print("DOOR_ROUTE_EXIT ",game.actors.pool.navigation_status(handle)," position=",game.actors.store.get_position(handle)," goal=",start)
	check(game.actors.store.get_position(handle).distance_to(start)<0.3,"reopening permits actor to descend entrance and return")
	check(peak_work<=12,"door route retains planner work cap")
	await finish()
