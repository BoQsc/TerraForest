extends SceneTree

const Furniture = preload("res://addons/structures/furniture_catalog.gd")
const Lots = preload("res://addons/structures/northern_lots.gd")
const Planner = preload("res://addons/structures/terrain_lot_planner.gd")
const Site = preload("res://addons/structures/site_plan.gd")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Works = preload("res://addons/world_runtime/generation_earthworks.gd")
const REVIEW_PATH := "res://reviews/modular_buildings/baked/large_house_c1.tres"
const PATH := "res://addons/structures/prefabs/large_house_c1.tres"
var checks := 0
var failures := 0
var output := "res://reports/approved_large_house"
var reference := REVIEW_PATH

class FieldFacade extends Node:
	var core: RefCounted
	var validator: RefCounted
	var world_ready := true
	var pending_edit := false
	var stopping := false
	var epoch := 0
	var density_revision := 0
	func request_density_scan(points: PackedVector3Array, token: int, support_depth: int, interpolated:bool=false) -> bool:
		var values := PackedFloat32Array()
		for offset in range(0, points.size(), 512):
			var batch := points.slice(offset, mini(offset + 512, points.size()))
			var query := Codec.command(31,[density_revision,batch.size()]) if interpolated else Codec.command(30, [density_revision, batch.size(), support_depth])
			query.append_array(batch.to_byte_array())
			var reply: PackedByteArray = core.execute(query)
			if not Codec.reply_ok(reply):
				return false
			values.append_array(reply.slice(20).to_float32_array())
		validator.receive.call_deferred({"status":"ok", "token":token, "epoch":epoch, "revision":density_revision, "values":values})
		return true

class GenerationFixture extends Node:
	var terrain: Node
	var structures: Node3D
	var foundation_check: RefCounted

func _initialize() -> void:
	run.call_deferred()

func check(accepted: bool, label: String) -> void:
	checks += 1
	if not accepted:
		failures += 1
	print("PASS " if accepted else "FAIL ", label)

