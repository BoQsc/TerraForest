# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func walk_to(target: Vector3) -> bool:
	for tick in 180:
		var delta: Vector3=target-game.player.position;delta.y=0
		if delta.length()<0.12 and absf(game.player.position.y-target.y)<0.2 and game.player.is_on_floor():return true
		await physics_frame
		game.player.velocity=game.movement.walking_velocity(delta.normalized() if delta.length()>=0.12 else Vector3.ZERO,game.player.velocity,1.0/60,false,game.player.is_on_floor(),false)
		game.movement.move_grounded(game.player,1.0/60)
	print("ROUTE_FAILURE target=",target," player=",game.player.position)
	return false
func run() -> void:
	var tower: bool="--tower" in OS.get_cmdline_user_args()
	var front: float=8.5 if tower else 5.5
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
		check(windows.get_ids()==saved.windows,"fresh process restores exact window identities")
		if tower:check(game.structures.model("architecture/metal_guardrail/v1").capture_snapshot()==saved.guards,"fresh process restores exact guardrail placements")
		aim(saved.origin+Vector3(2,1.03,front-0.8),saved.origin+Vector3(0,2,front-0.8))
		for i in 20:await physics_frame;await process_frame
		use()
		check(not game.doors.state.is_open(saved.id),"restored building door closes through E")
		game.player.position=saved.origin+Vector3(0.5,1.03,front+0.8)
		game.yaw=0;game.pitch=0;game.player.rotation.y=0;game.camera.position=Vector3(0,1.62,0);game.camera.rotation=Vector3.ZERO
		await finish();return
	var catalog=preload("res://addons/structures/furniture_catalog.gd")
	var asset: Resource=catalog.furnished_tower(3) if tower else catalog.enclosed_cottage()
	check(asset!=null and asset.get_model_attachments().size()==(66 if tower else 13),"building combines expected furniture storage door windows and guards")
	var origin:=Vector3i(game.player.position.floor())+Vector3i(20,12,0)
	game.construction_inventory.gameplay=false
	if "--grounded" in OS.get_cmdline_user_args():
		game.structure_mode=true;game.structure_rotation=0
		for i in game.structure_prefabs.size():
			if game.structure_prefabs[i].resource_name==asset.resource_name:game.structure_prefab_index=i;break
		game.camera.global_position=game.player.position+Vector3(60,15,30)
		game.camera.look_at(game.player.position+Vector3(60,-10,30),Vector3.FORWARD)
		await physics_frame
		game._survey_construction()
		if not check(await wait_for(func():return not game.construction_palette.survey_busy,20) and not game._survey_plan.is_empty(),"editor surveys grounded cottage site"):print(game.construction_palette.survey_dialog.dialog_text);await finish();return
		game._prepare_construction_site()
		if not check(await wait_for(func():return game.site_preparation.status!="running",30) and game.site_preparation.status=="complete","editor grades cottage foundation"):print(game.site_preparation.reason);await finish();return
		var prior: int=game.structures.blocks.stats().cells
		game._place_prepared_site()
		if not check(await wait_for(func():return game._foundation_placement.is_empty(),20) and game.structures.blocks.stats().cells>prior,"supported cottage publishes through editor placement"):print(game.construction_palette.survey_dialog.dialog_text);await finish();return
		origin=game.site_preparation.plan.target
		game.construction_palette.survey_dialog.hide()
	else:
		# Elevated clone-only assembly isolates geometry when no grading is requested.
		if not check(game.construction_inventory.place_prefab(game.structures.blocks,game.player_hud.inventory,asset,origin,0,game.structures.model_collections(),preload("res://addons/structures/construction_catalog.gd").recipes(),[]),"complete cottage transaction places"):await finish();return
	# The normalized prefab raises the original cottage coordinate system by 1 m.
	if not tower:origin+=Vector3i(0,1,0)
	aim(Vector3(origin)+Vector3(0.5,1.03,front+1.3),Vector3(origin)+Vector3(0.5,2,front))
	game.terrain.focus=game.player.position
	game.structures.blocks.set_focus(Vector3(origin));game.structures.set_model_focus(Vector3(origin))
	var bounds:=AABB(Vector3(origin)+Vector3(-9,0,-9),Vector3(19,14,20)) if tower else AABB(Vector3(origin)+Vector3(-5,0,-6),Vector3(11,10,14))
	if not check(await wait_for(func():return game.structures.is_collision_region_ready(bounds)),"cottage collision is ready"):await finish();return
	var id: int=doors.get_ids()[0]
	aim(Vector3(origin)+Vector3(0.5,1.03,front+1.3),Vector3(origin)+Vector3(0.5,2,front))
	for i in 5:await physics_frame
	var blocked: bool=game.player.test_move(game.player.global_transform,Vector3(0,0,-2.5))
	check(blocked,"closed door blocks player capsule")
	use();check(game.doors.state.is_open(id),"cottage entrance opens through E")
	for i in 20:await physics_frame;await process_frame
	for i in 90:
		await physics_frame
		var direction:=Vector3.FORWARD if game.player.position.z>origin.z+front-1.7 else Vector3.ZERO
		game.player.velocity=game.movement.walking_velocity(direction,game.player.velocity,1.0/60,false,game.player.is_on_floor(),false)
		game.movement.move_grounded(game.player,1.0/60)
	check(game.player.position.z<origin.z+front-1.5 and game.player.is_on_floor(),"player walks through open doorway onto building floor")
	if tower:
		var route_ok:=true
		for target: Vector3 in [Vector3(3,1,6),Vector3(3,1,-0.8),Vector3(0.5,1,-0.8),Vector3(0.5,5,4.6),Vector3(3,5,4.6),Vector3(3,5,-0.8),Vector3(0.5,5,-0.8),Vector3(0.5,9,4.6)]:
			if not await walk_to(Vector3(origin)+target):route_ok=false;break
		check(route_ok,"main-world player walks from entrance to third floor")
		if route_ok:
			for target: Vector3 in [Vector3(0.5,5,-0.8),Vector3(3,5,-0.8),Vector3(3,5,4.6),Vector3(0.5,5,4.6),Vector3(0.5,1,-0.8),Vector3(3,1,-0.8),Vector3(3,1,6)]:
				if not await walk_to(Vector3(origin)+target):route_ok=false;break
		check(route_ok,"main-world player returns downstairs")
	else:
		game.player.position=Vector3(origin)+Vector3(0.5,1.02,3)
		check(not game.player.test_move(game.player.global_transform,Vector3(0,0,-4)),"central interior aisle stays clear")
	var file:=FileAccess.open(evidence,FileAccess.WRITE)
	file.store_var({"hinges":game.doors.state.capture_storage_snapshot(),"door":doors.get_instance(id),"id":id,"origin":Vector3(origin),"windows":windows.get_ids(),"guards":game.structures.model("architecture/metal_guardrail/v1").capture_snapshot()});file.close()
	game.camera.global_position=Vector3(origin)+(Vector3(23,18,30) if tower else Vector3(12,7,16));game.camera.look_at(Vector3(origin)+Vector3(0,6 if tower else 3,0))
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(evidence+".png")
	game.camera.position=Vector3(0,1.62,0)
	game.yaw=PI;game.pitch=0;game.player.rotation.y=PI;game.camera.rotation=Vector3.ZERO
	game.structure_mode=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	await finish()
