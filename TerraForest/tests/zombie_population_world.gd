# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/zombie_population_world"
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func until(predicate:Callable,seconds:float)->bool:
	var end:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<end:
		await physics_frame
		game.app_focused=true
	return predicate.call()
func _initialize()->void:run.call_deferred()
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zombie-evidence-dir="):folder=arg.trim_prefix("--zombie-evidence-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	check(await until(func():return not game.loading_active,55),"actual world becomes playable")
	if game.loading_active:game.terrain.shutdown();game.free();quit(1);return
	game._clear_motion();game.needs_floor_spawn=false;game.fly=false;game.app_focused=true
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	game.zombies.clear()
	check(not game.zombies.force_pursuit and game.zombies.spawn_visible.is_valid(),"normal world uses awareness and camera exclusion")
	for i in 60*3:await physics_frame;game.app_focused=true
	check(game.zombies.residents.is_empty() and game.zombies._spawn_clock>14,"initial active play has no close surprise spawns")
	var admitted:=false
	for attempt in 12:
		game.zombies._spawn_clock=0
		for i in 30:await physics_frame;game.app_focused=true
		if not game.zombies.residents.is_empty():admitted=true;break
	check(admitted,"automatic scheduler finds supported distant terrain in the actual world")
	var record:Dictionary={}
	if admitted:
		var zombie:CharacterBody3D=game.zombies.residents[0]
		var offset:Vector3=zombie.global_position-game.player.global_position;offset.y=0
		check(offset.length()>=39.5 and offset.length()<=64.5,"actual admission preserves forty metre safety distance")
		check(not game.camera.is_position_in_frustum(zombie.global_position+Vector3.UP),"actual admission stays outside player view")
		check(zombie.target==null and zombie.awareness_state in ["idle","wander"],"distant resident starts living independently of the player")
		game.zombies._spawn_clock=100000
		var before:Vector3=zombie.global_position
		check(await until(func():return zombie.global_position.distance_to(before)>.3,12),"distant zombie walks on actual streamed terrain")
		check(game.zombies.navigation_status.get("perception_probes",3)<=2,"actual host keeps perception probes bounded")
		record={"intent":game.zombies.awareness.status(zombie.get_instance_id()),"body":zombie.get_behavior_snapshot(),"navigation":game.zombies.navigator.status(zombie.get_instance_id())}
		if DisplayServer.get_name()!="headless":
			var camera:=Camera3D.new();game.add_child(camera);camera.global_position=zombie.global_position+Vector3(3,2.5,4);camera.look_at(zombie.global_position+Vector3.UP);camera.current=true;game.tool_view.hide()
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("roaming.png"))
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"record":record},"  "))
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("ZOMBIE_POPULATION_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
