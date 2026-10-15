# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"normal world loads"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false;game.fly=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var start: Vector3=game.player.position
	game.yaw=0;game.player.rotation.y=0
	if not check(game.terrain.player_region_ready(start) and game.terrain.player_region_ready(start+Vector3.FORWARD*2),"terrain ready independently of model fixture"):await finish();return
	var batch: Node3D=game.structures.model("architecture/wooden_window/v1")
	# A real authored model intersects the production motion-readiness probe.
	# Hold its admission briefly so the test deterministically observes the gap.
	batch.set_physics_process(false)
	var pose:=Transform3D(Basis(Vector3.RIGHT,PI/2),start+Vector3(0,-0.2,-1))
	var id: int=batch.insert_instance(game.model_tool.records(pose,batch),AABB())
	if not check(id>0,"unadmitted nearby model inserted"):batch.set_physics_process(true);await finish();return
	game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
	var held:=true
	for frame in 4:
		await physics_frame
		game.app_focused=true;game._physics_process(1.0/60)
		held=held and game.structure_motion_blocked and game.player.position.is_equal_approx(start) and game.player.velocity==Vector3.ZERO and game.controls.held.has(KEY_W)
	check(held,"production controller holds position and retains W while structure collision is missing")
	batch.set_physics_process(true);batch.set_collision_focus(start)
	check(await wait_for(func():return game.structures.is_collision_region_ready(AABB(start-Vector3.ONE,Vector3.ONE*2))),"native model admission completes")
	for frame in 30:
		await physics_frame
		game.app_focused=true;game._physics_process(1.0/60)
	check(not game.structure_motion_blocked and game.player.position.z<start.z-0.3,"held W resumes walking after admission without another key press")
	game.controls.clear(Time.get_ticks_usec())
	batch.remove_instances(PackedInt64Array([id]))
	await finish()
