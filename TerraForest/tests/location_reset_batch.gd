# SPDX-License-Identifier: 0BSD
extends SceneTree

const Batch = preload("res://addons/world_runtime/location_reset_batch.gd")
const Capture = preload("res://addons/world_runtime/location_capture.gd")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks := 0
var failures := 0
var timings: Array = []

func _initialize() -> void:
	for addon: String in ["structures", "player_runtime", "world_runtime", "vegetation_runtime", "volumetric_water"]:
		GDExtensionManager.load_extension("res://addons/%s/%s.gdextension" % [addon, addon])
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("PASS " if value else "FAIL ", label)

func operation(owner: Object, kind: String, arguments: Array) -> Dictionary:
	return {"target": owner, "kind": kind, "arguments": arguments, "original": Capture.patch(owner, kind, arguments)}

func put(target: Node3D, position: Vector3) -> void:
	check(target.upsert_instances(PackedInt64Array([1]), PackedFloat32Array([1, 0, 0, position.x, 0, 1, 0, position.y, 0, 0, 1, position.z])), "model placement succeeds")

func fixture() -> Dictionary:
	var damage: RefCounted = ClassDB.instantiate("NativeWorldDurability")
	var inventory: RefCounted = ClassDB.instantiate("NativePlayerInventory")
	inventory.register_item(201, 999)
	inventory.register_item(213, 999)
	inventory.register_item(102, 999)
	inventory.register_item(301, 1)
	inventory.register_item(601, 1000000)
	var storage: RefCounted = ClassDB.instantiate("NativeContainerStore")
	check(storage.configure(inventory, 16, 8, 213), "storage configured")
	check(storage.seed_contents(1, PackedInt64Array([201, 7])) and storage.seed_lock(1, 180, 8), "original locked supplies")
	var field: RefCounted = ClassDB.instantiate("TerrainCore")
	check(Codec.reply_ok(field.execute(Codec.command(6, [1703, 5]))), "terrain initialized")
	var models: Node3D = ClassDB.instantiate("NativeStaticBatch")
	models.configure_collision_only()
	var mesh := BoxMesh.new()
	models.configure_asset("test/reset_batch", mesh)
	put(models, Vector3(4, 4, 4))
	var operations: Array = [operation(field, "field", [Vector3i(1274, 58, 1274), Vector3i.ONE * 13]), operation(field, "cube", [Vector3i(1274, 58, 1274), Vector3i.ONE * 13]), operation(damage, "damage", [PackedStringArray(["inside"])]), operation(damage, "damage", [PackedStringArray(["second"])]), operation(storage, "container", [PackedInt64Array([1])]), operation(models, "placement", [Vector3i.ZERO, Vector3i.ONE * 32])]
	check(Codec.reply_ok(field.execute(Codec.brush(Vector3(1280, 64, 1280), Vector3(1280, 64, 1280), 3, 0, true, 3))) and Codec.reply_ok(field.execute(Codec.command(3, [1279, 63, 1279, 1]))), "normal terrain tools change density and cubes")
	damage.hit("inside", 100, 25)
	damage.hit("second", 100, 40)
	damage.hit("outside", 100, 35)
	check(storage.damage_lock(1, 180, storage.snapshot(1).store_revision).opened, "player breaks lock")
	check(storage.withdraw(1, inventory, 0, 7, inventory.snapshot().revision, storage.snapshot(1).store_revision).ok, "player loots supplies")
	check(storage.seed_contents(2, PackedInt64Array([201, 9])), "outside container")
	put(models, Vector3(8, 4, 4))
	return {"operations": operations, "damage": damage, "field": field, "models": models, "inventory": inventory, "storage": storage}

func captured(operations: Array) -> Array:
	var result: Array = []
	for row: Dictionary in operations:
		result.append(Capture.patch(row.target, row.kind, row.arguments))
	return result