func bake(reviewed: Resource) -> void:
	var asset: Resource = ClassDB.instantiate("NativeBlockPrefab")
	check(asset.compose([reviewed], PackedInt32Array([0, 0, 4, 0, 0])), "normalize approved C1 foundation without changing its design")
	asset.resource_name = "Large two-storey house C1"
	asset.set_meta("approved_as_addition", true)
	asset.set_meta("approved_revision", "C1 R1")
	asset.set_meta("approved_date", "2026-10-27")
	asset.set_meta("site_surface_offset", 5)
	asset.set_meta("site_sample_band", 5)
	asset.set_meta("cellar_clearance", true)
	asset.set_meta("cellar_sections", [Vector2(-3, -5.5), Vector2(-1, -5.5), Vector2(1, -5.5), Vector2(3, -5.5), Vector2(4, -5.5)])
	asset.set_meta("cellar_end", 6.5)
	asset.set_meta("cellar_floor", .75)
	asset.set_meta("cellar_height", 5.0)
	asset.set_meta("floor_profiles", [{"sections":[Vector2(6.875, -.125), Vector2(8.25, -.125), Vector2(9.75, -.125), Vector2(11.125, -.125)], "end":7.125, "floor":4.75, "height":1.25, "width":.875}])
	asset.set_meta("garage_entrance", Vector3(9.5, 5, 9.5))
	check(ResourceSaver.save(asset, PATH) == OK, "bake production resource outside excluded review folder")

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):
			output = argument.trim_prefix("--review-output=")
		if argument.begins_with("--approved-reference="):
			reference = argument.trim_prefix("--approved-reference=")
	DirAccess.make_dir_recursive_absolute(output)
	var reviewed: Resource = load(reference)
	if "--bake" in OS.get_cmdline_user_args():
		bake(reviewed)
	var asset: Resource = Furniture.large_house()
	check(asset != null and asset.get_meta("approved_as_addition", false) and asset.get_meta("approved_revision", "") == "C1 R1", "specific approved revision loads as an addition")
	if asset == null:
		finish()
		return
	var expected: Resource = ClassDB.instantiate("NativeBlockPrefab")
	expected.compose([reviewed], PackedInt32Array([0, 0, 4, 0, 0]))
	check(asset.get_records() == expected.get_records() and asset.get_model_attachments() == expected.get_model_attachments(), "all reviewed cells and attached objects preserved under one vertical translation")
	var independent: Resource = Furniture.large_house()
	check(independent != asset and independent.configure(PackedInt32Array([0, 0, 0, 1])) and Furniture.large_house().get_records() == expected.get_records(), "editing one prefab cannot change future houses")
	var production_lots: Array = Lots.recipe(Vector3.ZERO, true)
	var count := 0
	for lot: Dictionary in production_lots:
		if lot.asset.get_meta("approved_revision", "") == "C1 R1":
			count += 1
	check(production_lots.size() == 12 and count == 1, "one C1 joins the neighborhood alongside the existing archetypes")
	check(Lots.recipe(Vector3.ZERO)[0].asset.get_records() == Furniture.enclosed_cottage().get_records(), "legacy ungraded neighborhood recipe is unchanged")
	for rotation in 4:
		var plan: Dictionary = Site.prepare(asset, Vector3i(1000, 50, 1000), rotation, 50)
		check(plan.get("ok", false) and plan.target.y == 45 and plan.segments[-5].start.y == 45.75 and plan.segments[-5].clearance == 5 and plan.segments[-1].start.y == 49.75, "basement and garage soil meet slab undersides under quarter-turn " + str(rotation))
	var legacy: Resource = preload("res://addons/structures/cellar_catalog.gd").cottage()
	var legacy_plan: Dictionary = Site.prepare(legacy, Vector3i(1000, 50, 1000), 0, 50)
	check(legacy_plan.ok and legacy_plan.segments[-1].clearance == 5, "existing small cellar excavation stays unchanged")
	var invalid: Resource = asset.duplicate()
	invalid.set_meta("cellar_sections", [Vector2(NAN, -5)])
	check(not Site.prepare(invalid, Vector3i(1000, 50, 1000), 0, 50).ok, "malformed excavation metadata fails before edits")
	invalid = asset.duplicate()
	invalid.set_meta("floor_profiles", [false])
	check(not Site.prepare(invalid, Vector3i(1000, 50, 1000), 0, 50).ok, "malformed floor profile is rejected without a script error")
	for seed_value in [1703, 42]:
		await verify_plan(seed_value)
	verify_full_plan()
	finish()

func verify_full_plan() -> void:
	var plans := preload("res://addons/world_runtime/world_generation_plan.gd")
	var options: Dictionary = preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS
	var folder := output.path_join("plan_cache")
	var plan: Dictionary = plans.build(1703, 23, true, true, folder, options)
	check(plan.get("ok", false) and plan.get("building_count", 0) == 20, "complete default two-settlement world plan includes the additional house")
	if not plan.get("ok", false):
		print("DEFAULT_PLAN_REJECTED ", plan)
		return
	var cached: Dictionary = plans.build(1703, 23, true, true, folder, options)
	check(cached.get("ok", false) and cached.get("cache_hit", false) and cached.plan_digest == plan.plan_digest, "default binary plan cache reopens with the current C1 definition")
	var count := 0
	for site: Dictionary in cached.sites:
		for lot: Dictionary in site.lots:
			if lot.asset.get_meta("approved_revision", "") == "C1 R1":
				count += 1
	check(count == 1, "default generation contains one C1 without replacing approved shop designs")

