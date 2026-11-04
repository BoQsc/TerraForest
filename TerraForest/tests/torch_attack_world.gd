# SPDX-License-Identifier: 0BSD
extends "res://tests/attack_contact_world.gd"
func run()->void:
	folder="res://reports/torch_attack/integration";DirAccess.make_dir_recursive_absolute(folder)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
	game.player_view.settings_path="";root.add_child(game)
	check(await until(func():return not game.loading_active and not game.needs_floor_spawn and not game.player_view.entry.blocks_actions(),65),"temporary native world and entry sequence ready")
	if game.loading_active or game.player_view.entry.blocks_actions():await finish();return
	var original_position:Vector3=game.player.position
	game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false;game.ground_enabled=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.zombies.clear();game.zombies.population_enabled=false;game.zombies.enabled=true
	var hud=game.player_hud;var attack=game.world_attack;var view=game.tool_view.human
	check(hud.inventory.grant_items(PackedInt64Array([6,1]),hud.inventory.snapshot().revision).ok,"native inventory owns a torch")
	hud.refresh();check(hud.equip_item(6),"ordinary gameplay belt equips the torch")
	check(await until(func():return view.action_remaining<=0),"torch keyed equip completes before attack")
	var profile:Dictionary=game.tool_view.attack_profile()
	check(profile.get("clip")=="FP_Torch_Swing" and is_equal_approx(profile.contact,26.0/60) and is_equal_approx(profile.duration,1.1),"gameplay selects the reviewed clip/contact/duration")
	var cell:=Vector3i(original_position.floor())+Vector3i(0,8,0)
	check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,65])),"real concrete target installed")
	game.structures.blocks.set_focus(Vector3(cell))
	for i in 5:await physics_frame
	aim(cell)
	check(attack.target().get("kind")=="block","normal shared ray query finds concrete")
	attack.impact_resolved.connect(func(identity:int,accepted:bool):impacts.append({"id":identity,"accepted":accepted,"clip":view.active_clip,"position":view.animation_player.current_animation_position}))
	var inventory:PackedByteArray=hud.inventory.capture_storage_snapshot()
	mouse(true);mouse(false)
	check(not attack.pending.is_empty() and damage(cell)==0 and hud.inventory.capture_storage_snapshot()==inventory,"left mouse starts visible windup without damage or inventory mutation")
	if attack.pending.is_empty():await finish();return
	attack.resolve_contact(attack.pending.identity)
	check(damage(cell)==0 and impacts.is_empty(),"early contact callback cannot apply torch damage")
	check(await until(func():return view.animation_player.current_animation_position>=.2) and damage(cell)==0,"actual windup remains harmless")
	await capture("windup")
	check(await until(func():return impacts.size()==1),"torch reaches one live contact")
	check(impacts.size()==1 and impacts[0].accepted and impacts[0].clip=="FP_Torch_Swing" and is_equal_approx(impacts[0].position,26.0/60) and damage(cell)==5,"frame-26 contact applies exactly five native concrete damage")
	check(hud.inventory.capture_storage_snapshot()==inventory and view.torch_effects.burning,"existing non-durable torch remains owned and lit after its hit")
	await capture("contact")
	check(not attack.pending.is_empty() and not attack.attack(),"recovery blocks an overlapping torch swing")
	check(await until(func():return attack.pending.is_empty()) and impacts.size()==1,"full recovery ends without a duplicate hit")
	await capture("recovered")
	for reason in ["equipment","inventory","focus"]:
		hud.equip_item(6);aim(cell);await until(func():return view.action_remaining<=0)
		attack.next_attack=0;var before:=impacts.size();var saved:PackedByteArray=attack.durability.capture_storage_snapshot()
		check(attack.attack(),"torch cancellation windup starts: "+reason)
		match reason:
			"equipment":hud.equip_item(1)
			"inventory":hud.set_open(true);hud.set_open(false)
			"focus":game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT);game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
		check(await until(func():return attack.pending.is_empty()) and impacts.size()==before and saved==attack.durability.capture_storage_snapshot(),"cancelled torch produces no ghost hit: "+reason)
	hud.equip_item(6);aim(cell);await until(func():return view.action_remaining<=0);attack.next_attack=0
	check(attack.attack(),"miss fixture starts its ordinary torch swing")
	game.camera.look_at(game.camera.global_position+Vector3(0,1,-.1))
	check(await until(func():return attack.pending.is_empty()) and not attack.last_hit and damage(cell)==5,"live aim at contact can miss without another target mutation")
	aim(cell);attack.next_attack=0;var count:=impacts.size();mouse(true)
	var hold_until:=Time.get_ticks_msec()+2450
	# Motor is paused for this airborne block fixture. Drive the actual gameplay
	# held-input path while retaining native input state and real animation time.
	while Time.get_ticks_msec()<hold_until:
		game._update_edit(1.0/60.0);await process_frame
	mouse(false)
	check(await until(func():return attack.pending.is_empty()),"last held torch swing finishes after release")
	var held:=impacts.size()-count
	check(held>=2 and held<=3 and damage(cell)==5*(held+1),"held left mouse produces one native hit per full torch cycle")
	# A real zombie uses the same normal target picker and blunt-impact adapter.
	var zombie:Node3D
	for offset:Vector3 in [Vector3(0,0,2),Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,-2)]:
		zombie=game.zombies.spawn_at(original_position+offset)
		if zombie!=null:break
	check(zombie!=null,"zombie fixture admits on actual streamed ground")
	if zombie!=null:
		zombie.set_behavior(false);zombie.set_physics_process(false)
		var point:=zombie.global_position+Vector3.UP*1.1
		game.player.position=zombie.global_position+Vector3(0,0,2)
		game.camera.global_position=point+Vector3(0,0,2);game.camera.look_at(point)
		game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		for i in 4:await physics_frame
		check(attack.target().get("kind")=="zombie","live torch ray finds the real zombie")
		var health:float=zombie.health;inventory=hud.inventory.capture_storage_snapshot();attack.next_attack=0
		check(attack.attack() and zombie.health==health,"torch zombie strike starts without immediate damage")
		check(await until(func():return attack.pending.is_empty()) and attack.last_hit and is_equal_approx(zombie.health,health-10),"one animation contact applies ten base melee damage to the zombie")
		check(hud.inventory.capture_storage_snapshot()==inventory and attack.ZOMBIE_IMPACTS[6]=="melee","blunt strike retains existing torch durability policy")
		await capture("zombie_contact")
	await finish()
func finish()->void:
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"temporary world shuts down cleanly without saving user data")
	game.free();await process_frame;await process_frame
	FileAccess.open(folder.path_join("checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"impacts":impacts,"scope":"Actual source-world left mouse, native block/zombie damage at animation contact and cancellation; no user saves or third-person art approval."},"  ")+"\n")
	print("TORCH_ATTACK_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
