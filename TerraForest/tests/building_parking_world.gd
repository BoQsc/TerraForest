# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"

var game: Node
var expected: Dictionary = {}
var motion: Array = []
var measuring := false
var frame_times: Array[float] = []
var previous_frame := 0

func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if measuring and previous_frame > 0 and frame_times.size() < 2400: frame_times.append((now - previous_frame) * .001)
	previous_frame = now
	return false

func walk_to_car(path: PackedVector3Array) -> bool:
	game.player.global_position = path[-1] + Vector3.UP * .06
	game.player.velocity = Vector3.ZERO
	for index in range(path.size() - 2, -1, -1):
		var deadline := Time.get_ticks_msec() + 7000
		while Time.get_ticks_msec() < deadline:
			await physics_frame
			var offset: Vector3 = path[index] - game.player.global_position
			offset.y = 0
			if offset.length() < .12: break
			var velocity := offset.normalized() * 2.5
			velocity.y = game.player.velocity.y - 20.0 / Engine.physics_ticks_per_second
			game.player.velocity = velocity
			game.player.move_and_slide()
		if game.player.global_position.distance_to(path[index]) > .35: return false
	game.player.velocity = Vector3.ZERO
	return true

func same_fleet(storage: RefCounted, wanted: PackedByteArray, actual: PackedByteArray) -> Dictionary:
	var before: Dictionary = storage.decode_fleet(wanted)
	var after: Dictionary = storage.decode_fleet(actual)
	var valid: bool = before.ok and after.ok and before.next_identity == after.next_identity and before.records.size() == after.records.size()
	var position_error := 0.0
	var basis_error := 0.0
	if valid:
		for index in before.records.size():
			var first: Dictionary = before.records[index]
			var second: Dictionary = after.records[index]
			valid = valid and first.identity == second.identity and first.get("kind", "terraforest.ranger.v1") == second.get("kind", "terraforest.ranger.v1") and first.get("state", PackedByteArray()) == second.get("state", PackedByteArray())
			position_error = maxf(position_error, first.pose.origin.distance_to(second.pose.origin))
			for column in 3: basis_error = maxf(basis_error, first.pose.basis[column].distance_to(second.pose.basis[column]))
	return {"ok": valid and position_error == 0 and basis_error < .000002, "position_error_m": position_error, "basis_error": basis_error, "byte_identical": wanted == actual, "expected": before, "restored": after}

func _initialize() -> void:
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	ProjectSettings.set_setting("terraforest/offscreen_session", true)
	super._initialize()