func verify_plan(seed_value: int) -> void:
	var core: RefCounted = ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6, [seed_value, 23]))
	var layout: Dictionary = preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value, 16)
	var plan: Dictionary = Planner.locate(core, layout.sites[3].position)
	check(plan.get("ok", false), "native terrain-fitting neighborhood plan / seed " + str(seed_value))
	if not plan.get("ok", false):
		print("PLAN_REJECTED ", plan)
		return
	var chosen := {}
	for lot: Dictionary in plan.lots:
		if lot.asset.get_meta("approved_revision", "") == "C1 R1":
			chosen = lot
	check(not chosen.is_empty() and chosen.origin.y + 5 == int(chosen.survey.grade), "C1 fitted at surveyed surface with basement below grade")
	if chosen.is_empty():
		return
	var works: Dictionary = Planner.earthworks(plan)
	check(works.get("ok", false), "complete master plan includes house, driveway and underground clearance")
	if not works.get("ok", false):
		return
	var baked: Dictionary = core.bake_generated_earthworks(Works.packets(works.segments))
	check(baked.get("ok", false), "native generation-time bake includes all edits / seed " + str(seed_value))
	if not baked.get("ok", false):
		print("BAKE_REJECTED ", baked)
		return
	var air := PackedVector3Array()
	for column in range(-4, 5):
		for row in range(-6, 7):
			for height in [1.25, 2.5, 4.5]:
				var point := Vector3(column + .5, height, row + .5)
				for turn in chosen.rotation:
					point = Vector3(1 - point.z, point.y, point.x)
				air.append(point + Vector3(chosen.origin))
	check(density_matches(core, air, baked.revision, false), "all 351 sampled cellar interior points are excavated before construction")
	var floor_surfaces := PackedVector3Array()
	for column in range(6, 12):
		for row in range(-1, 8):
			floor_surfaces.append(site_point(chosen, Vector3(column + .5, 5, row + .5)))
	for column in range(-4, 5):
		for row in range(-6, 7):
			floor_surfaces.append(site_point(chosen, Vector3(column + .5, 1, row + .5)))
	check(density_matches(core, floor_surfaces, baked.revision, false), "soil stays below exposed basement and garage slab tops instead of z-fighting")
	var support: PackedVector3Array = chosen.asset.foundation_samples(chosen.origin, chosen.rotation, 0)
	check(density_matches(core, support, baked.revision, true), "every basement floor column has solid terrain support")
	var clear := true
	for offset in range(0, chosen.asset.clearance_sample_count(), 512):
		clear = density_matches(core, chosen.asset.clearance_samples(chosen.origin, chosen.rotation, offset, 512, 5), baked.revision, false, true) and clear
	check(clear, "production foundation validator sees clear rooms, garage and roof envelope")
	var saved: PackedByteArray = core.execute(Codec.command(4)).slice(12)
	var restored: RefCounted = ClassDB.instantiate("TerrainCore")
	var packet := Codec.command(5)
	packet.append_array(saved)
	check(Codec.reply_ok(restored.execute(packet)) and restored.execute(Codec.command(4)).slice(12) == saved, "generated terrain archive restores without a new save format")
	var cache := {"plan":plan, "market":{}}
	var plans := preload("res://addons/world_runtime/world_generation_plan.gd")
	var decoded: Dictionary = plans.without_assets(cache)
	check(plans.attach_assets(decoded) and decoded.plan.lots.size() == plan.lots.size(), "derived-plan cache reattaches current approved archetypes")
	FileAccess.open(output.path_join("plan_" + str(seed_value) + ".bin"), FileAccess.WRITE).store_var(plans.without_assets(cache))
	FileAccess.open(output.path_join("terrain_" + str(seed_value) + ".bin"), FileAccess.WRITE).store_buffer(saved)
	print("C1_GENERATION seed=", seed_value, " origin=", chosen.origin, " rotation=", chosen.rotation, " edits=", works.segments.size(), " bake_ms=", baked.worker_ms)
	if seed_value == 1703:
		await inspect_site(core, plan, chosen, baked.revision)

func site_point(lot: Dictionary, local: Vector3) -> Vector3:
	for turn in lot.rotation:
		local = Vector3(1 - local.z, local.y, local.x)
	return Vector3(lot.origin) + local

