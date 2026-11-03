# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
var game: Node
var expected: Dictionary = {}
var sampled := false

func measure(pool: Node3D, enabled: bool) -> Dictionary:
	pool.set_enabled(enabled)
	for frame in 15: await process_frame
	var samples: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in 120:
		await process_frame
		var now := Time.get_ticks_usec(); samples.append((now - previous) * .001); previous = now
	samples.sort()
	return {"enabled": enabled, "frames": samples.size(), "p95_ms": samples[113], "worst_ms": samples[-1], "pool": pool.statistics()}

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	ProjectSettings.set_setting("terraforest/offscreen_session", true)
	super._initialize()

func run() -> void:
	var reopening := "--lights-reopen" in OS.get_cmdline_user_args()
	change_scene_to_file("res://demo/worlds.tscn"); await scene_changed
	if not check(await wait_for(browser_catalog_ready), "normal browser opens"): await finish(); return
	var browser := current_scene
	var report := ""
	if reopening:
		expected = FileAccess.open(folder.path_join("expected.bin"), FileAccess.READ).get_var()
		if not check(str(expected.slot).begins_with("HouseLights_"), "only owned light fixture world reopened"): await finish(); return
		var found := -1
		for index in browser.worlds.item_count:
			if browser.worlds.get_item_metadata(index) == expected.slot: found = index; break
		if not check(found >= 0, "My worlds lists the generated light fixture save"): await finish(); return
		browser.worlds.select(found); browser.launch_selected(false)
	else:
		expected.slot = "HouseLights_1703_" + Crypto.new().generate_random_bytes(4).hex_encode()
		FileAccess.open(folder.path_join("created_slot.json"), FileAccess.WRITE).store_string(JSON.stringify({"slot": expected.slot}))
		browser.name_field.text = expected.slot; browser.seed_field.value = 1703; browser.world_tabs.current_tab = 1
		check(browser.selected_options() == preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS, "normal default recipe without review flags")
		browser.generate_button.pressed.emit()
		if not check(await wait_for(func() -> bool: return browser.preparation_job != null and browser.preparation_job.task != null and not browser.preparation_job.task.report.is_empty(), 15), "generation evidence path available"): await finish(); return
		report = browser.preparation_job.task.report
	if not check(await wait_for(game_ready, 520), "ordinary generation/loading reaches control"): await finish(); return
	game = current_scene; game.background_fps = 60; game.app_focused = true; game.set_physics_process(false); game._clear_motion()
	game.zombies.update(0, game.player.global_position, false)
	check(await wait_for(func() -> bool: return not game.player_view.entry.blocks_actions(), 15), "entry animation finishes before object interaction")
	var pool: Node3D = game.structures.resident_lights
	if not check(pool != null and pool.statistics().capacity == 4, "real world has one bounded native light pool"): await finish(); return
	if not reopening:
		var generated: Dictionary = FileAccess.open(report.path_join("house_lights.bin"), FileAccess.READ).get_var()
		FileAccess.open(folder.path_join("generation.json"), FileAccess.WRITE).store_string(JSON.stringify(generated, "  "))
		check(generated.ok and generated.placements.size() > 20, "ordinary generated homes contain breakable lights")
		expected.samples = {}; expected.counts = {}
		for row: Dictionary in generated.placements:
			if not expected.samples.has(row.asset): expected.samples[row.asset] = row
			if not expected.counts.has(row.asset): expected.counts[row.asset] = 0
			expected.counts[row.asset] += 1
		check(expected.samples.size() == 3, "lamps, torches and fireplaces all reachable in ordinary generation")
	for key: String in expected.samples:
		var sample: Dictionary = expected.samples[key]
		var collection: Node3D = game.structures.model(key)
		var point: Vector3 = sample.position
		game.teleport(point, point.y + 2)
		if not check(await wait_for(game_ready, 120), "normal streaming reaches light room"): continue
		game.app_focused = true; game.set_physics_process(false); game.zombies.update(0, game.player.global_position, false)
		if reopening:
			check(collection.get_instance(sample.id).is_empty(), "broken light does not return after fresh load: " + key)
			continue
		if not check(await wait_for(func() -> bool: return not collection.get_instance(sample.id).is_empty(), 15), "native light object is resident"): continue
		pool.set_focus(point)
		check(await wait_for(func() -> bool: return active(pool, key, sample.id), 10), "GLB prop owns a live pooled light")
		var viewer := Camera3D.new(); viewer.cull_mask = game.camera.cull_mask & ~((1 << 18) | (1 << 19)); game.add_child(viewer); viewer.current = true
		var bounds: AABB = collection.survey_prototype_bounds()
		var target := point + bounds.get_center()
		for direction: Vector3 in [Vector3(1,0,1), Vector3(-1,0,1), Vector3(1,0,-1), Vector3(-1,0,-1)]:
			viewer.global_position = point + direction.normalized() * 2.5 + Vector3.UP * 1.5
			viewer.look_at(target)
			var hit: Dictionary = game.structures.blocks.raycast_scene(viewer.global_position, target, 7, [game.player.get_rid()], true)
			if hit.get("collider") == collection: break
		for frame in 12: await physics_frame
		await photograph(key.get_slice("/", 1))
		if not sampled:
			var costs: Array = [await measure(pool, false), await measure(pool, true)]
			FileAccess.open(folder.path_join("light-cost.json"), FileAccess.WRITE).store_string(JSON.stringify(costs, "  "))
			sampled = true
		var inventory: RefCounted = game.player_hud.inventory
		var before := material_counts(inventory)
		var profile := preload("res://addons/player_runtime/durability_catalog.gd").model_profile(key, game.structures.object_definitions)
		var attack: Dictionary = {"kind": "model", "key": "model:" + key + ":" + str(sample.id), "id": sample.id, "collection": collection, "asset": key, "health": profile.health, "material": profile.material, "name": profile.name}
		game.equipped_tool = 3; game.player_hud.equip(2)
		var hits := 0
		while not attack.get("destroyed", false) and hits < 20:
			hits += 1
			if not game.world_attack.apply_target(attack): break
		check(attack.get("destroyed", false) and collection.get_instance(sample.id).is_empty(), "real player hit adapter breaks the light prop")
		check(await wait_for(func() -> bool: return not active(pool, key, sample.id), 3), "destroyed object loses its real light")
		check(material_counts(inventory) != before, "breaking the object grants ordinary salvage")
		viewer.free(); game.camera.current = true
	if reopening:
		check(game.player_hud.inventory.capture_storage_snapshot() == expected.inventory, "fresh process preserves the gained salvage exactly")
	else:
		expected.inventory = game.player_hud.inventory.capture_storage_snapshot()
		FileAccess.open(folder.path_join("expected.bin"), FileAccess.WRITE).store_var(expected)
	FileAccess.open(folder.path_join("pool.json"), FileAccess.WRITE).store_string(JSON.stringify(pool.statistics(), "  "))
	check(await leave(), "normal Save and return publishes broken light state")
	await finish()

func active(pool: Node3D, key: String, identity: int) -> bool:
	var keys: Array = game.structures.resident_lights.get_meta("source_keys", [])
	for row: Dictionary in pool.statistics().lights:
		if row.source < keys.size() and keys[row.source] == key and row.id == identity: return true
	return false

func material_counts(inventory: RefCounted) -> Dictionary:
	var counts: Dictionary = {}
	for slot: Dictionary in inventory.snapshot().slots:
		if slot.item in [101, 102, 103, 104]: counts[slot.item] = counts.get(slot.item, 0) + slot.count
	return counts

func finish() -> void:
	if is_instance_valid(game) and game.is_inside_tree(): game.shutdown_requested = true; await game.terrain.shutdown_after_edits()
	if is_instance_valid(current_scene): current_scene.free()
	RenderingServer.force_sync()
	for frame in 12: await process_frame
	print("HOUSE_LIGHTS_WORLD checks=%d failures=%d" % [checks, failures]); quit(1 if failures else 0)
