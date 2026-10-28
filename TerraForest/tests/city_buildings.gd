extends SceneTree

const Recipe = preload("res://reviews/city_buildings/recipes.gd")
var checks := 0
var failures := 0
var viewer: Node3D
var output := "res://reports/city_buildings"
var metrics: Array = []
var only := ""

func _initialize() -> void:
	run.call_deferred()

func check(accepted: bool, label: String) -> void:
	checks += 1
	if not accepted: failures += 1
	print("PASS " if accepted else "FAIL ", label)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="): output = argument.trim_prefix("--review-output=")
		if argument.begins_with("--building="): only = argument.trim_prefix("--building=")
	DirAccess.make_dir_recursive_absolute(output)
	if "--bake-city" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://reviews/city_buildings/baked")
		var blocks: Node3D = ClassDB.instantiate("NativeBlockWorld")
		for index in Recipe.IDS.size():
			var prefab: Resource = Recipe.build(blocks, index)
			check(prefab != null and ResourceSaver.save(prefab, "res://reviews/city_buildings/baked/" + Recipe.IDS[index] + ".tres") == OK, "bake " + Recipe.IDS[index])
		blocks.free()
	viewer = preload("res://reviews/city_buildings/viewer.gd").new()
	root.add_child(viewer)
	for index in Recipe.IDS.size():
		if not only.is_empty() and only != Recipe.IDS[index]: continue
		var started := Time.get_ticks_usec()
		if index > 0: viewer.select_building(index)
		check(viewer.ready_ok, "native publication " + Recipe.IDS[index])
		if not viewer.ready_ok:
			print(viewer.placement_results)
			diagnose_attachments()
			continue
		var blocks: Node3D = viewer.structures.blocks
		var expected: Resource = Recipe.build(blocks, index)
		check(expected.get_records() == viewer.asset.get_records(), "baked cells match recipe " + Recipe.IDS[index])
		check(expected.get_model_attachments() == viewer.asset.get_model_attachments(), "baked models match recipe " + Recipe.IDS[index])
		check(viewer.asset.get_meta("review_only", false), "proposal cannot be mistaken for approved production " + Recipe.IDS[index])
		var envelope_samples := PackedVector3Array()
		for shell: Dictionary in viewer.asset.get_meta("shells"):
			var rect: Rect2i = shell.rect
			for floor_index in range(1, shell.storeys):
				for column in range(rect.position.x, rect.end.x):
					for row in [rect.position.y, rect.end.y - 1]: envelope_samples.append(Vector3(column + .5, floor_index * 4 + .1, row + .5))
				for row in range(rect.position.y, rect.end.y):
					for column in [rect.position.x, rect.end.x - 1]: envelope_samples.append(Vector3(column + .5, floor_index * 4 + .1, row + .5))
		check(not blocks.sample_solid(envelope_samples).has(0), "no gaps between exterior storeys " + Recipe.IDS[index])
		var saved: PackedByteArray = viewer.structures.capture_storage_snapshot()
		check(viewer.structures.restore_storage_snapshot(saved) and saved == viewer.structures.capture_storage_snapshot(), "combined storage roundtrip " + Recipe.IDS[index])
		var records: PackedInt32Array = viewer.asset.get_records()
		var roof_cell := Vector3i.ZERO
		for offset in range(0, records.size(), 4):
			if records[offset + 1] > roof_cell.y: roof_cell = Vector3i(records[offset], records[offset + 1], records[offset + 2])
		var count: int = blocks.stats().cells
		check(blocks.set_cells(PackedInt32Array([roof_cell.x, roof_cell.y, roof_cell.z, 0])) and blocks.stats().cells == count - 1, "individually destroy topmost building block " + Recipe.IDS[index])
		viewer.select_view(2)
		check(blocks.stats().cells < count, "ground-floor cutaway " + Recipe.IDS[index])
		viewer.select_view(0)
		check(saved == viewer.structures.capture_storage_snapshot(), "cutaway restores every block and attachment " + Recipe.IDS[index])
		metrics.append({"id": Recipe.IDS[index], "cells": count, "models": viewer.asset.get_model_attachments().size(), "snapshot_bytes": saved.size(), "publish_verify_ms": (Time.get_ticks_usec() - started) / 1000.0})
		if "--pictures-only" not in OS.get_cmdline_user_args():
			viewer.toggle_doors()
			var doors: Node3D = viewer.structures.model(preload("res://addons/structures/door_catalog.gd").KEY)
			for identity in doors.get_ids(): check(viewer.hinges.is_open(identity), "working hinged door " + Recipe.IDS[index] + "/" + str(identity))
			blocks.flush_bakes()
			for frame in 30: await physics_frame
			check_roof_seams(index)
			await traverse(index)
		if DisplayServer.get_name() != "headless":
			for mode in viewer.MODES.size():
				viewer.select_view(mode)
				if mode == 3: viewer.toggle_doors()
				for frame in 20: await process_frame
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(output.path_join(Recipe.IDS[index] + "_" + str(mode) + ".png")) == OK, "capture " + Recipe.IDS[index] + "/" + str(mode))
			for floor_index in range(1, Recipe.FLOORS[index]):
				viewer.cutaway_floor = floor_index
				viewer.select_view(2)
				for frame in 12: await process_frame
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(output.path_join(Recipe.IDS[index] + "_floor_" + str(floor_index + 1) + ".png")) == OK, "capture upper floor " + Recipe.IDS[index] + "/" + str(floor_index + 1))
	viewer.free()
	await process_frame
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures, "buildings": metrics, "scope": "isolated proposals, native blocks/models/storage/traversal; no generated-city acceptance"}, "  "))
	print("CITY_BUILDINGS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func diagnose_attachments() -> void:
	var transaction: RefCounted = ClassDB.instantiate("NativePrefabPlacement")
	for attachment: Dictionary in viewer.asset.get_model_attachments():
		viewer.structures.restore_storage_snapshot(viewer.empty)
		var single: Resource = ClassDB.instantiate("NativeBlockPrefab")
		single.configure(viewer.asset.get_records())
		single.configure_model_attachments([attachment])
		var result: Dictionary = transaction.place(viewer.structures.blocks, single, Vector3i.ZERO, 0, viewer.structures.model_collections(), [])
		if not result.get("ok", false): print("ATTACHMENT_REJECTED ", attachment, " / ", result)

func check_roof_seams(index: int) -> void:
	for span: Dictionary in viewer.asset.get_meta("roof_spans", []):
		var closed := true
		for column in range(span.left + 1, span.right):
			for row in [span.back + 2.5, (span.back + span.front) * .5 + .5, span.front - 2.5]:
				var heights: Array[float] = []
				for offset in [-.02, .02]:
					var query := PhysicsRayQueryParameters3D.create(Vector3(column + offset, span.peak + 3, row), Vector3(column + offset, 6, row), 7)
					var hit: Dictionary = root.world_3d.direct_space_state.intersect_ray(query)
					if not hit.is_empty(): heights.append(hit.position.y)
				var joined := heights.size() == 2
				if joined and absf(heights[0] - heights[1]) >= .1:
					var lower := minf(heights[0], heights[1])
					var upper := maxf(heights[0], heights[1])
					for sample in range(1, 10):
						var height := lerpf(lower, upper, sample / 10.0)
						var solid: PackedByteArray = viewer.structures.blocks.sample_solid(PackedVector3Array([Vector3(column - .02, height, row), Vector3(column + .02, height, row)]))
						joined = joined and solid.has(1)
				if not joined: print("ROOF_GAP column=", column, " row=", row, " heights=", heights)
				closed = closed and joined
		check(closed, "continuous roof across every bay seam " + Recipe.IDS[index])

func traverse(index: int) -> void:
	var player := CharacterBody3D.new()
	player.collision_mask = 7
	player.collision_layer = 8
	player.floor_snap_length = .35
	player.floor_max_angle = deg_to_rad(48)
	player.floor_constant_speed = true
	player.safe_margin = .004
	var shape := CapsuleShape3D.new()
	shape.radius = .34
	shape.height = 1.8
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = .9
	player.add_child(collider)
	root.add_child(player)
	var motor: RefCounted = ClassDB.instantiate("NativePlayerMovement")
	for route: Dictionary in viewer.asset.get_meta("stair_routes", []):
		await route_walk(player, motor, route.start, route.end, Recipe.IDS[index] + " " + route.kind)
		await route_walk(player, motor, route.end, route.start, Recipe.IDS[index] + " reverse " + route.kind)
	for door: Dictionary in viewer.asset.get_meta("door_routes", []):
		var direction := Vector3.RIGHT if door.side else Vector3.BACK
		var start: Vector3 = door.center - direction * 1.1 + Vector3.UP * .02
		var end: Vector3 = door.center + direction * 1.1 + Vector3.UP * .02
		await route_walk(player, motor, start, end, Recipe.IDS[index] + " doorway " + str(door.center))
		await route_walk(player, motor, end, start, Recipe.IDS[index] + " reverse doorway " + str(door.center))
	player.free()

func route_walk(player: CharacterBody3D, motor: RefCounted, start: Vector3, end: Vector3, label: String) -> void:
	player.position = start
	player.velocity = Vector3.ZERO
	for frame in 3: await physics_frame
	var direction := Vector3(end.x - start.x, 0, end.z - start.z).normalized()
	for tick in 230:
		await physics_frame
		player.velocity = motor.walking_velocity(direction, player.velocity, 1.0 / 60, false, player.is_on_floor(), false)
		motor.move_grounded(player, 1.0 / 60)
		if Vector2(player.position.x - end.x, player.position.z - end.z).length() < .13: break
	player.velocity.x = 0
	player.velocity.z = 0
	for frame in 25:
		await physics_frame
		player.velocity = motor.walking_velocity(Vector3.ZERO, player.velocity, 1.0 / 60, false, player.is_on_floor(), false)
		motor.move_grounded(player, 1.0 / 60)
	var reached := Vector2(player.position.x - end.x, player.position.z - end.z).length() < .18 and absf(player.position.y - end.y) < .18
	check(reached, "walk " + label + " end=" + str(player.position))
