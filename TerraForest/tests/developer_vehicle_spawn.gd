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
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,50),"playable forest and player floor ready"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.fly=false
	var session=game.world_vehicle;var menu=game.session_menu
	check(session.fleet_enabled and not menu.developer,"fixture starts in ordinary gameplay without entering development mode")
	menu.set_open(true);menu.show_page("Developer")
	var before:int=session.fleet.statistics().records
	game.camera.rotation=Vector3(1.2,0,0) # Looking at sky must not reject spawning.
	session.interaction_available=func():return false # Focus/publication gates do not cancel an explicit spawn.
	menu.spawner.vehicle_button.pressed.emit()
	check(await wait_for(func():return not menu.spawner.vehicle_busy,15),"one click waits for the actual vehicle resource without requiring another key")
	print("VEHICLE_MENU_RESULT ",game._lake_notice," · ",menu.message.text)
	if not check(session.last_spawn_identity>0 and session.fleet.statistics().records==before+1,"first gameplay-mode click spawns despite sky aim and unavailable ordinary placement"):await capture("failure");await finish();return
	var id:int=session.last_spawn_identity
	check(not menu.opened and session.activation.residents.has(id) and session.activation.residents[id].visible and session.activation.residents[id].freeze,"first click immediately shows a frozen live vehicle and closes the menu")
	var car:RigidBody3D=session.activation.residents[id]
	check(not menu.developer and game.construction_inventory.gameplay,"spawning does not require or switch the player's gameplay mode")
	game.camera.look_at(car.global_position+Vector3.UP*.3);await capture("nearby_vehicle")
	before=session.fleet.statistics().records
	menu.set_open(true);menu.show_page("Developer");menu.spawner.entries[501].pressed.emit()
	await wait_for(func():return not menu.spawner.vehicle_busy,15)
	check(session.fleet.statistics().records==before+1 and session.activation.residents.has(session.last_spawn_identity) and not menu.developer,"vehicle entry in the item list also directly spawns a car on its first click in gameplay")
	await finish()
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("DEVELOPER_VEHICLE_SPAWN checks=",checks," failures=",failures);quit(1 if failures else 0)