func inspect_site(core: RefCounted, plan: Dictionary, lot: Dictionary, revision: int) -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var structures := preload("res://addons/structures/structures_world.gd").new()
	stage.add_child(structures)
	check(structures.prepare(), "native site structures prepare")
	for catalog in [Furniture, preload("res://addons/structures/storage_catalog.gd"), preload("res://addons/structures/door_catalog.gd"), preload("res://addons/structures/window_catalog.gd"), preload("res://addons/structures/guardrail_catalog.gd")]:
		catalog.register(structures)
	var placement: RefCounted = ClassDB.instantiate("NativePrefabPlacement")
	var game := GenerationFixture.new()
	var field := FieldFacade.new()
	game.terrain = field
	game.structures = structures
	game.foundation_check = preload("res://addons/structures/foundation_check.gd").new()
	field.validator = game.foundation_check
	field.core = core
	field.epoch = core.execute(Codec.command(13)).decode_u32(12)
	field.density_revision = revision
	var generator := preload("res://addons/world_runtime/generate_world_task.gd").new()
	generator.root = root
	for fitted: Dictionary in plan.lots:
		var placed: Dictionary
		if fitted.asset.get_meta("approved_revision", "") == "C1 R1":
			placed = {"ok":await generator.generate_prefab(game, fitted)}
		else:
			placed = placement.place(structures.blocks, fitted.asset, fitted.origin, fitted.rotation, structures.model_collections(), [])
		check(placed.get("ok", false), "native compound publication / " + fitted.label)
		if not placed.get("ok", false):
			print(placed)
	generator.free()
	field.free()
	game.free()
	check(structures.blocks.set_cells(plan.block_paving.records), "destructible street paving publishes beside fitted houses")
	var focus := site_point(lot, Vector3(3, 5, 0))
	structures.blocks.set_focus(focus)
	structures.blocks.set_collision_radius(96)
	structures.blocks.flush_bakes()
	structures.set_model_focus(focus)
	var bounds: AABB = lot.bounds.grow(12).expand(lot.entrance.segment.finish)
	var epoch: int = core.execute(Codec.command(13)).decode_u32(12)
	var faces := PackedVector3Array()
	var material: Material = preload("res://addons/volumetric_terrain/runtime_assets.gd").make_terrain_material() if DisplayServer.get_name() != "headless" else null
	if material != null:
		material.set_shader_parameter("regional_temperate", true)
		for fitted: Dictionary in plan.lots:
			bounds = bounds.merge(fitted.bounds.grow(4))
	for across in range(floori(bounds.position.x / 16) * 16, ceili(bounds.end.x / 16) * 16, 16):
		for along in range(floori(bounds.position.z / 16) * 16, ceili(bounds.end.z / 16) * 16, 16):
			for height in range(floori((lot.origin.y - 4) / 32.0) * 32, ceili((lot.origin.y + 20) / 32.0) * 32, 32):
				var decoded: Dictionary = Codec.decode_mesh(core.build_owned_region(across, along, 16, 1, height, height + 32, epoch))
				if decoded.has("error"):
					check(false, "native site terrain mesh decodes")
					stage.free()
					return
				faces.append_array(decoded.faces)
				if material != null and not decoded.faces.is_empty():
					var mesh := ArrayMesh.new()
					mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, decoded.arrays)
					mesh.surface_set_material(0, material)
					var instance := MeshInstance3D.new()
					instance.mesh = mesh
					stage.add_child(instance)
	var terrain := StaticBody3D.new()
	terrain.collision_layer = 1
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	terrain.add_child(collider)
	stage.add_child(terrain)
	for frame in 10:
		await physics_frame
	var hinges: RefCounted = ClassDB.instantiate("NativeHingedDoors")
	var doors: Node3D = structures.model("architecture/wooden_door/v1")
	for identity in doors.get_ids():
		hinges.toggle(doors, identity, AABB())
	for frame in 8:
		await physics_frame
	var player := CharacterBody3D.new()
	player.collision_layer = 8
	player.collision_mask = 7
	player.floor_snap_length = .35
	player.floor_max_angle = deg_to_rad(48)
	player.floor_constant_speed = true
	player.safe_margin = .004
	var capsule := CapsuleShape3D.new()
	capsule.radius = .34
	capsule.height = 1.8
	var body_shape := CollisionShape3D.new()
	body_shape.shape = capsule
	body_shape.position.y = .9
	player.add_child(body_shape)
	stage.add_child(player)
	var motor: RefCounted = ClassDB.instantiate("NativePlayerMovement")
	var routes := [[lot.entrance.segment.finish + Vector3.UP * .05, site_point(lot, Vector3(.5, 5.02, 6))]]
	for route in [[Vector3(2.5, 5.02, .8), Vector3(2.5, 1.02, -5.2)], [Vector3(2.5, 1.02, -5.2), Vector3(2.5, 5.02, .8)], [Vector3(2.5, 5.02, -5.2), Vector3(2.5, 9.02, .8)], [Vector3(2.5, 9.02, .8), Vector3(2.5, 5.02, -5.2)], [Vector3(.5, 9.02, 6), Vector3(.5, 9.145, 9.2)], [Vector3(4, 5.02, 3.5), Vector3(9.5, 5.02, 3.5)]]:
		routes.append([site_point(lot, route[0]), site_point(lot, route[1])])
	for index in routes.size():
		var route: Array = routes[index]
		player.position = route[0]
		player.velocity = Vector3.ZERO
		for frame in 8:
			await physics_frame
		for tick in 360:
			await physics_frame
			var offset: Vector3 = route[1] - player.position
			offset.y = 0
			if offset.length() < .16:
				break
			player.velocity = motor.walking_velocity(offset.normalized(), player.velocity, 1.0 / 60, false, player.is_on_floor(), false)
			motor.move_grounded(player, 1.0 / 60)
		check(Vector2(player.position.x, player.position.z).distance_to(Vector2(route[1].x, route[1].z)) < .2 and absf(player.position.y - route[1].y) < .18, "actual terrain + blocks traversal / route " + str(index) + " end " + str(player.position))
	player.free()
	if material != null:
		await photograph(stage, lot)
	stage.free()
	await process_frame