func run() -> void:
	var reopening := "--parking-reopen" in OS.get_cmdline_user_args()
	change_scene_to_file("res://demo/worlds.tscn"); await scene_changed
	if not check(await wait_for(browser_catalog_ready), "ordinary browser loads"): await finish(); return
	var browser := current_scene
	var report := ""
	if reopening:
		expected = FileAccess.open(folder.path_join("expected.bin"), FileAccess.READ).get_var()
		if not check(str(expected.slot).begins_with("Parking_"), "only owned parking save is reopened"): await finish(); return
		var selected := -1
		for index in browser.worlds.item_count:
			if browser.worlds.get_item_metadata(index) == expected.slot: selected = index; break
		if not check(selected >= 0, "published parking world appears in My worlds"): await finish(); return
		browser.worlds.select(selected); browser.launch_selected(false)
	else:
		expected.slot = "Parking_1703_" + Crypto.new().generate_random_bytes(4).hex_encode()
		FileAccess.open(folder.path_join("created_slot.json"), FileAccess.WRITE).store_string(JSON.stringify({"slot": expected.slot}))
		browser.name_field.text = expected.slot; browser.seed_field.value = 1703; browser.world_tabs.current_tab = 1
		check(browser.selected_options() == preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS, "normal default recipe without development content flags")
		browser.generate_button.pressed.emit()
		if not check(await wait_for(func() -> bool: return browser.preparation_job != null and browser.preparation_job.task != null and not browser.preparation_job.task.report.is_empty(), 15), "owned generation directory available"): await finish(); return
		report = browser.preparation_job.task.report
	if not check(await wait_for(game_ready, 520), "normal world flow reaches play"): await finish(); return
	game = current_scene; game.background_fps = 60; game.app_focused = true
	game.set_physics_process(false); game._clear_motion(); game.zombies.update(0, game.player.global_position, false)
	var session: Node = game.world_vehicle
	session.interaction_available = func() -> bool: return not game.loading_active
	if reopening:
		var restored: PackedByteArray = session.fleet.capture_storage_snapshot()
		var comparison := same_fleet(session.storage, expected.fleet, restored)
		FileAccess.open(folder.path_join("fleet-comparison.json"), FileAccess.WRITE).store_string(JSON.stringify(comparison, "  "))
		check(comparison.ok, "fresh process preserves exact positions, identities and module state with quaternion float-roundtrip tolerance")
	else:
		var parking_file := report.path_join("building_parking.bin")
		if not check(FileAccess.file_exists(parking_file), "normal generation produces parking evidence"): await finish(); return
		var generated: Dictionary = FileAccess.open(parking_file, FileAccess.READ).get_var()
		expected.placements = generated.placements
		FileAccess.open(folder.path_join("generation.json"), FileAccess.WRITE).store_string(JSON.stringify(generated, "  "))
		check(generated.ok and generated.placements.size() > 0, "normal publication contains native parked vehicles")
		var kinds: Dictionary = {}
		for row: Dictionary in generated.placements: kinds[row.building] = true
		check(kinds.has("house_c1") and kinds.has("warehouse_w1"), "both garages and warehouses receive usable vehicles")
	var visited: Dictionary = {}
	for row: Dictionary in expected.placements:
		if visited.has(row.building): continue
		visited[row.building] = true
		var record: Dictionary = session.fleet.get_record(row.id)
		if not check(record.present and record.kind == session.Packs.DEFAULT, "native saved vehicle exists: " + row.building): continue
		if not reopening: check(record.pose.is_equal_approx(row.pose), "initial generation publication restores exact untouched bay transform")
		game.teleport(record.pose.origin, record.pose.origin.y + 2)
		if not check(await wait_for(game_ready, 120) and await wait_for(func() -> bool: return session.activation.residents.has(row.id), 30), "normal streaming admits parked vehicle: " + row.building): continue
		game.app_focused = true; game.set_physics_process(false); game.zombies.update(0, game.player.global_position, false)
		var body: RigidBody3D = session.activation.residents[row.id]
		check(body.freeze and not body.is_physics_processing(), "unoccupied car has no active driving simulation")
		var viewer := Camera3D.new(); viewer.cull_mask = game.camera.cull_mask & ~((1 << 18) | (1 << 19)); game.add_child(viewer); viewer.current = true
		viewer.global_position = row.portal + row.pose.basis.z * 4 + Vector3.UP * 2.5
		viewer.look_at(body.global_position)
		for frame in 20: await physics_frame
		await photograph(row.building + ("_restored" if reopening else "_parked"))
		if not reopening:
			check(await walk_to_car(row.walk), "actual player capsule walks from loading entrance around parked car")
			for frame in 4: await physics_frame
			var entered: bool = session.enter(game, row.id)
			check(entered, "actual vehicle entry from reserved pedestrian aisle")
			if entered:
				check(session.safe_exit_position(game).is_finite(), "production exit solver finds clear supported space inside building")
				var exited: String = session.exit_vehicle(game)
				check(not session.driving, "actual exit inside bay: " + exited)
				for frame in 40: await physics_frame
				game.player.global_position = row.walk[0] + Vector3.UP * .06
				if check(session.enter(game, row.id), "re-enter parked car before driving"):
					frame_times.clear(); previous_frame = 0; measuring = true
					body.autonomous_controls = func(_delta: float) -> Dictionary: return {"throttle": .25, "brake": 0.0, "hold": false}
					var began := Time.get_ticks_msec()
					var held := 0
					var crossed := false
					while Time.get_ticks_msec() - began < 18000:
						await physics_frame
						if body.streaming.waiting: held += 1
						if (body.global_position - row.portal).dot(row.pose.basis.z) > 2.6: crossed = true; break
					body.autonomous_controls = func(_delta: float) -> Dictionary: return {"hold": true}
					for frame in 240:
						await physics_frame
						if body.linear_velocity.length() < .15: break
					measuring = false; frame_times.sort()
					motion.append({"building": row.building, "crossed": crossed, "held_ticks": held, "seconds": (Time.get_ticks_msec() - began) * .001, "position": body.global_position, "frames": frame_times.size(), "p95_ms": frame_times[mini(frame_times.size() - 1, floori(frame_times.size() * .95))] if not frame_times.is_empty() else 0, "worst_ms": frame_times[-1] if not frame_times.is_empty() else 0})
					check(crossed, "native vehicle physically drives through existing bay opening")
					check(body.linear_velocity.length() < .2, "service brake stops departed vehicle")
					var left: String = session.exit_vehicle(game)
					check(not session.driving, "exit outside building: " + left)
					body.autonomous_controls = Callable()
					for frame in 90: await physics_frame
		viewer.free(); game.camera.current = true
	var saved_fleet: RefCounted = session.fleet
	if not reopening:
		check(await wait_for(func() -> bool: return session.coasting.is_empty(), 15), "departed vehicles finish parking before saving")
		check(not session.capture_snapshot().is_empty(), "native fleet snapshot includes driven vehicle state")
		FileAccess.open(folder.path_join("motion.json"), FileAccess.WRITE).store_string(JSON.stringify(motion, "  "))
	check(await leave(), "ordinary Save and return persists generated vehicles")
	if not reopening:
		expected.fleet = saved_fleet.capture_storage_snapshot()
		FileAccess.open(folder.path_join("expected.bin"), FileAccess.WRITE).store_var(expected)
	await finish()

func finish() -> void:
	if is_instance_valid(game) and game.is_inside_tree():
		game.shutdown_requested = true; await game.terrain.shutdown_after_edits()
	if is_instance_valid(current_scene): current_scene.free()
	await process_frame
	print("BUILDING_PARKING_WORLD checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
