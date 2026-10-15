# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"normal world loads with door component"):await finish();return
	game.set_physics_process(false);game._clear_motion()
	var door: Node3D=game.doors.collection
	var origin: Vector3=game.player.position+Vector3(0,8,-3)
	var pose:=Transform3D(Basis.IDENTITY,origin)
	var id: int=door.insert_instance(game.model_tool.records(pose,door),AABB())
	check(id>0,"door inserted in normal model collection")
	door.set_collision_focus(origin)
	aim(origin+Vector3(0.5,0,2),origin+Vector3(0.5,1,0))
	for i in 15:await physics_frame;await process_frame
	use()
	check(game.doors.state.is_open(id),"normal E input opens targeted door")
	check(game.terrain.changed_since_save,"interaction marks world dirty")
	var components: Dictionary=game.persistence._capture().sections
	check(components.has("door_hinges") and game.doors.state.validate_snapshot(components.door_hinges),"compound capture includes valid native door state")
	var model: PackedByteArray=door.capture_snapshot()
	game.doors.state.forget(id)
	check(game.doors.state.restore_storage_snapshot(components.door_hinges) and door.restore_snapshot(model),"captured open door restores")
	aim(origin+Vector3(2,0,-0.5),origin+Vector3(0,1,-0.5))
	for i in 15:await physics_frame;await process_frame
	use()
	check(not game.doors.state.is_open(id),"normal E input closes restored door")
	check(door.get_instance(id)==game.model_tool.records(pose,door),"closed door returns to original placed transform")
	await finish()
