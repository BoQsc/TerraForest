# SPDX-License-Identifier: 0BSD
extends SceneTree
var game: Node
var failures := 0
var checks := 0

func check(value: bool, label: String) -> bool:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1
	return value

func wait_for(predicate: Callable, seconds: int = 15) -> bool:
	var deadline := Time.get_ticks_msec() + seconds * 1000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		if is_instance_valid(game): game.app_focused = true
		await process_frame
	return predicate.call()

func _initialize() -> void: run.call_deferred()

func run() -> void:
	ProjectSettings.set_setting("terraforest/offscreen_session", true)
	game = load("res://demo/world.tscn").instantiate(); game.temporary_world = true; game.background_fps = 60
	game.player_view.settings_path = ""; root.add_child(game); current_scene = game
	root.get_node("WorldSession")._attach_optional_audio()
	if not check(await wait_for(func(): return not game.loading_active and not game.needs_floor_spawn, 75), "temporary real world reaches play"): await finish(); return
	var omitted := "--no-audio" in OS.get_cmdline_user_args()
	check(game.has_node("WorldAudio") != omitted, "session host honors optional module flag")
	if omitted: await finish(); return
	var adapter: Node3D = game.get_node("WorldAudio")
	if not check(await wait_for(func(): return adapter.initialized), "session host attaches audio after startup"): await finish(); return
	game.set_physics_process(false); game._clear_motion(); adapter.timer.stop()
	game.session_menu.set_open(false); game.player_view.entry.finish()
	check(game.session_menu.pages.has("Audio") and adapter.audio.catalog.packs == ["nox.essentials.v1"], "real menu exposes sound controls and bundled pack")
	var base: Vector3 = game.player.position + Vector3(0, 8, 0)
	var cell := Vector3i(base.floor())
	game.structures.blocks.set_focus(Vector3(cell))
	game.structures.blocks.set_cells(PackedInt32Array([cell.x, cell.y, cell.z, 33]))
	var point := Vector3(cell) + Vector3(.5, 1.02, .5)
	if check(await wait_for(func(): return not game.structures.blocks.raycast_scene(point + Vector3.UP, point - Vector3.UP * .5, 7, [game.player.get_rid()]).is_empty()), "authored wood floor has actual published collision"):
		adapter.audio.listener = point + Vector3.UP
		var before: int = adapter.audio.played
		adapter.footstep(point, "walk")
		check(adapter.last_surface == "wood" and adapter.audio.played == before + 1, "real ground hit selects wood footstep")
		adapter.audio.set_enabled(false); adapter.footstep(point, "run")
		check(adapter.audio.played == before + 1 and adapter.audio.statistics().active == 0, "muting stops presentation without touching the floor")
		check(game.structures.blocks.get_cell(cell) == 33, "audio does not mutate gameplay data")
		adapter.audio.set_enabled(true)
	var handle: int = adapter.audio.start_loop("fire.burn", {"position": adapter.audio.listener})
	check(handle > 0, "real world supports spatial fire loop")
	adapter.reset_world()
	check(adapter.audio.statistics().active == 0 and adapter.pending.is_empty() and adapter.fire_handles.is_empty(), "epoch reset retires voices and pending queries")
	adapter.audio.listener = game.camera.global_position
	game.tool_view.human.equip(6)
	adapter.soundscape()
	check(adapter.fire_handles.has("held-torch"), "visible held torch registers its physical fire source")
	game.tool_view.human.equip(0)
	adapter.soundscape()
	check(not adapter.fire_handles.has("held-torch"), "putting away torch retires its fire sound")
	game.session_menu.set_open(true); adapter.tick()
	check(adapter.audio.statistics().active == 0, "paused menu suppresses world sound")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--audio-screenshot=") and DisplayServer.get_name() != "headless":
			game.session_menu.show_page("Audio")
			await process_frame; await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(argument.trim_prefix("--audio-screenshot="))
	await finish()

func finish() -> void:
	if is_instance_valid(game):
		game.shutdown_requested = true
		await game.terrain.shutdown_after_edits()
		game.free()
	await process_frame; await process_frame
	print("AUDIO_WORLD checks=%d failures=%d" % [checks, failures]); quit(1 if failures else 0)
