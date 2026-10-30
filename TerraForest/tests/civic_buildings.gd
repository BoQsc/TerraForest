# SPDX-License-Identifier: 0BSD
extends "res://tests/city_buildings.gd"
const Civic = preload("res://reviews/civic_buildings/recipes.gd")

func run() -> void:
	output = "res://reports/civic_buildings"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--review-output="): output = arg.trim_prefix("--review-output=")
		if arg.begins_with("--building="): only = arg.trim_prefix("--building=")
	DirAccess.make_dir_recursive_absolute(output)
	if "--bake-civic" in OS.get_cmdline_user_args():
		DirAccess.make_dir_recursive_absolute("res://reviews/civic_buildings/baked")
		var blocks: Node3D = ClassDB.instantiate("NativeBlockWorld")
		for index in Civic.IDS.size():
			var baked: Resource = Civic.build(blocks, index)
			check(baked != null and ResourceSaver.save(baked, "res://reviews/civic_buildings/baked/" + Civic.IDS[index] + ".tres") == OK, "bake " + Civic.IDS[index])
		blocks.free()
	viewer = preload("res://reviews/civic_buildings/viewer.gd").new(); root.add_child(viewer)
	for index in Civic.IDS.size():
		if not only.is_empty() and only != Civic.IDS[index]: continue
		if index > 0: viewer.select_building(index)
		check(viewer.ready_ok, "native combined publication " + Civic.IDS[index])
		if not viewer.ready_ok:
			print(viewer.placement_results); diagnose_attachments(); continue
		var blocks: Node3D = viewer.structures.blocks
		var expected: Resource = Civic.build(blocks, index)
		check(expected.get_records() == viewer.asset.get_records() and expected.get_model_attachments() == viewer.asset.get_model_attachments(), "baked recipe identity " + Civic.IDS[index])
		check(viewer.asset.get_meta("review_only", false), "review metadata " + Civic.IDS[index])
		var saved: PackedByteArray = viewer.structures.capture_storage_snapshot()
		var path: String = output.path_join(Civic.IDS[index] + ".tfbs")
		if "--restore" in OS.get_cmdline_user_args(): saved = FileAccess.get_file_as_bytes(path)
		else: FileAccess.open(path, FileAccess.WRITE).store_buffer(saved)
		check(not saved.is_empty() and viewer.structures.restore_storage_snapshot(saved) and viewer.structures.capture_storage_snapshot() == saved, "combined saved block/model restoration " + Civic.IDS[index])
		var count: int = blocks.stats().cells
		var records: PackedInt32Array = viewer.asset.get_records()
		check(blocks.set_cells(PackedInt32Array([records[0], records[1], records[2], 0])) and blocks.stats().cells == count - 1, "local block removal " + Civic.IDS[index])
		viewer.select_view(2); viewer.select_view(0)
		check(viewer.structures.capture_storage_snapshot() == saved, "cutaway restores exact content " + Civic.IDS[index])
		if index > 0:
			check(viewer.asset.get_meta("basement_interior_m2") in [81, 99], "medium partial basement " + Civic.IDS[index])
			check(blocks.sample_solid(PackedVector3Array([Vector3(7, -3.01, 9)])) == PackedByteArray([1]), "basement has supported floor " + Civic.IDS[index])
		metrics.append({"id":Civic.IDS[index], "cells":count, "attachments":viewer.asset.get_model_attachments().size(), "snapshot_bytes":saved.size()})
		if "--pictures-only" not in OS.get_cmdline_user_args():
			viewer.toggle_doors()
			var doors: Node3D = viewer.structures.model("architecture/wooden_door/v1")
			for id in doors.get_ids(): check(viewer.hinges.is_open(id), "working door " + Civic.IDS[index] + "/" + str(id))
			blocks.flush_bakes()
			for frame in 12: await physics_frame
			await civic_walk(index)
		if DisplayServer.get_name() != "headless":
			for mode in viewer.MODES.size():
				if mode == 4 and index == 0 or mode == 5 and Civic.FLOORS[index] < 2: continue
				viewer.select_view(mode)
				for frame in 16: await process_frame
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(output.path_join(Civic.IDS[index] + "_" + str(mode) + ".png")) == OK, "capture " + Civic.IDS[index] + "/" + str(mode))
	viewer.free(); await process_frame
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"buildings":metrics,"scope":"native prefab publication, local traversal, save/reload and review images; not generated-world acceptance"}, "  "))
	print("CIVIC_BUILDINGS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)

func civic_walk(index: int) -> void:
	var player := CharacterBody3D.new(); player.collision_mask = 15; player.collision_layer = 2
	player.floor_snap_length = .35; player.floor_max_angle = deg_to_rad(48); player.floor_constant_speed = true; player.safe_margin = .004
	var capsule := CapsuleShape3D.new(); capsule.radius = .34; capsule.height = 1.8
	var collider := CollisionShape3D.new(); collider.shape = capsule; collider.position.y = .9; player.add_child(collider); root.add_child(player)
	# The viewer's inactive walk body must not obstruct physics fixtures.
	viewer.player.position = Vector3(-40, 1, -40)
	var motor: RefCounted = ClassDB.instantiate("NativePlayerMovement")
	for route: Dictionary in viewer.asset.get_meta("stair_routes"):
		await route_walk(player, motor, route.start, route.end, Civic.IDS[index] + " " + route.kind)
		await route_walk(player, motor, route.end, route.start, Civic.IDS[index] + " reverse " + route.kind)
	for door: Dictionary in viewer.asset.get_meta("door_routes"):
		var direction := Vector3.RIGHT if door.side else Vector3.BACK
		var start: Vector3 = door.center - direction * 1.1 + Vector3.UP * .02
		var end: Vector3 = door.center + direction * 1.1 + Vector3.UP * .02
		await route_walk(player, motor, start, end, Civic.IDS[index] + " door " + str(door.center))
		await route_walk(player, motor, end, start, Civic.IDS[index] + " reverse door " + str(door.center))
	player.free()

func route_walk(player: CharacterBody3D, motor: RefCounted, start: Vector3, end: Vector3, label: String) -> void:
	player.position = start; player.velocity = Vector3.ZERO
	for frame in 3: await physics_frame
	var direction := Vector3(end.x - start.x, 0, end.z - start.z).normalized()
	var budget := mini(600, ceili(start.distance_to(end) / 5.5 * 60) + 90)
	for tick in budget:
		await physics_frame
		player.velocity = motor.walking_velocity(direction, player.velocity, 1.0 / 60, false, player.is_on_floor(), false)
		motor.move_grounded(player, 1.0 / 60)
		if Vector2(player.position.x - end.x, player.position.z - end.z).length() < .13: break
	player.velocity = Vector3.ZERO
	for tick in 25:
		await physics_frame
		player.velocity = motor.walking_velocity(Vector3.ZERO, player.velocity, 1.0 / 60, false, player.is_on_floor(), false)
		motor.move_grounded(player, 1.0 / 60)
	check(Vector2(player.position.x - end.x, player.position.z - end.z).length() < .18 and absf(player.position.y - end.y) < .18, "walk " + label + " end=" + str(player.position))
