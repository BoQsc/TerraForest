# SPDX-License-Identifier: 0BSD
extends SceneTree

var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/zombie_variety_world"
var evidence:Array=[]
var sampled_intent_us:Array=[]

func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
	return ok

func until(predicate:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await physics_frame
		game.app_focused=true
	return predicate.call()

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()

func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):folder=argument.trim_prefix("--view-output=")
	DirAccess.make_dir_recursive_absolute(folder)
	game=load("res://demo/world.tscn").instantiate()
	game.temporary_world=true;game.background_fps=60;game.player_view.settings_path=""
	root.add_child(game)
	if not check(await until(func():return not game.loading_active,75),"ordinary temporary world loads its native population before play"):
		await finish();return
	if not check(game.zombies.enabled and not game.zombies.residents.is_empty(),"normal resident admission has live zombies without review spawns"):
		await finish();return
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"world test never captures desktop pointer")
	game.set_physics_process(false)
	var original:Dictionary={}
	var injured_count:=0
	var pristine=ClassDB.instantiate("NativeZombiePopulation")
	pristine.initialize(game.terrain.backend.world_seed,game._initial_generation_spawn)
	for zombie in game.zombies.residents:
		zombie.set_physics_process(false)
		var identity:int=zombie.get_meta("world_zombie_id",0)
		var recipe:Dictionary=pristine.encounter(identity)
		var intent:Dictionary=game.zombies.awareness.status(zombie.get_instance_id())
		check(identity>0 and intent.profile==recipe.profile and zombie.get_meta("encounter_profile","")==recipe.profile,"resident gets its deterministic production temperament "+str(identity))
		check(is_equal_approx(zombie.walk_speed,float(intent.walk_speed)) and is_equal_approx(zombie.chase_speed_multiplier,float(intent.chase_speed_multiplier)),"native profile drives physical movement speed "+str(identity))
		var vitals:PackedByteArray=zombie.anatomy.capture_vitals()
		original[identity]={"profile":recipe.profile,"vitals":vitals}
		if not recipe.initial_vitals.is_empty():
			injured_count+=1
			check(vitals==recipe.initial_vitals,"new amputee has exact generated body/limb health "+str(identity))
			check(zombie.detached_parts.is_empty(),"pre-existing amputation creates no detached ragdoll debris "+str(identity))
			for part:String in zombie.missing:
				if not zombie.missing[part]:continue
				check(not zombie.part_meshes[part].visible and zombie.hit_areas[part].collision_layer==0,"absent limb has no mesh or damage region "+str(identity)+" "+part)
			if zombie._crawling:
				zombie.skeleton.force_update_all_bone_transforms()
				var head:Vector3=zombie.skeleton.global_transform*zombie.skeleton.get_bone_global_pose(zombie.skeleton.find_bone("Head")).origin
				check(head.y-zombie.global_position.y<1.1,"generated leg amputee is prone before gameplay "+str(identity))
		evidence.append({"id":identity,"profile":recipe.profile,"missing":zombie.missing.duplicate(),"position":zombie.global_position,"health":zombie.health})
	check(injured_count>0,"seeded normal arrival includes a visible pre-existing limb-loss variant")
	var saved:PackedByteArray=game.zombies.population.capture()
	if DisplayServer.get_name()!="headless":
		var camera:=Camera3D.new();camera.fov=52;game.add_child(camera);camera.current=true;game.tool_view.hide()
		for zombie in game.zombies.residents:
			if not zombie.missing.values().has(true):continue
			for angle:int in 2:
				camera.global_position=zombie.global_position+Vector3(2.6 if angle==0 else -2.6,1.7,3.5)
				camera.look_at(zombie.global_position+Vector3.UP*(0.45 if zombie._crawling else 0.9))
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder.path_join("resident_%d_%d.png"%[zombie.get_meta("world_zombie_id"),angle]))
		camera.queue_free();game.camera.current=true
	check(game.zombies.population.restore(saved),"same real world accepts binary population restore")
	await process_frame;await physics_frame
	var deadline:=Time.get_ticks_msec()+25000
	while not game.zombies.population.advance(game.player.global_position,true) and Time.get_ticks_msec()<deadline:
		await physics_frame
	check(game.zombies.population.initial_complete,"population reload finishes through the ordinary loading admission path")
	var restored_ids:Dictionary={}
	for zombie in game.zombies.residents:
		var identity:int=zombie.get_meta("world_zombie_id",0)
		check(not restored_ids.has(identity) and original.has(identity),"reloaded resident has original unique identity "+str(identity))
		restored_ids[identity]=true
		if not original.has(identity):continue
		check(zombie.anatomy.capture_vitals()==original[identity].vitals and zombie.get_meta("encounter_profile","")==original[identity].profile,"reloaded anatomy and temperament are unchanged "+str(identity))
		check(zombie.detached_parts.is_empty(),"reload does not allocate detached limbs "+str(identity))
	check(restored_ids.size()==original.size(),"reload preserves all admitted inhabitants")
	game._clear_motion();game.needs_floor_spawn=false;game.fly=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.app_focused=true
	game.zombies.profiling_enabled=true;game.set_physics_process(true)
	for tick in 180:
		await physics_frame;game.app_focused=true
		sampled_intent_us.append(int(game.zombies.update_phase_us.get("intent",0)))
	check(game.zombies.residents.size()<=6 and int(game.zombies.navigation_status.get("perception_probes",0))<=2,"new variety preserves six-body and two-sight-probe limits")
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"gameplay sampling still leaves pointer uncaptured")
	await finish()

func finish()->void:
	sampled_intent_us.sort()
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"residents":evidence,"intent_samples":sampled_intent_us.size(),"intent_p95_us":sampled_intent_us[int(sampled_intent_us.size()*0.95)] if not sampled_intent_us.is_empty() else null,"scope":"Short normal-world population admission/restore; not sleeper animation, full traversal or endurance qualification"},"  "))
	game.shutdown_requested=true
	await game.terrain.shutdown_after_edits()
	game.free();await process_frame;await process_frame
	print("ZOMBIE_VARIETY_WORLD checks=",checks," failures=",failures)
	quit(1 if failures else 0)
