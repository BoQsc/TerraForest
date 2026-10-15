# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func walk(ticks: int) -> void:
	game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
	for tick in ticks:
		await physics_frame;game.app_focused=true;game._physics_process(1.0/60)
	game.controls.clear(Time.get_ticks_usec())
func run() -> void:
	var slot:=""
	var expected_doors:=4
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
		if arg.begins_with("--expected-doors="):expected_doors=arg.trim_prefix("--expected-doors=").to_int()
	if not slot.begins_with("doorwalk_"):quit(2);return
	game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"copied enclosed settlement loads"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false
	var doors: Node3D=game.doors.collection
	var ids: PackedInt64Array=doors.get_ids()
	check(ids.size()==expected_doors,"expected generated building doors present")
	if expected_doors>4:
		var center:=Vector3.ZERO
		for id in ids:
			var p: PackedFloat32Array=doors.get_instance(id)
			center+=Vector3(p[3],p[7],p[11])
		center/=maxi(1,ids.size())
		game.camera.global_position=center+Vector3(85,75,100)
		game.camera.look_at(center)
		for tick in 30:await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://reports/mixed_neighborhood")
		root.get_texture().get_image().save_png("res://reports/mixed_neighborhood/overview.png")
	for id in ids:
		var p: PackedFloat32Array=doors.get_instance(id)
		var pose:=Transform3D(Basis(Vector3(p[0],p[4],p[8]),Vector3(p[1],p[5],p[9]),Vector3(p[2],p[6],p[10])).orthonormalized(),Vector3(p[3],p[7],p[11]))
		# Different prefabs have different foundation heights. Start on the
		# actual street surface rather than placing tower tests below the ground.
		var start: Vector3=pose*Vector3(0.5,0,3.5)
		var from:=start+Vector3.UP*5
		var to:=start-Vector3.UP*10
		if not check(await wait_for(func():return not game._terrain_pick(from,to).is_empty(),8),"street surface located for entrance"):continue
		start.y=game._terrain_pick(from,to).position.y+0.05
		aim(start,pose*Vector3(0.5,1,0))
		game.yaw=pose.basis.get_euler().y;game.player.rotation.y=game.yaw;game.pitch=0;game.camera.rotation=Vector3.ZERO
		game.terrain.focus=game.player.position;game.structures.blocks.set_focus(pose.origin);game.structures.set_model_focus(pose.origin)
		check(await wait_for(func():return game.structures.is_collision_region_ready(AABB(pose.origin-Vector3(6,3,8),Vector3(12,10,16)))) ,"entrance collision ready")
		await walk(90)
		var local: Vector3=pose.affine_inverse()*game.player.position
		print("ENTRANCE_APPROACH ",id," local=",local," street=",start)
		check(local.z>0 and local.z<1.5 and absf(local.y)<0.25,"approach ascends stairs and stops outside closed door %d"%id)
		game.camera.look_at(pose*Vector3(0.5,1,0));use()
		if not check(game.doors.state.is_open(id),"E opens generated door %d"%id):continue
		for tick in 15:await physics_frame;await process_frame
		await walk(45)
		local=pose.affine_inverse()*game.player.position
		print("ENTRANCE_RESULT ",id," local=",local)
		check(local.z< -1 and absf(local.y)<0.25 and game.player.is_on_floor(),"production player walks inside building %d without jumping"%id)
	await finish()
