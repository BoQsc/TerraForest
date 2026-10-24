# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var checks := 0
var impacts: Array = []
func verify(ok: bool, label: String) -> bool:
	checks += 1; return check(ok,label)
func mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	Input.parse_input_event(event); Input.flush_buffered_events()
func run() -> void:
	if DisplayServer.get_name() == "headless": push_error("Unarmed input check requires a graphical mouse-mode backend"); quit(2); return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); root.position = Vector2i(-32000,-32000)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	game = load("res://demo/world.tscn").instantiate(); game.temporary_world = true; game.background_fps = 60; game.player_view.settings_path = ""
	root.add_child(game)
	if not verify(await wait_for(func(): return not game.loading_active and not game.needs_floor_spawn,60),"ordinary temporary world becomes playable"):
		await finish(); return
	ProjectSettings.set_setting("terraforest/offscreen_session",false)
	game.set_physics_process(false); game._clear_motion(); game.zombies.clear()
	if game.session_menu.developer: game.session_menu.toggle_developer()
	game.session_menu.set_open(false)
	var hud = game.player_hud; hud.equip(9)
	var view = game.tool_view.human; view.set_process(false)
	verify(hud.active_slot == 9 and hud.active_item == 0 and game.equipped_tool == 0 and view.active_clip == "FP_Unarmed_Idle","selecting the actual empty belt slot equips neutral hands")
	var base := Vector3i(game.player.position.floor()) + Vector3i(0,1,0)
	game.structures.blocks.set_focus(Vector3(base)); game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,1]))
	game.player.position = Vector3(base)+Vector3(.5,-1.15,1.65)
	game.camera.global_position = Vector3(base)+Vector3(.5,.5,1.65); game.camera.look_at(Vector3(base)+Vector3.ONE*.5)
	game.app_focused = true; game.fly = false; game.needs_floor_spawn = false; Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var attack = game.world_attack
	if not verify(await wait_for(func(): return attack.target().get("kind") == "block",5),"real block collider is in fist reach"):
		await finish(); return
	var target: Dictionary = attack.target(); var key: String = target.key; var health: int = target.health
	game.camera.global_position += Vector3(0,0,.75)
	verify(attack.target().get("kind")=="block" and is_equal_approx(attack.reach(),1.65),"bare hands can select a block at a comfortable 1.4 metre distance")
	game.camera.global_position += Vector3(0,0,.75)
	verify(attack.target().is_empty(), "bare hands cannot select a block beyond arm reach")
	hud.equip(0)
	verify(attack.target().get("kind") == "block" and is_equal_approx(attack.reach(),3.5), "equipped pickaxe retains its existing longer interaction reach")
	hud.equip(9); game.camera.global_position -= Vector3(0,0,1.5)
	var inventory_before: PackedByteArray = hud.inventory.capture_storage_snapshot()
	attack.impact_resolved.connect(func(id: int, accepted: bool): impacts.append({"identity":id,"accepted":accepted,"time":view.animation_player.current_animation_position}))
	mouse(true); await process_frame; game._update_edit(.1); mouse(false)
	verify(not attack.pending.is_empty() and view.active_clip == "FP_Unarmed_Punch", "empty-slot left click starts an actual punch")
	var contact: float = game.tool_view.attack_profile().contact
	view._process(contact-.01)
	verify(impacts.is_empty() and attack.durability.damage(key,health) == 0, "winding up cannot damage the target")
	view._process(.1)
	verify(impacts.size() == 1 and impacts[0].accepted and is_equal_approx(impacts[0].time,contact) and attack.durability.damage(key,health) == 5, "frame-28 fist contact applies one normal bare-hand hit")
	var skeleton: Skeleton3D = view.model.find_child("Skeleton3D",true,false)
	var knuckle := skeleton.to_global(skeleton.get_bone_global_pose(skeleton.find_bone("RightHandMiddle1")).origin)
	verify(knuckle.distance_to(target.position)<.07, "visible striking knuckles reach the actual world contact point")
	verify(hud.inventory.capture_storage_snapshot() == inventory_before, "bare-hand punch does not consume an item or wear a tool")
	view._process(1)
	verify(attack.pending.is_empty() and view.active_clip == "FP_Unarmed_Idle", "recovery returns to neutral hands in the real world")
	attack.next_attack = 0; verify(attack.attack(),"another punch can start after recovery")
	view._process(.1); hud.equip(0); view._process(1)
	verify(impacts.size() == 1 and attack.pending.is_empty() and game.tool_view.attack_profile().clip == "FP_Pickaxe_Fresh_Swing", "switching to the pickaxe cancels the unfinished punch")
	hud.equip(9); game.camera.global_position += Vector3(0,0,1.5); attack.next_attack = 0
	verify(attack.attack(), "out-of-reach click can still animate an air punch")
	view._process(contact+.01); view._process(1)
	verify(impacts.size() == 2 and not impacts[-1].accepted and attack.durability.damage(key,health) == 5, "air punch cannot damage the distant block")
	game.camera.global_position -= Vector3(0,0,.75);attack.next_attack=0
	verify(attack.attack(),"punch starts at comfortable building distance")
	view._process(contact+.01);view._process(1)
	verify(impacts.size()==3 and impacts[-1].accepted and attack.durability.damage(key,health)==10,"comfortable-distance punch deals one hit at animation contact")
	game.camera.global_position -= Vector3(0,0,.75)
	if "--video" in OS.get_cmdline_user_args(): await capture_sequence(base)
	await finish()
func capture_sequence(cell: Vector3i) -> void:
	var folder := "res://reports/unarmed/world_frames"; DirAccess.make_dir_recursive_absolute(folder)
	var view = game.tool_view.human; var attack = game.world_attack
	var point := Vector3(cell)+Vector3(.8,.5,1)
	var eye := point+Vector3(sin(deg_to_rad(35.0)),0,cos(deg_to_rad(35.0)))*.65
	game.player.position = eye-Vector3(0,1.65,0); game.camera.global_position = eye; game.camera.look_at(point)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED); root.size = Vector2i(1280,720)
	root.position = Vector2i(-32000,-32000)
	var note := Label.new(); note.position = Vector2(24,180); note.add_theme_font_size_override("font_size",22)
	note.add_theme_color_override("font_color",Color.WHITE); note.add_theme_color_override("font_shadow_color",Color.BLACK)
	note.add_theme_constant_override("shadow_offset_x",2); note.add_theme_constant_override("shadow_offset_y",2); root.add_child(note)
	for frame in 180:
		if frame in [21,90]:
			view.animation_player.speed_scale = .5 if frame == 90 else 1.0
			attack.next_attack = 0; verify(attack.attack(),"recorded world punch starts at frame "+str(frame))
		view._process(1.0/30.0)
		note.text = "EMPTY HANDS / WORLD CONTACT / " + ("0.5x" if frame >= 90 else "1x")
		await process_frame; RenderingServer.force_draw(false); RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(folder+"/%03d.png"%frame)
	view.animation_player.speed_scale = 1.0; note.free()
func finish() -> void:
	game.shutdown_requested = true
	verify(await game.terrain.shutdown_after_edits(),"temporary world closes with edits settled")
	game.free(); await process_frame; await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports/unarmed")
	FileAccess.open("res://reports/unarmed/world.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"impacts":impacts},"\t"))
	print("HUMAN_UNARMED_WORLD checks=",checks," failures=",failures); quit(1 if failures else 0)