func finish(batch: RefCounted) -> Dictionary:
	var state: Dictionary = batch.status()
	for count in Batch.MAX_OPERATIONS * 2 + 4:
		if state.terminal:
			break
		state = batch.advance()
	check(state.terminal, "transaction reaches a bounded terminal state")
	timings.append({"phase": state.phase, "elapsed_us": state.elapsed_us, "maximum_step_us": state.maximum_step_us, "bytes": state.bytes})
	return state

func success_and_cancel() -> void:
	for boundary in 7:
		var world := fixture()
		var before := captured(world.operations)
		var player: PackedByteArray = world.inventory.capture_storage_snapshot()
		var outside := Capture.patch(world.storage, "container", [PackedInt64Array([2])])
		var batch := Batch.new()
		check(batch.prepare(world.operations).phase == "prepared" and captured(world.operations) == before, "preflight captures undo without mutation")
		for index in boundary:
			var step: Dictionary = batch.advance()
			check(step.applied == index + 1 and step.phase in ["applying", "restored"], "one native operation per step; shared revision domains stay coherent")
		if boundary == 6:
			var originals: Array = []
			for row: Dictionary in world.operations:
				originals.append(row.original)
			check(captured(world.operations) == originals, "all selected owners reach originals")
		check(batch.cancel().phase == "rolling_back" and finish(batch).phase == "rolled_back", "cancel at boundary %d rolls back" % boundary)
		check(captured(world.operations) == before, "exact pre-reset state restored at boundary %d" % boundary)
		check(world.damage.damage("outside", 100) == 35 and Capture.patch(world.storage, "container", [PackedInt64Array([2])]) == outside and world.inventory.capture_storage_snapshot() == player, "outside damage, supplies and player inventory survive")
		world.models.free()

func late_failure() -> void:
	var world := fixture()
	var before := captured(world.operations)
	var batch := Batch.new()
	check(batch.prepare(world.operations).phase == "prepared", "late rejection fixture prepared")
	world.models.set_removal_protected(1, true)
	var result := finish(batch)
	check(result.phase == "rolled_back" and result.applied == 5 and result.reason.begins_with("restore_failed:placement:"), "real protected-model rejection rolls back five earlier operations")
	check(captured(world.operations) == before and world.models.is_removal_protected(1), "late failure preserves complete prior state and model protection")
	world.models.free()

func reject_and_recover() -> void:
	var world := fixture()
	var before := captured(world.operations)
	var corrupt: Array = world.operations.duplicate(true)
	corrupt[-1].original[80] ^= 1
	var batch := Batch.new()
	check(batch.prepare(corrupt).phase == "rejected" and captured(world.operations) == before, "invalid late original rejects before any mutation")
	batch = Batch.new()
	batch.prepare(world.operations)
	world.damage.hit("outside", 100, 1)
	check(batch.advance().phase == "rejected" and captured(world.operations) == before, "pre-start stale owner rejects without writes")
	batch = Batch.new()
	batch.prepare(world.operations)
	batch.advance()
	world.damage.hit("outside", 100, 1)
	var interrupted := captured(world.operations)
	check(batch.advance().phase == "recovery_required" and captured(world.operations) == interrupted and world.damage.damage("outside", 100) == 37, "mid-reset foreign mutation demands durable recovery, never blind rollback")
	world.models.free()
	world = fixture()
	batch = Batch.new()
	batch.prepare(world.operations)
	check(finish(batch).phase == "restored", "rollback-failure fixture fully restored")
	world.models.set_removal_protected(1, true)
	batch.cancel()
	check(batch.advance().phase == "recovery_required", "native rollback rejection requires recovery instead of reporting success")
	world.models.free()
	world = fixture()
	batch = Batch.new()
	batch.prepare(world.operations)
	world.models.free()
	check(batch.advance().phase == "rejected", "freed owner rejected before mutation")
	check(Batch.new().prepare([]).phase == "rejected", "empty transaction rejected")
	var oversized: Array = []
	oversized.resize(Batch.MAX_OPERATIONS + 1)
	check(Batch.new().prepare(oversized).phase == "rejected", "operation cap enforced")
	check(Batch.new().prepare([{"target": world.damage, "kind": "unknown", "arguments": [], "original": PackedByteArray()}]).phase == "rejected", "unknown owner kind rejected")
	check(Batch.new().prepare([{"target": world.damage, "kind": "damage", "arguments": [1], "original": PackedByteArray()}]).phase == "rejected", "wrong argument type rejected before native dispatch")
	var mismatched := operation(world.damage, "damage", [PackedStringArray(["inside"])])
	mismatched.arguments = [PackedStringArray(["outside"])]
	check(Batch.new().prepare([mismatched]).get("reason") == "scope_mismatch:damage", "valid original cannot mutate a different selection than its undo")
	mismatched.expected = world.damage.damage_patch_state()
	mismatched.captured = mismatched.original
	check(Batch.new().prepare([mismatched]).get("reason") == "scope_mismatch:damage", "cached capture cannot bypass declared selector validation")
	check(Batch.new().prepare([operation(world.damage, "damage", [PackedStringArray(["second", "inside"])])]).phase == "prepared", "unordered native identity arguments normalize safely")
	check(Batch.new().prepare([operation(world.damage, "damage", [PackedStringArray(["inside"])])], [[123, "damage", {}]]).phase == "rejected", "non-object guard rejects without script exception")

