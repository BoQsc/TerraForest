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
	check(game.player_hud.interaction_hint.visible and game.player_hud.interaction_hint.text=="E · Open wooden door","main-world HUD shows aimed door action")
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
	check(game.player_hud.interaction_hint.visible and game.player_hud.interaction_hint.text=="E · Close wooden door","main-world HUD reflects restored open hinge")
	use()
	check(not game.doors.state.is_open(id),"normal E input closes restored door")
	check(door.get_instance(id)==game.model_tool.records(pose,door),"closed door returns to original placed transform")
	for side: float in [-1.0,1.0]:
		aim(origin+Vector3(0.5,0,side*0.38),origin+Vector3(0.5,1.62,0))
		for frame in 12:await physics_frame;await process_frame
		use()
		check(game.doors.state.is_open(id),"E opens while pressed against the closed door from side "+str(side))
		aim(origin+Vector3(0.38,0,-0.5),origin+Vector3(0,1.62,-0.5))
		for frame in 12:await physics_frame;await process_frame
		use()
		check(not game.doors.state.is_open(id),"E closes while the player occupies the swing from side "+str(side))
	check(game.doors.state.toggle(door,id,AABB()).ok,"prepare open leaf for player-overlap check")
	aim(origin+Vector3(0.02,0,-0.5),origin+Vector3(-1,1.62,-0.5))
	for frame in 12:await physics_frame;await process_frame
	check(game.player_hud.interaction_hint.text=="E · Close wooden door" and game.player_hud.interaction_hint.visible,"close hint remains available with the camera inside the open leaf")
	use()
	check(not game.doors.state.is_open(id),"E closes from inside the open leaf")
	aim(origin+Vector3(0.5,0,0.02),origin+Vector3(0.5,1.62,-1))
	for frame in 12:await physics_frame;await process_frame
	check(game.player_hud.interaction_hint.text=="E · Open wooden door" and game.player_hud.interaction_hint.visible,"open hint remains available with the camera inside the closed leaf")
	use()
	check(game.doors.state.is_open(id),"E opens from inside the closed leaf")
	aim(origin+Vector3(0.2,0,-0.2),origin+Vector3(0,1.62,-0.5))
	for frame in 12:await physics_frame;await process_frame
	use()
	check(not game.doors.state.is_open(id),"player overlap with the final closed leaf does not veto closing")
	game.player.velocity=Vector3(0,0,-2)
	for frame in 30:
		await physics_frame
		game.player.velocity=Vector3(0,0,-2);game.movement.move_grounded(game.player,1.0/Engine.physics_ticks_per_second)
	check(game.player.position.is_finite() and game.player.position.z<origin.z-0.6,"native player movement can leave the door after overlapping closure")
	aim(origin+Vector3(0.5,0,4),origin+Vector3(0.5,1.62,0))
	for frame in 12:await physics_frame;await process_frame
	use()
	check(not game.doors.state.is_open(id),"close-range allowance does not extend the three-metre use range")
	var wall:=StaticBody3D.new();wall.collision_layer=1;wall.collision_mask=0
	var wall_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,2.2,0.2);wall_shape.shape=box;wall.add_child(wall_shape);game.add_child(wall);wall.position=origin+Vector3(0.5,1.1,0.6)
	for feet: Vector3 in [Vector3(0.5,0,1.2),Vector3(0.5,0,0.6)]:
		aim(origin+feet,origin+Vector3(0.5,1.62,0))
		for frame in 12:await physics_frame;await process_frame
		use()
		check(not game.doors.state.is_open(id) and not game.player_hud.interaction_hint.text.contains("wooden door"),"solid wall still occludes the door, including from inside the wall")
	wall.free()
	await finish()
