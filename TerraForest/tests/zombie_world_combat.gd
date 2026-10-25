# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks := 0
var failures := 0
var game: Node
var rows: Array = []
var captured := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void: run.call_deferred()

func _capture_attack() -> void:
	if captured or DisplayServer.get_name()=="headless": return
	captured=true
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/zombie_world_combat/attack.png")

func run() -> void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"real terrain world becomes ready")
	if not game.loading_active:
		game._clear_motion();game.needs_floor_spawn=false;game.fly=false;game.app_focused=true
		if game.session_menu.developer: game.session_menu.toggle_developer()
		game.session_menu.set_open(false);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		game.zombies.clear();await process_frame
		game.zombies.population_enabled=false
		check(game.is_physics_processing(),"fixture keeps real world physics and encounter updates active")
		check((game.player.collision_mask & game.zombies.CHARACTER_LAYER)!=0,"real native player motor collides with zombie capsules")
		var zombie: CharacterBody3D
		for offset in [Vector3(0.9,0,0),Vector3(-0.9,0,0),Vector3(0,0,0.9),Vector3(0,0,-0.9),Vector3(1.1,0,1.1)]:
			zombie=game.zombies.spawn_at(game.player.global_position+offset)
			if zombie!=null: break
		check(zombie!=null,"close-range zombie admits on actual streamed collision")
		DirAccess.make_dir_recursive_absolute("res://reports/zombie_world_combat")
		if zombie!=null:
			game.camera.look_at(zombie.global_position+Vector3.UP*1.35)
			game.player_hud.equip(0)
			var maximum_time:=0.0
			for tick in Engine.physics_ticks_per_second*8:
				await physics_frame
				game.app_focused=true
				if not is_instance_valid(zombie): break
				var state: Dictionary=zombie.get_behavior_snapshot()
				maximum_time=maxf(maximum_time,state.action_time)
				if tick % 30==0: rows.append(state)
				if not String(state.active_action).is_empty() and state.action_time>0.4: _capture_attack()
			check(is_instance_valid(zombie) and zombie.get_behavior_snapshot().contact_count>0,"unmodified world physics allows autonomous attack contacts")
			check(game.zombie_target.damage_received>0,"actual player adapter receives zombie attack damage")
			check(maximum_time>0.5,"actual host updates preserve attack windup")
			var before:float=game.zombie_target.damage_received
			game.session_menu.set_open(true)
			for tick in Engine.physics_ticks_per_second*2: await physics_frame
			check(is_equal_approx(before,game.zombie_target.damage_received),"real Escape menu suspends attack contacts")
			game.session_menu.set_open(false);game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
			for tick in Engine.physics_ticks_per_second*4:
				await physics_frame
				game.app_focused=true
			check(game.zombie_target.damage_received>before,"closing real Escape menu restores completed attacks")
		var report:=FileAccess.open("res://reports/zombie_world_combat/result.json",FileAccess.WRITE)
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"damage_received":game.zombie_target.damage_received,"samples":rows},"  "));report.close()
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("ZOMBIE_WORLD_COMBAT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
