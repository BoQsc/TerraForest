# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"integrated terrain world becomes ready")
	if game.loading_active:
		game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();quit(1);return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.fly=false;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	check(game.zombies.enabled,"gameplay enables zombie encounters")
	check(game.tool_view.human.body==game.player,"R11 presentation follows existing native player motor")
	game.player_hud.equip(0)
	check(game.tool_view.human.current==1,"real belt equips R11 pickaxe")
	game.player_hud.equip(1)
	check(game.tool_view.human.current==2,"real belt equips R11 axe")
	game.zombies.clear();await process_frame
	# Find supported ground through the actual streamed terrain/structures/forest gate.
	var zombie:CharacterBody3D
	for offset in [Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,2),Vector3(0,0,-2),Vector3(3,0,3)]:
		zombie=game.zombies.spawn_at(game.player.global_position+offset)
		if zombie!=null:break
	check(zombie!=null,"zombie admits on actual streamed world collision")
	if zombie!=null:
		game.zombies.update(0.01,game.player.global_position,true,false)
		zombie.set_behavior(false);zombie.set_physics_process(false)
		game.camera.look_at(zombie.global_position+Vector3.UP*1.0)
		for tick in 3:await physics_frame
		var selected:Dictionary=game.world_attack.target()
		check(selected.get("kind")=="zombie","existing world attack resolves R4 target")
		if selected.get("kind")=="zombie":
			var health:float=zombie.health
			var slot:int=game.player_hud.active_slot
			var wear:int=game.player_hud.inventory.snapshot().slots[slot].wear
			check(game.world_attack.apply_target(selected),"existing melee adapter accepts zombie strike")
			var feedback=game.player_hud.damage_feedback
			check(feedback.visible and feedback.remaining==int(ceil(zombie.limb_health[selected.part])) and feedback.maximum==int(zombie.PARTS[selected.part].health),"live character strike displays authoritative hit-region durability")
			check(zombie.health<health,"integrated strike reaches live zombie health")
			check(game.player_hud.inventory.snapshot().slots[slot].wear==wear+1,"zombie strike wears the actual equipped tool once")
			check(game.terrain.changed_since_save,"tool wear marks compound player save dirty")
		game.zombies.update(0.1,game.player.global_position,false)
		check(zombie.process_mode==Node.PROCESS_MODE_DISABLED,"integrated menu/edit gate suspends encounters")
		check(not game.zombies.apply_hit(selected,20,Vector3.FORWARD),"suspended target rejects stale attack")
		game.zombies.update(0.1,game.player.global_position,true,false)
		zombie.set_behavior(false)
		var death_target:Dictionary=selected.duplicate()
		death_target.part="torso"
		for hit in 20:
			if not zombie.alive:break
			game.world_attack.apply_target(death_target)
		check(not zombie.alive and not game.player_hud.damage_feedback.visible and game.player_hud.damage_feedback.expires_us==0,"fatal character strike clears feedback synchronously")
		game.player_hud.equip(0)
		for tick in 5:await process_frame
		DirAccess.make_dir_recursive_absolute("res://reports/character_world")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/character_world/world.png")
		var pose:PackedByteArray=game._capture_player_pose()
		check(game._restore_player_pose(pose) and game.zombies.residents.is_empty(),"world pose restore clears transient encounters")
	await process_frame
	# Exercise an existing paid tool action in the gameplay mode this fixture owns.
	game.player_hud.equip(1)
	var base:=Vector3i(game.player.position.floor())+Vector3i(0,6,0)
	game.structures.blocks.set_focus(Vector3(base))
	check(game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,33])),"existing wooden block damage fixture installs")
	game.camera.global_position=Vector3(base)+Vector3(0.5,0.5,2.5);game.camera.look_at(Vector3(base)+Vector3.ONE*0.5)
	for tick in 4:await physics_frame
	var before:int=game.player_hud.inventory.snapshot().slots[1].wear
	print("BLOCK_ATTACK_CONTEXT ",JSON.stringify({"target":game.world_attack.target(),"available":game._model_edit_available(),"tool":game.equipped_tool,"mouse":Input.mouse_mode,"menu":game.session_menu.visible_ui(),"camera":game.camera.global_position,"base":base}))
	game.world_attack.next_attack=0
	check(await preload("res://tests/swing_driver.gd").strike(game) and game.structures.blocks.get_cell(base)!=0 and game.player_hud.inventory.snapshot().slots[1].wear==before+1,"R11 axe preserves existing block damage and wear")
	game.world_attack.next_attack=0
	check(await preload("res://tests/swing_driver.gd").strike(game) and game.structures.blocks.get_cell(base)==0,"R11 axe preserves existing block destruction")
	check(not game.persistence._capture().sections.has("zombies"),"encounters do not change persistent world actor schema")
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("CHARACTER_WORLD checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