func water_fixture(wet: bool) -> PackedByteArray:
	var catalog: PackedByteArray = ClassDB.instantiate("NativeLakeCatalog").encode([])
	var data := PackedByteArray()
	data.resize(32)
	data.fill(0)
	data.encode_u32(0, 0x31575256)
	data.encode_u32(4, 10)
	data.encode_u32(8, catalog.size())
	data.encode_u32(12, 1 if wet else 0)
	data.encode_u64(16, 100 if wet else 0)
	data.encode_u64(24, 12 if wet else 0)
	data.append_array(catalog)
	if wet:
		var record := PackedByteArray()
		record.resize(9076)
		record.fill(0)
		record.encode_u64(0, (25 << 24) | (25 << 12) | 25)
		record.encode_u32(8, 1)
		record.encode_u32(12, 1)
		for sample in 512:
			record.encode_u16(18 + sample * 12, 500)
		for sample in 729:
			record.encode_float(6160 + sample * 4, 1.0)
		record.encode_u64(20, 100)
		data.append_array(record)
		var tail := PackedByteArray()
		tail.resize(12)
		tail.fill(0)
		data.append_array(tail)
	return data

func all_owners() -> void:
	var world := fixture()
	var blocks: Node3D = ClassDB.instantiate("NativeBlockWorld")
	var hinges: RefCounted = ClassDB.instantiate("NativeHingedDoors")
	var residents: RefCounted = ClassDB.instantiate("NativeZombiePopulation")
	check(residents.initialize(1703, Vector3.ZERO) and residents.register_sleepers([{"key": 1001, "position": Vector3(400, 80, 400), "yaw": 0.0, "pose": 1}]).added == 1, "authored sleeper fixture")
	var corpses: RefCounted = ClassDB.instantiate("NativeCorpseStore")
	check(corpses.configure(world.inventory, 4096, 8), "corpse store fixture")
	var trees: RefCounted = ClassDB.instantiate("NativeHarvestState")
	var ground: RefCounted = ClassDB.instantiate("NativeGroundCoverState")
	check(ground.bind_world(1703, 1), "ground identity fixture")
	var water: RefCounted = ClassDB.instantiate("NativeRegionalWater")
	check(water.restore_snapshot(water_fixture(false)), "dry water original")
	var extra: Array = [operation(blocks, "cell", [Vector3i.ZERO, Vector3i.ONE * 32]), operation(hinges, "door", [PackedInt64Array([1])]), operation(residents, "resident", [PackedInt64Array([2501])]), operation(corpses, "corpse", [PackedInt64Array([2501]), PackedInt64Array([1001])]), operation(trees, "harvest", [PackedInt64Array([12289])]), operation(ground, "ground", [AABB(Vector3(100, 10, 100), Vector3(20, 30, 20)), PackedInt64Array([12289])]), operation(water, "water", [Vector3i(200, 200, 200), Vector3i.ONE * 4])]
	check(blocks.set_cells(PackedInt32Array([4, 4, 4, 1])), "player adds building block")
	check(hinges.toggle(world.models, 1, AABB()).ok, "player opens model hinge")
	var resident: Dictionary = residents.resident(2501)
	var dead: PackedByteArray = resident.vitals.duplicate()
	dead.encode_float(0, 0)
	check(residents.update_resident(2501, Vector3(800, 80, 800), 0.5, dead), "sleeper killed away from anchor")
	check(corpses.create_corpse(Vector3(800, 80, 800), 0.5, 1703, 2501, 1001) > 0, "owned corpse appears")
	check(trees.mark(12289) and ground.mark(12289) and ground.add(3, Transform3D(Basis.IDENTITY, Vector3(110, 20, 110))) > 0, "harvesting and planted ground roots")
	check(water.restore_snapshot(water_fixture(true)), "later water fixture")
	var operations: Array = world.operations.duplicate()
	operations.append_array(extra)
	var before := captured(operations)
	var originals: Array = []
	for row: Dictionary in operations:
		originals.append(row.original)
	var batch := Batch.new()
	check(batch.prepare(operations).phase == "prepared", "twelve owner kinds preflight together")
	check(finish(batch).phase == "restored" and captured(operations) == originals, "all twelve owners restored to exact selected originals")
	batch.cancel()
	check(finish(batch).phase == "rolled_back" and captured(operations) == before, "all twelve owners roll back to exact player-modified state")
	world.models.free()
	blocks.free()

