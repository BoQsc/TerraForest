# SPDX-License-Identifier: 0BSD
extends SceneTree
## The world must play the assigned breakage sound through the real adapter.

const WANTED := "Pickaxe on Stone 3 - Kaino_hit1.wav"
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void:
	ProjectSettings.set_setting("terraforest/session_arguments", PackedStringArray([
		"--world-slot=Crystal_Creek", "--no-zombies", "--max-fps=60", "--temporary",
	]))
	var game = load("res://demo/world.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	run.call_deferred(game)

func run(game) -> void:
	var waited := 0.0
	while waited < 120.0 and game.get("startup_complete") != true:
		await create_timer(1.0).timeout
		waited += 1.0
	var audio = game.get_node_or_null("WorldAudio")
	if audio != null and not audio.initialized:
		audio.initialize()
		await create_timer(1.0).timeout
	check(audio != null and audio.initialized, "world audio adapter is running")
	if audio == null or not audio.initialized:
		quit(1)
		return
	var row: Dictionary = audio.audio.catalog.sounds.get("world.break.block", {})
	check(not row.is_empty(), "breakage event is admitted")
	check(str(row.get("files", [""])[0]).ends_with(WANTED + ":once"), "breakage event uses the assigned sound")
	check(game.world_attack.has_method("break_sound"), "break path emits the event")
	audio.audio.listener = game.player.global_position
	game.world_attack.break_sound({"position": game.player.global_position + Vector3(0, 1, 1)})
	await process_frame
	check(audio.audio.statistics().active > 0 and audio.audio.previous.has("world.break.block"), "breakage starts a voice")
	print("WORLD_BREAK_SOUND checks=", checks, " failures=", failures)
	game.shutdown_requested = true
	await game.terrain.shutdown_after_edits()
	game.free()
	quit(1 if failures > 0 else 0)
