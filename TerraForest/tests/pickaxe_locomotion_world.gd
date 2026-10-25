# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var checks:=0
var movement_records:Array=[]
func verify(ok:bool,label:String)->bool:
	checks+=1
	return check(ok,label)
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);root.position=Vector2i(-32000,-32000)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	evidence="res://reports/pickaxe_locomotion/world";DirAccess.make_dir_recursive_absolute(evidence)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	if not verify(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,60),"temporary native world is ready"):
		await finish();return
	game.set_physics_process(false);game._clear_motion();game.zombies.population_enabled=false;game.zombies.clear()
	ProjectSettings.set_setting("terraforest/offscreen_session",false)
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.app_focused=true;game.fly=false;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	game.player_hud.equip_item(1)
	var view=game.tool_view.human;view.set_process(false)
	verify(view.body==game.player,"view reads the actual player body owned by the motor")
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false);var weapon:=skeleton.find_bone("Weapon_Pickaxe")
	for sprint in [false,true]:
		game.controls.held[KEY_W]=true
		if sprint:game.controls.held[KEY_SHIFT]=true
		var start:Vector3=game.player.position;var first:=Vector3.ZERO;var travel:=0.0;var clips:={};var maximum_speed:=0.0
		for frame in 60:
			await physics_frame;game.app_focused=true;game._physics_process(1.0/60.0);view._process(1.0/60.0)
			clips[view.active_clip]=true
			var speed:=Vector2(game.player.velocity.x,game.player.velocity.z).length();maximum_speed=maxf(maximum_speed,speed)
			var point:=skeleton.get_bone_global_pose(weapon).origin
			if frame==10:first=point
			if frame>10:travel=maxf(travel,point.distance_to(first))
		var distance:=Vector2(game.player.position.x-start.x,game.player.position.z-start.z).length()
		verify(distance>.2 and maximum_speed>.15,"native motor moves player during "+("sprint" if sprint else "walk"))
		verify(travel>.01 and clips.has("FP_Pickaxe_Fresh_Run" if sprint else "FP_Pickaxe_Fresh_Walk"),"actual motor velocity selects the matching moving pickaxe clip")
		movement_records.append({"sprint":sprint,"displacement":distance,"maximum_speed":maximum_speed,"weapon_travel":travel,"clips":clips.keys()})
		game.controls.held.clear()
	for frame in 30:
		await physics_frame;game._physics_process(1.0/60.0);view._process(1.0/60.0)
	verify(view.active_clip=="FP_Pickaxe_Fresh_Idle","stopping returns to approved idle")
	RenderingServer.force_draw(false);RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(evidence+"/stopped.png")
	FileAccess.open(evidence+"/movement.json",FileAccess.WRITE).store_string(JSON.stringify(movement_records,"  "))
	await finish()
func finish()->void:
	game.shutdown_requested=true
	verify(await game.terrain.shutdown_after_edits(),"temporary world closes with edits settled")
	game.free();await process_frame;await process_frame
	FileAccess.open(evidence+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"movement":movement_records,"scope":"Temporary ordinary world, native player motor, actual velocity and pickaxe animation dispatch; walk/sprint/stop. No saved-world changes or impact-alignment claim."},"  "))
	print("PICKAXE_LOCOMOTION_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
