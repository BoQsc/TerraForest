# SPDX-License-Identifier: 0BSD
extends SceneTree
## The running world must play the event ids the audition introduced.

const EVENTS := ["npc.zombie.attack", "npc.zombie.hit", "npc.zombie.death", "player.hurt", "vehicle.door.open", "vehicle.door.close", "world.break.block"]
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
	check(game.get("startup_complete") == true, "world reaches playable state")
	var adapter = game.get_node_or_null("WorldAudio")
	if adapter != null and not adapter.initialized:
		adapter.initialize()
		await create_timer(1.0).timeout
	check(adapter != null and adapter.initialized, "world audio adapter is running")
	if adapter == null or not adapter.initialized:
		quit(1)
		return
	for id: String in EVENTS:
		check(adapter.audio.catalog.sounds.has(id), "admitted event " + id)
	adapter.audio.listener = game.player.global_position
	var point: Vector3 = game.player.global_position + Vector3(0, 1, 1)
	var before: int = adapter.audio.statistics().active
	adapter.play_event("npc.zombie.attack", point)
	await process_frame
	check(adapter.audio.statistics().active > before and adapter.audio.previous.has("npc.zombie.attack"), "zombie attack starts a mapped voice")
	var after: int = adapter.audio.statistics().active
	adapter.hurt(1.0)
	await process_frame
	check(adapter.audio.statistics().active > 0 and adapter.audio.previous.has("player.hurt"), "player damage starts the hurt event")
	print("WORLD_AUDIO_EVENTS checks=", checks, " failures=", failures)
	game.shutdown_requested = true
	await game.terrain.shutdown_after_edits()
	game.free()
	quit(1 if failures > 0 else 0)
