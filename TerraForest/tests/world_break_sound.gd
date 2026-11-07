# SPDX-License-Identifier: 0BSD
extends SceneTree
## Breakage sounds must follow the material: stone, wood, metal, dirt, vegetation.

const STONE_HIT := "Pickaxe on Stone 3 - Kaino_hit1.wav"
const DIRT_HIT := "Stone Crumble 1 - Kaino_hit1.wav"
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
	var attack = game.world_attack
	attack.pending = {"identity": 7, "item": 1, "slot": 0, "epoch": game.terrain.epoch, "contacted": false, "repairing": false}
	attack.attack()
	check(not attack.queued_click, "the held-button poll does not queue an extra swing")
	attack.attack(false, true)
	check(attack.queued_click, "a press during a swing is remembered")
	attack.finish_swing(7, true)
	check(not attack.queued_click, "the remembered press is consumed when the swing ends")
	attack.pending = {}
	var feedback = game.player_hud.damage_feedback
	game.player_hud.developer_belt = false
	game.player_hud.inventory_open = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	game.player_hud.show_target_damage("Building block", 90, 100)
	check(feedback.amount_label.text == "90 / 100", "the durability HUD shows the first hit value")
	game.player_hud.show_target_damage("Wooden block", 70, 100)
	check(feedback.name_label.text == "Wooden block" and feedback.amount_label.text == "70 / 100", "the durability HUD refreshes for the next block")
	check(attack.break_event({"kind": "block", "material": "stone"}) == "world.break.stone", "stone block uses the stone break event")
	check(attack.break_event({"kind": "block", "material": "wood"}) == "world.break.wood", "wood block uses the wood break event")
	check(attack.break_event({"kind": "tree", "material": "wood"}) == "world.break.wood", "tree uses the wood break event")
	check(attack.break_event({"kind": "terrain", "surface": "dirt"}) == "world.break.dirt", "dirt surface uses the dirt break event")
	game.material_id = 1
	check(attack.break_event({"kind": "terrain"}) == "world.break.dirt", "untouched ground defaults to dirt, not stone")
	game.material_id = 2
	check(attack.break_event({"kind": "terrain"}) == "world.break.wood", "wood terrain uses the wood break event")
	game.material_id = 3
	check(attack.break_event({"kind": "terrain"}) == "world.break.metal", "metal terrain uses the metal break event")
	var here: Vector3 = game.player.global_position
	audio.surface_cache = {"position": here, "surface": "dirt", "revision": game.terrain.native_revision}
	check(attack.break_event({"kind": "terrain", "position": here}) == "world.break.dirt", "sampled dirt ground uses the dirt break event")
	audio.surface_cache["surface"] = "grass"
	check(attack.break_event({"kind": "terrain", "position": here}) == "world.break.vegetation", "sampled grass ground uses the vegetation break event")
	audio.surface_cache["surface"] = "rock"
	check(attack.break_event({"kind": "terrain", "position": here}) == "world.break.stone", "sampled rock ground uses the stone break event")
	audio.surface_cache["revision"] = game.terrain.native_revision - 1
	game.material_id = 2
	check(attack.break_event({"kind": "terrain", "position": here}) == "world.break.wood", "a stale sample falls back to the carved material")
	audio.surface_cache = {}
	game.material_id = 1
	audio.surface_cache = {"position": here, "surface": "dirt", "revision": game.terrain.native_revision}
	game._break_sound(here)
	await process_frame
	check(audio.audio.previous.has("world.break.dirt"), "developer removal uses the sampled material")
	audio.surface_cache = {}
	check(attack.break_event({"kind": "cover", "material": "stone"}) == "world.break.stone", "stone boulder uses the stone break event")
	check(attack.break_event({"kind": "cover", "material": "wood"}) == "world.break.vegetation", "plant cover uses the vegetation break event")
	check(attack.break_event({"kind": "model", "material": "metal"}) == "world.break.metal", "metal object uses the metal break event")
	check(attack.break_event({"kind": "actor", "material": "other"}) == "world.break.block", "an unknown material falls back to the generic event")
	var stone_row: Dictionary = audio.audio.catalog.sounds.get("world.break.stone", {})
	var dirt_row: Dictionary = audio.audio.catalog.sounds.get("world.break.dirt", {})
	check(str(stone_row.get("files", [""])[0]).ends_with(STONE_HIT + ":once"), "stone event resolves to the assigned hit")
	check(str(dirt_row.get("files", [""])[0]).ends_with(DIRT_HIT + ":once"), "dirt event resolves to the assigned hit")
	var metal_row: Dictionary = audio.audio.catalog.sounds.get("world.break.metal", {})
	check(str(metal_row.get("files", [""])[0]).ends_with("Sword Hits Armor 1 - Kaino.wav:once"), "metal event resolves to the assigned metal hit")
	var wood_row: Dictionary = audio.audio.catalog.sounds.get("world.break.wood", {})
	var plant_row: Dictionary = audio.audio.catalog.sounds.get("world.break.vegetation", {})
	check(str(wood_row.get("files", [""])[0]).ends_with("Chopping Wood 2 - Kaino_hit3.wav:once"), "wood event resolves to the assigned wood hit")
	check(str(plant_row.get("files", [""])[0]).ends_with("Wood Snap 2 - Kaino_hit2.wav:once"), "vegetation event resolves to the assigned plant hit")
	audio.audio.listener = game.player.global_position
	audio.play_event("world.break.vegetation", game.player.global_position + Vector3(0, 1, 1))
	await process_frame
	check(audio.audio.previous.has("world.break.vegetation"), "vegetation breakage starts a voice")
	audio.play_event("world.break.metal", game.player.global_position + Vector3(0, 1, 1))
	await process_frame
	check(audio.audio.previous.has("world.break.metal"), "metal breakage starts a voice")
	attack.break_sound({"kind": "block", "material": "stone", "position": game.player.global_position + Vector3(0, 1, 1)})
	await process_frame
	check(audio.audio.previous.has("world.break.stone"), "stone breakage starts a voice")
	print("WORLD_BREAK_SOUND checks=", checks, " failures=", failures)
	game.shutdown_requested = true
	await game.terrain.shutdown_after_edits()
	game.free()
	quit(1 if failures > 0 else 0)
