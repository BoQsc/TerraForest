extends SceneTree

const Recipe = preload("res://reviews/modular_buildings/large_house_recipe.gd")
var checks := 0
var failures := 0
var viewer: Node3D
var output := "res://reports/large_house"

func _initialize() -> void:
	run.call_deferred()

func check(accepted: bool, label: String) -> void:
	checks += 1
	if not accepted:
		failures += 1
	print("PASS " if accepted else "FAIL ", label)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):
			output = argument.trim_prefix("--review-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var blocks: Node3D = ClassDB.instantiate("NativeBlockWorld")
	if "--bake" in OS.get_cmdline_user_args():
		var baked: Resource = Recipe.build(blocks)
		check(baked != null and ResourceSaver.save(baked, Recipe.PATH) == OK, "bake separate native prefab")
	blocks.free()
	viewer = preload("res://reviews/modular_buildings/large_house_viewer.gd").new()
	root.add_child(viewer)
	check(viewer.ready_ok, "complete native block and attached-object publication")
	if not viewer.ready_ok:
		print(viewer.placement_results)
		diagnose_attachments()
		finish()
		return
	blocks = viewer.structures.blocks
	var expected: Resource = Recipe.build(blocks)
	check(expected.get_records() == viewer.asset.get_records(), "baked cells exactly match offline authoring recipe")
	check(expected.get_model_attachments() == viewer.asset.get_model_attachments(), "baked attached doors, windows and furniture match recipe")
	check(viewer.asset.get_meta("review_only", false), "historical reviewed resource remains separate from its production copy")
	check(viewer.asset.get_meta("basement_excavation").size == Vector3(11, 5, 15), "explicit basement excavation envelope is retained")
	var before: PackedByteArray = blocks.capture_snapshot()
	var cell_count: int = blocks.stats().cells
	var target := Vector3i(-2, 12, 8)
	check(blocks.get_cell(target) != 0, "roof-removal fixture is a real native slope cell")
	check(blocks.set_cells(PackedInt32Array([target.x, target.y, target.z, 0])), "one roof block can be destroyed independently")
	check(blocks.stats().cells == cell_count - 1, "roof removal leaves all other building blocks intact")
	check(blocks.restore_snapshot(before) and blocks.capture_snapshot() == before, "local roof removal restores exact native bytes")
	for level in [-3, 1, 5]:
		var support: PackedByteArray = blocks.sample_solid(PackedVector3Array([Vector3(.5, level - .06, 2), Vector3(-3.5, level - .06, 2)]))
		check(support == PackedByteArray([1, 1]), "continuous occupied floor at level " + str(level))
	check(blocks.sample_solid(PackedVector3Array([Vector3(2.5, 5.5, -2), Vector3(2.5, 1.5, -2)])) == PackedByteArray([0, 0]), "stacked stair openings are not plugged by floor slabs")
	for column in [-4, 2]:
		check(blocks.sample_solid(PackedVector3Array([Vector3(column + .5, 4.99, 10.5), Vector3(column + .5, 5.01, 10.5)])) == PackedByteArray([1, 1]), "balcony upright meets its thin deck without a gap")
	var saved: PackedByteArray = viewer.structures.capture_storage_snapshot()
	check(not saved.is_empty(), "combined block/model storage captured")
	if "--restore" in OS.get_cmdline_user_args():
		saved = FileAccess.get_file_as_bytes(output.path_join("house.tfbs"))
		check(not saved.is_empty(), "previous process produced storage fixture")
	else:
		FileAccess.open(output.path_join("house.tfbs"), FileAccess.WRITE).store_buffer(saved)
	check(viewer.structures.restore_storage_snapshot(saved), "combined house storage restores")
	check(viewer.structures.capture_storage_snapshot() == saved, "combined persistence roundtrip is byte-identical")
	viewer.select_view(6)
	check(blocks.stats().cells < cell_count, "review cutaway removes only temporary review geometry")
	viewer.select_view(0)
	check(viewer.structures.capture_storage_snapshot() == saved, "leaving cutaway restores all original blocks and attached objects")
	if "--pictures-only" not in OS.get_cmdline_user_args():
		viewer.toggle_doors()
		var doors: Node3D = viewer.structures.model(preload("res://addons/structures/door_catalog.gd").KEY)
		for identity in doors.get_ids():
			check(viewer.hinges.is_open(identity), "door opens independently " + str(identity))
		blocks.flush_bakes()
		for frame in 10:
			await physics_frame
		await traverse()
		await vehicle_clearance()
	if DisplayServer.get_name() != "headless":
		for index in viewer.VIEWS.size():
			viewer.select_view(index)
			for frame in 16:
				await process_frame
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(output.path_join("c1_" + str(index) + ".png")) == OK, "capture " + str(viewer.VIEWS[index][0]))
	finish()

