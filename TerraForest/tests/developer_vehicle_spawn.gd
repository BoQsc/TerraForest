# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var checks:=0
var failures:=0
var evidence:="res://reports/developer_vehicle_spawn"
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label);return ok
func wait_for(predicate:Callable,seconds:int=10)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(name+".png"))
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--vehicle-spawn-evidence="):evidence=argument.trim_prefix("--vehicle-spawn-evidence=")
	DirAccess.make_dir_recursive_absolute(evidence)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,50),"playable forest and player floor ready"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.fly=false
	var session=game.world_vehicle;var menu=game.session_menu
	check(session.fleet_enabled,"normal fleet path is enabled")
	menu.set_open(true);menu.show_page("Developer")
	var before:int=session.fleet.statistics().records
	menu.spawner.vehicle_button.pressed.emit()
	check(menu.opened and session.fleet.statistics().records==before and menu.message.text.contains("development"),"gameplay click keeps a visible development-mode explanation and creates nothing")
	menu.toggle_developer();menu.show_page("Developer")
	game.camera.rotation=Vector3.ZERO # Level view: the old centre ray misses ground.
	menu.spawner.vehicle_button.pressed.emit()
	check(await wait_for(func():return not menu.spawner.vehicle_busy,15),"one click waits for the actual vehicle resource without requiring another key")
	print("VEHICLE_MENU_RESULT ",game._lake_notice," · ",menu.message.text)
	if not check(session.last_spawn_identity>0 and session.fleet.statistics().records==before+1,"level-camera ESC click places a real vehicle nearby in the forest"):await capture("failure");await finish();return
	var id:int=session.last_spawn_identity
	check(not menu.opened and session.activation.residents.has(id) and session.activation.residents[id].visible,"successful click immediately shows the live vehicle and closes the menu")
	var car:RigidBody3D=session.activation.residents[id]
	check(car.global_position.distance_to(game.player.global_position)>3.25 and car.global_position.distance_to(game.player.global_position)<12,"nearby placement keeps player clearance and bounded distance")
	game.camera.look_at(car.global_position+Vector3.UP*.3);await capture("nearby_vehicle")
	# A failed click must remain readable and cannot add an invisible fleet record.
	session.interaction_available=func():return false
	before=session.fleet.statistics().records
	menu.set_open(true);menu.show_page("Developer");menu.spawner.vehicle_button.pressed.emit()
	await wait_for(func():return not menu.spawner.vehicle_busy,3)
	check(menu.opened and menu.current_page=="Developer" and menu.message.text.contains("unavailable") and session.fleet.statistics().records==before,"failed vehicle admission keeps the exact reason visible without a phantom saved vehicle")
	await capture("visible_failure")
	session.interaction_available=game._vehicle_interaction_available
	# Reject paid aimed placement when even part of its footprint lacks support.
	var platform:=StaticBody3D.new();var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(.5,.5,.5);collision.shape=shape;platform.add_child(collision);game.add_child(platform)
	platform.position=game.player.position+Vector3(0,8,-6)
	for i in 3:await physics_frame
	var hit:={"position":platform.global_position+Vector3.UP*.25,"normal":Vector3.UP}
	var fit:Dictionary=preload("res://addons/vehicle_runtime/vehicle_placement.gd").at_ground(game,session,hit,Basis.IDENTITY)
	check(not fit.ok,"a small aimed ledge cannot support a whole vehicle")
	await finish()
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("DEVELOPER_VEHICLE_SPAWN checks=",checks," failures=",failures);quit(1 if failures else 0)
