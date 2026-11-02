# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"

const DOOR:="architecture/wooden_door/v1"
var game:Node
var expected:Dictionary={}

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	super._initialize()

func run()->void:
	var reopening:bool="--door-reopen" in OS.get_cmdline_user_args()
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed;await wait_for(browser_catalog_ready)
	var browser:=current_scene
	var report:=""
	if reopening:
		expected=FileAccess.open(folder.path_join("expected.bin"),FileAccess.READ).get_var()
		if not check(str(expected.slot).begins_with("Reinforced_"),"only reopen owned reinforcement fixture"):await finish();return
		var selected:=-1
		for index in browser.worlds.item_count:
			if browser.worlds.get_item_metadata(index)==expected.slot:selected=index;break
		if not check(selected>=0,"normal world selector lists fixture"):await finish();return
		browser.worlds.select(selected);browser.launch_selected(false)
	else:
		expected.slot="Reinforced_1703_"+Crypto.new().generate_random_bytes(4).hex_encode()
		FileAccess.open(folder.path_join("created_slot.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":expected.slot}))
		browser.name_field.text=expected.slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
		check(browser.selected_options()==preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS,"normal default recipe without developer content flags")
		browser.generate_button.pressed.emit()
		if not check(await wait_for(func()->bool:return browser.preparation_job!=null and browser.preparation_job.task!=null and not browser.preparation_job.task.report.is_empty(),15),"generation reports its owned work directory"):await finish();return
		report=browser.preparation_job.task.report
	if not check(await wait_for(game_ready,520),"ordinary generation or load reaches play"):await finish();return
	game=current_scene;game.background_fps=60;game.app_focused=true;game.set_physics_process(false);game._clear_motion();game.zombies.update(0,game.player.global_position,false)
	var entry:Dictionary=game.doors.types[DOOR]
	if reopening:
		check(entry.locks.capture_storage_snapshot()==expected.locks,"fresh process restores all partial reinforcement exactly")
	else:
		var generated:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report.path_join("door_reinforcement.json")))
		check(generated.ok and not generated.locked.is_empty(),"ordinary world generation includes reinforced houses")
		if generated.locked.is_empty():await finish();return
		check(entry.locks.store.get_ids().size()==generated.locked.size(),"all generated locks reached the published world")
		expected.id=int(generated.doors[0].id);expected.point=Vector3(generated.doors[0].position[0],generated.doors[0].position[1],generated.doors[0].position[2])
		FileAccess.open(folder.path_join("generation.json"),FileAccess.WRITE).store_string(JSON.stringify(generated))
	game.teleport(expected.point,expected.point.y+2)
	if not check(await wait_for(game_ready,120) and await wait_for(func()->bool:return not entry.collection.get_instance(expected.id).is_empty(),30),"normal destination streaming admits locked door"):await finish();return
	game.app_focused=true;game.zombies.update(0,game.player.global_position,false)
	check(await wait_for(func()->bool:return entry.reinforcement.shown.has(expected.id),10),"derived boards appear on the streamed production door")
	var pose:Transform3D=game.doors._pose(entry.collection.get_instance(expected.id))
	var center:Vector3=pose*entry.definition.bounds.get_center()
	var viewer:=Camera3D.new();game.add_child(viewer);viewer.current=true
	var hit:Dictionary={}
	for side in [1,-1]:
		viewer.global_position=center+pose.basis.z.normalized()*3*side+Vector3.UP*.15;viewer.look_at(center)
		for frame in 12:await physics_frame
		hit=game.structures.blocks.raycast_scene(viewer.global_position,center,7,[game.player.get_rid()],true)
		if game.doors.aimed_id(hit)==expected.id:break
	check(game.doors.aimed_id(hit)==expected.id,"real doorway approach has unoccluded interaction picking")
	await photograph("restored" if reopening else "reinforced")
	if not reopening:
		game.equipped_tool=2;game.player_hud.equip(1)
		var target:Dictionary={"kind":"model","key":"model:"+DOOR+":"+str(expected.id),"id":expected.id,"collection":entry.collection,"asset":DOOR,"health":90,"material":"wood","name":"Wooden door"}
		check(game.world_attack.apply_target(target) and game.world_attack.apply_target(target),"actual player contact adapter damages generated reinforcement")
		check(entry.locks.store.lock_state(expected.id).remaining==120,"generated door retains two-thirds reinforcement for save")
		check(await wait_for(func()->bool:return entry.reinforcement.shown.get(expected.id,0)==2,10),"visible damage stage updates in populated world")
		await photograph("damaged")
		expected.locks=entry.locks.capture_storage_snapshot()
		FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE).store_var(expected)
	check(await leave(),"normal Save and return preserves reinforcement")
	await finish()

func finish()->void:
	if is_instance_valid(game) and game.is_inside_tree():
		game.shutdown_requested=true;await game.terrain.shutdown_after_edits()
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame
	print("DOOR_REINFORCEMENT_WORLD checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
