# SPDX-License-Identifier: 0BSD
extends SceneTree
## A silent event must be visible in the log, and an assignment must take effect
## in a running world without a restart.

const LOG_PATH := "user://audio_events.log"
const LIVE := "user://live_mapping_test.json"
const HIT_A := "res://addons/audio_runtime/packs/Kaino/1/split/Pickaxe on Stone 3 - Kaino_hit1.wav"
const HIT_B := "res://addons/audio_runtime/packs/Kaino/1/split/Rockfall 1 - Kaino_hit1.wav"
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func read_log() -> String:
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path(LOG_PATH))

func write_map(path: String, mapping: Dictionary) -> void:
	var handle := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	handle.store_string(JSON.stringify({"schema": 1, "pack": "Kaino", "selection": mapping, "notes": {}, "deferred_sounds": [], "rejected_sounds": []}))
	handle.close()

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
	var start_log := read_log()
	check(start_log.contains("mapping ") and start_log.contains("entries from"), "session log records the mapping it loaded")
	write_map(LIVE, {"world.break.stone": HIT_A})
	audio.mapping_path = LIVE
	audio.reload_mapping(true)
	var row: Dictionary = audio.audio.catalog.sounds.get("world.break.stone", {})
	check(str(row.get("files", [""])[0]).ends_with(HIT_A.get_file() + ":once"), "mapping applies while the world runs")
	await create_timer(1.2).timeout
	write_map(LIVE, {"world.break.stone": HIT_B})
	audio.reload_mapping()
	row = audio.audio.catalog.sounds.get("world.break.stone", {})
	check(str(row.get("files", [""])[0]).ends_with(HIT_B.get_file() + ":once"), "a changed selection is picked up without a restart")
	audio.audio.listener = game.player.global_position
	var quiet_generic: int = audio.audio.statistics().active
	audio.play_event("world.break.block", game.player.global_position)
	await process_frame
	check(audio.audio.statistics().active == quiet_generic and read_log().contains("world.break.block skipped"), "an unassigned generic break stays silent")
	await create_timer(1.2).timeout
	write_map(LIVE, {"world.break.stone": HIT_B, "world.break.wood": HIT_A})
	audio.reload_mapping()
	var wood_row: Dictionary = audio.audio.catalog.sounds.get("world.break.wood", {})
	check(str(wood_row.get("files", [""])[0]).ends_with(HIT_A.get_file() + ":once"), "wood follows an assignment made after load")
	audio.play_event("world.break.wood", game.player.global_position)
	await process_frame
	check(audio.audio.previous.has("world.break.wood"), "wood break plays with the assigned sound")
	audio.audio.listener = game.player.global_position
	game.world_attack.break_sound({"kind": "block", "material": "stone", "position": game.player.global_position + Vector3(0, 1, 1)})
	await process_frame
	var event_log := read_log()
	check(event_log.contains("event world.break.stone -> ") and event_log.contains(HIT_B.get_file()), "log names the event and the file it played")
	check(audio.audio.previous.has("world.break.stone"), "the logged event started a voice")
	print("WORLD_AUDIO_DIAGNOSTICS checks=", checks, " failures=", failures)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(LIVE))
	game.shutdown_requested = true
	await game.terrain.shutdown_after_edits()
	game.free()
	quit(1 if failures > 0 else 0)