func quest_barrier() -> void:
	for reject_late in [false, true]:
		var world := fixture()
		var quests: RefCounted = ClassDB.instantiate("NativeQuestLog")
		check(quests.configure(world.inventory, 601), "quest currency configured")
		var location := {"key": 1, "layout": "mine_test", "title": "Mine", "origin": Vector3i(100, 40, 100), "rotation": 0, "marker": Vector3(98, 40, 100), "bounds": AABB(Vector3(100, 40, 100), Vector3(5, 5, 5)), "residents": PackedInt64Array([1001]), "containers": PackedInt64Array([1]), "coins": 20, "xp": 80}
		check(quests.register_locations(1703, [location]).ok and quests.accept(1, quests.snapshot().revision).ok, "ordinary native contract enters travel phase")
		var batch := Batch.new()
		batch.prepare(world.operations)
		if reject_late:
			world.models.set_removal_protected(1, true)
		var reservation: Dictionary = quests.begin_reset(quests.snapshot().revision)
		check(reservation.ok, "quest reserves reset before owner mutation")
		while not batch.status().terminal:
			check(not quests.validate_snapshot(quests.capture_storage_snapshot()), "compound save cannot capture partial reset")
			batch.advance()
		check(batch.status().phase == ("rolled_back" if reject_late else "restored"), "owner outcome decides quest result")
		check(quests.finish_reset(reservation.cycle, not reject_late, quests.snapshot().revision).ok and quests.snapshot().phase == (1 if reject_late else 3), "only successful owner reset activates quest")
		check(quests.validate_snapshot(quests.capture_storage_snapshot()), "only settled quest state becomes saveable")
		world.models.free()

func run() -> void:
	success_and_cancel()
	late_failure()
	reject_and_recover()
	all_owners()
	quest_barrier()
	print("LOCATION_RESET_TIMINGS ", JSON.stringify(timings))
	print("LOCATION_RESET_BATCH checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