func diagnose_attachments() -> void:
	if viewer.asset == null:
		return
	var empty: PackedByteArray = viewer.structures.capture_storage_snapshot()
	var transaction: RefCounted = ClassDB.instantiate("NativePrefabPlacement")
	for attachment: Dictionary in viewer.asset.get_model_attachments():
		var single: Resource = ClassDB.instantiate("NativeBlockPrefab")
		single.configure(viewer.asset.get_records())
		single.configure_model_attachments([attachment])
		var result: Dictionary = transaction.place(viewer.structures.blocks, single, Vector3i.ZERO, 0, viewer.structures.model_collections(), [])
		if not result.get("ok", false):
			print("ATTACHMENT_REJECTED ", attachment, " / ", result)
		viewer.structures.restore_storage_snapshot(empty)

func traverse() -> void:
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
	for base in [-3, 1]:
		player.position = Vector3(2.5, base + .14, -5.2)
		player.velocity = Vector3.ZERO
		for frame in 8:
			await physics_frame
		await walk(player, motor, Vector3.BACK, func(): return player.position.z > .7)
		check(player.position.z > .7 and absf(player.position.y - base - 4) < .15, "walk up full stair flight from " + str(base) + " / end " + str(player.position))
		await walk(player, motor, Vector3.FORWARD, func(): return player.position.z < -5.1)
		check(player.position.z < -5.1 and absf(player.position.y - base) < .15, "walk down full stair flight to " + str(base))
	for route in [[Vector3(.5, 1.02, 6.9), Vector3.FORWARD, 2.0, 2], [Vector3(.5, 5.02, 6), Vector3.BACK, 9.0, 2], [Vector3(4, 1.02, 3.5), Vector3.RIGHT, 7.0, 0]]:
		player.position = route[0]
		player.velocity = Vector3.ZERO
		for frame in 8:
			await physics_frame
		await walk(player, motor, route[1], func(): return player.position[route[3]] < route[2] if route[1] == Vector3.FORWARD else player.position[route[3]] > route[2])
		var reached: bool = player.position[route[3]] < route[2] if route[1] == Vector3.FORWARD else player.position[route[3]] > route[2]
		check(reached and absf(player.position.y - route[0].y) < .15, "walk through entrance, balcony or garage connection / " + str(route[0]) + " end " + str(player.position))
	for level in [-3, 1, 5]:
		for depth in [-1.5 if level == 5 else -3.5, 3.5]:
			player.position = Vector3(.7, level + .02, depth)
			player.velocity = Vector3.ZERO
			for frame in 8:
				await physics_frame
			await walk(player, motor, Vector3.LEFT, func(): return player.position.x < -1.8)
			check(player.position.x < -1.8 and absf(player.position.y - level) < .15, "room doorway clearance / level " + str(level) + " depth " + str(depth) + " end " + str(player.position))
	player.free()

func walk(player: CharacterBody3D, motor: RefCounted, direction: Vector3, reached: Callable) -> void:
	for tick in 200:
		await physics_frame
		player.velocity = motor.walking_velocity(direction, player.velocity, 1.0 / 60, false, player.is_on_floor(), false)
		motor.move_grounded(player, 1.0 / 60)
		if reached.call():
			break

func vehicle_clearance() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 1.8, 4.4)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 7
	query.margin = .02
	var clear := true
	for depth in range(2, 11):
		query.transform = Transform3D(Basis.IDENTITY, Vector3(9.5, 2.1, depth))
		clear = clear and root.world_3d.direct_space_state.intersect_shape(query, 1).is_empty()
	check(clear, "2.2 m wide, 1.8 m tall, 4.4 m long vehicle envelope clears the open garage approach")

func finish() -> void:
	var result := {"checks":checks, "failures":failures, "scope":"isolated reviewed C1 prefab, native persistence and traversal; production integration tested separately"}
	if viewer != null and viewer.ready_ok:
		result["cells"] = viewer.asset.get_cell_count()
		result["attachments"] = viewer.asset.get_model_attachments().size()
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify(result, "  "))
	if viewer != null:
		viewer.free()
	await process_frame
	print("LARGE_HOUSE checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
