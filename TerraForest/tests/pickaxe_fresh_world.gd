# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var impacts: Array = []
var checks := 0
func verify(ok: bool, label: String) -> bool:
	checks += 1
	return check(ok, label)
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This input integration check requires a graphical display: headless Godot cannot capture the mouse.")
		quit(2); return
	# An offscreen graphical window supports real mouse-mode admission without
	# taking fullscreen focus from a user's running playtest.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.position = Vector2i(-32000, -32000)
	ProjectSettings.set_setting("terraforest/offscreen_session", true)
	evidence = "res://reports/pickaxe_fresh/world"
	DirAccess.make_dir_recursive_absolute(evidence)
	game = load("res://demo/world.tscn").instantiate()
	game.temporary_world = true
	game.background_fps = 60
	game.player_view.settings_path = ""
	root.add_child(game)
	if not verify(await wait_for(func(): return not game.loading_active and not game.needs_floor_spawn, 60), "ordinary temporary world becomes playable"):
		await finish(); return
	game.set_physics_process(false)
	ProjectSettings.set_setting("terraforest/offscreen_session", false)
	game._clear_motion()
	game.zombies.clear()
	if game.session_menu.developer: game.session_menu.toggle_developer()
	game.session_menu.set_open(false)
	var hud = game.player_hud
	hud.equip_item(1)
	var view = game.tool_view.human
	view.set_process(false)
	verify(view.active_clip == "FP_Pickaxe_Fresh_Idle" and is_equal_approx(game.tool_view.attack_profile().duration, 1.7), "ordinary equipment path selects the accepted hold and full cycle")
	var origin: Vector3 = game.player.position + Vector3(15, 50, 15)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin, origin - Vector3.UP * 200, 1))
	if not verify(not hit.is_empty(), "loaded native terrain provides a real target"):
		await finish(); return
	game.player.position = hit.position + Vector3.UP * .2
	game.app_focused = true; game.fly = false; game.needs_floor_spawn = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.camera.global_position = hit.position + Vector3.UP * 2
	game.camera.look_at(hit.position, Vector3.FORWARD)
	var attack = game.world_attack
	verify(attack.target().get("kind") == "terrain", "pickaxe targets terrain through the normal reach query")
	attack.impact_resolved.connect(func(identity: int, accepted: bool): impacts.append({"identity": identity, "accepted": accepted, "time": view.animation_player.current_animation_position}))
	var revision: int = game.terrain.density_revision
	var wear: int = hud.inventory.snapshot().slots[hud.active_slot].wear
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT; click.pressed = true
	Input.parse_input_event(click); Input.flush_buffered_events()
	print("PICKAXE_INPUT ", JSON.stringify({"admitted": game._model_edit_available(), "focused": game.app_focused, "mouse": Input.mouse_mode, "ui": game.session_menu.visible_ui(), "item": game.equipped_tool, "slot": hud.active_slot, "profile": game.tool_view.attack_profile(), "visible": game.tool_view.is_visible_in_tree(), "pending": attack.pending}))
	await process_frame
	game._update_edit(.1)
	click = InputEventMouseButton.new(); click.button_index = MOUSE_BUTTON_LEFT
	Input.parse_input_event(click); Input.flush_buffered_events()
	verify(not attack.pending.is_empty() and view.active_clip == "FP_Pickaxe_Fresh_Swing", "real mouse input starts the new default through world attack")
	view._process(.54)
	verify(impacts.is_empty() and game.terrain.density_revision == revision and hud.inventory.snapshot().slots[hud.active_slot].wear == wear, "old contact time cannot dig or consume durability during the new windup")
	view._process(.4)
	verify(impacts.size() == 1 and impacts[0].accepted and is_equal_approx(impacts[0].time, 50.0 / 60.0), "one real excavation is accepted at authored frame 50 even across a long frame")
	verify(await wait_for(func(): return not game.terrain.pending_edit, 20) and game.terrain.density_revision > revision and not game.mining_rewards.failed, "native terrain publishes excavation and mining reward processing")
	verify(hud.inventory.snapshot().slots[hud.active_slot].wear == wear + 1, "one strike consumes durability exactly once")
	view._process(1.0)
	verify(attack.pending.is_empty() and view.active_clip == "FP_Pickaxe_Fresh_Idle", "full recovery releases the attack and returns to the same grip")
	attack.next_attack = 0
	verify(attack.attack(), "the next stroke is admitted after recovery")
	hud.equip_item(2)
	view._process(2.0)
	verify(attack.pending.is_empty() and impacts.size() == 1 and game.tool_view.attack_profile().clip == "FP_Axe_Swing", "switching tools cancels an uncontacted stroke without an extra hit")
	await finish()
func finish() -> void:
	game.shutdown_requested = true
	verify(await game.terrain.shutdown_after_edits(), "temporary world closes with edits settled")
	game.free(); await process_frame; await process_frame
	FileAccess.open(evidence + "/result.json", FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "impacts": impacts, "scope": "Ordinary scene, equipment, mouse input, native terrain and mining pipeline; no geometric tip alignment claim."}, "\t"))
	print("PICKAXE_FRESH_WORLD checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
