# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run() -> void:
	var slot:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--route-evidence="):evidence=arg.trim_prefix("--route-evidence=")
		if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
	if evidence.is_empty() or not slot.begins_with("doors_"):quit(2);return
	game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"cloned world loads"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	var doors: Node3D=game.doors.collection
	var windows: Node3D=game.structures.model("architecture/wooden_window/v1")
	if "--reopen-building" in OS.get_cmdline_user_args():
		var saved: Dictionary=FileAccess.open(evidence,FileAccess.READ).get_var()
		check(game.doors.state.capture_storage_snapshot()==saved.hinges,"fresh process restores exact hinge state")
		game.structures.set_model_focus(saved.origin);game.structures.blocks.set_focus(saved.origin)
		check(await wait_for(func():return doors.get_instance(saved.id).size()==12),"saved door becomes resident")
		check(doors.get_instance(saved.id)==saved.door,"fresh process restores open door pose")
		check(windows.get_ids().size()==8,"fresh process restores eight window identities")
		aim(saved.origin+Vector3(2,1.03,4.7),saved.origin+Vector3(0,2,4.7))
		for i in 20:await physics_frame;await process_frame
		use()
		check(not game.doors.state.is_open(saved.id),"restored building door closes through E")
		await finish();return
	var asset: Resource=preload("res://addons/structures/furniture_catalog.gd").enclosed_cottage()
	check(asset!=null and asset.get_model_attachments().size()==13,"cottage combines furniture chest door and eight windows")
	# Elevated clone-only assembly isolates passage geometry from terrain edits.
	var origin:=Vector3i(game.player.position.floor())+Vector3i(20,12,0)
	game.construction_inventory.gameplay=false
	if not check(game.construction_inventory.place_prefab(game.structures.blocks,game.player_hud.inventory,asset,origin,0,game.structures.model_collections(),preload("res://addons/structures/construction_catalog.gd").recipes(),[]),"complete cottage transaction places"):await finish();return
	game.structures.blocks.set_focus(Vector3(origin));game.structures.set_model_focus(Vector3(origin))
	var bounds:=AABB(Vector3(origin)+Vector3(-5,0,-6),Vector3(11,10,14))
	if not check(await wait_for(func():return game.structures.is_collision_region_ready(bounds)),"cottage collision is ready"):await finish();return
	var id: int=doors.get_ids()[0]
	aim(Vector3(origin)+Vector3(0.5,1.03,6.8),Vector3(origin)+Vector3(0.5,2,5.5))
	for i in 5:await physics_frame
	var blocked: bool=game.player.test_move(game.player.global_transform,Vector3(0,0,-2.5))
	check(blocked,"closed door blocks player capsule")
	use();check(game.doors.state.is_open(id),"cottage entrance opens through E")
	for i in 20:await physics_frame;await process_frame
	for i in 90:
		await physics_frame
		var direction:=Vector3.FORWARD if game.player.position.z>origin.z+3.8 else Vector3.ZERO
		game.player.velocity=game.movement.walking_velocity(direction,game.player.velocity,1.0/60,false,game.player.is_on_floor(),false)
		game.movement.move_grounded(game.player,1.0/60)
	check(game.player.position.z<origin.z+4 and game.player.is_on_floor(),"player walks through open doorway onto cottage floor")
	game.player.position=Vector3(origin)+Vector3(0.5,1.02,3)
	check(not game.player.test_move(game.player.global_transform,Vector3(0,0,-4)),"central interior aisle stays clear")
	var file:=FileAccess.open(evidence,FileAccess.WRITE)
	file.store_var({"hinges":game.doors.state.capture_storage_snapshot(),"door":doors.get_instance(id),"id":id,"origin":Vector3(origin)});file.close()
	game.camera.global_position=Vector3(origin)+Vector3(12,7,16);game.camera.look_at(Vector3(origin)+Vector3(0,3,0))
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(evidence+".png")
	game.camera.position=Vector3(0,1.62,0)
	await finish()