func photograph(stage: Node3D, lot: Dictionary) -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("bdcfd8")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d8e3ed")
	environment.environment.ambient_light_energy = .65
	environment.environment.ssao_enabled = true
	stage.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-44, -30 - 90 * lot.rotation, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.current = true
	camera.near = .04
	camera.far = 200
	stage.add_child(camera)
	var canvas := CanvasLayer.new()
	stage.add_child(canvas)
	var label := Label.new()
	label.text = "TERRAFOREST / APPROVED C1 / GENERATED SITE / SEED 1703\nActual baked terrain + native building blocks / no player save modified"
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(label)
	for view in [["exterior", Vector3(27, 21, 32), Vector3(3, 10, 1)], ["basement", Vector3(3.9, 2.8, 5.6), Vector3(.5, 2.8, -3)]]:
		camera.fov = 49 if view[0] == "exterior" else 78
		camera.position = site_point(lot, view[1])
		camera.look_at(site_point(lot, view[2]))
		for frame in 18:
			await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(output.path_join(str(view[0]) + ".png")) == OK, "capture generated C1 " + str(view[0]))

func density_matches(core: RefCounted, points: PackedVector3Array, revision: int, solid: bool, allow_contact: bool = false) -> bool:
	var packet := Codec.command(31, [revision, points.size()])
	packet.append_array(points.to_byte_array())
	var reply: PackedByteArray = core.execute(packet)
	if not Codec.reply_ok(reply) or reply.size() != 20 + points.size() * 4:
		return false
	var mismatches := 0
	for index in points.size():
		var density: float = reply.decode_float(20 + index * 4)
		if density >= 0 if solid else density < 0 if allow_contact else density <= 0:
			if mismatches < 3:
				print("DENSITY_MISMATCH ", points[index], " value=", density, " solid=", solid)
			mismatches += 1
	return mismatches == 0

func finish() -> void:
	FileAccess.open(output.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures, "scope":"approved geometry, production native lot fitting and terrain bake; seeds 1703 and 42"}, "  "))
	print("APPROVED_LARGE_HOUSE checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
