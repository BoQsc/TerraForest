# SPDX-License-Identifier: 0BSD
extends "res://tests/actor_population_cost.gd"
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	game.terrain.backend.disable_snapshot_writes();game.set_physics_process(false);game._clear_motion()
	var ends: PackedVector3Array=game.road_palette.prepared_streets[0].ends
	direction=(ends[1]-ends[0]).normalized();side=Vector3(-direction.z,0,direction.x);start=ends[0]+direction*5+Vector3.UP*0.95
	game.player.position=start+side*8;game.terrain.focus=start
	deadline=Time.get_ticks_msec()+30000
	while not game._actor_collision_ready(AABB(start-Vector3.ONE*3,Vector3.ONE*6)) and Time.get_ticks_msec()<deadline:await process_frame
	add_until(1)
	var snapshot: PackedByteArray=game.actors.store.capture_storage_snapshot()
	var positions: Array[Vector3]=[];var original_rate:=Engine.physics_ticks_per_second
	for rate in [60,120]:
		Engine.physics_ticks_per_second=rate
		check(game.actors._restore(snapshot),"restore same starting actor at%dHz"%rate)
		var before: int=game.actors.simulation_steps
		for tick in rate:
			await physics_frame
			game.actors.update_simulation(1.0/rate,start,true,game._actor_collision_ready)
		check(game.actors.simulation_steps-before==rate,"actor movement follows%dHz engine timestep"%rate)
		var position: Vector3=game.actors.store.get_position(game.actors.store.resolve_identity(ids[0]))
		positions.append(position)
		check((position-start).dot(direction)>2,"actor travels over2m at%dHz"%rate)
	check(positions[0].distance_to(positions[1])<0.01,"same elapsed time yields same movement within1cm")
	game.actors.update_simulation(1.0/120,start,false,game._actor_collision_ready)
	check(game.actors.pool.active_handles().is_empty(),"unavailability suspends immediately between actor ticks")
	var before: int=game.actors.simulation_steps
	game.actors.update_simulation(1.0/120,start,true,game._actor_collision_ready)
	check(game.actors.simulation_steps==before+1,"resume advances exactly one engine timestep")
	Engine.physics_ticks_per_second=original_rate
	DirAccess.make_dir_recursive_absolute("res://reports/actor_cadence")
	var file:=FileAccess.open("res://reports/actor_cadence/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"positions":positions}));file.close()
	game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
