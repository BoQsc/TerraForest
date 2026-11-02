# SPDX-License-Identifier: 0BSD
extends SceneTree
const Plan = preload("res://addons/world_runtime/location_reset_plan.gd")
const Capture = preload("res://addons/world_runtime/location_capture.gd")
const Scope = preload("res://addons/world_runtime/location_patch_scope.gd")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
const BOUNDS := AABB(Vector3(100, 60, 100), Vector3.ONE * 16)
const CHEST := "storage/wooden_chest/v1"
const DOOR := "architecture/test_door/v1"
var checks := 0
var failures := 0

func _initialize() -> void:
	for addon: String in ["structures", "player_runtime", "world_runtime", "vegetation_runtime", "volumetric_water"]:
		GDExtensionManager.load_extension("res://addons/%s/%s.gdextension" % [addon, addon])
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
	print("PASS " if value else "FAIL ", label)
	return value

func put(collection: Node3D, identity: int, point: Vector3) -> void:
	check(collection.upsert_instances(PackedInt64Array([identity]), PackedFloat32Array([1, 0, 0, point.x, 0, 1, 0, point.y, 0, 0, 1, point.z])), "model instance accepted")

func fixture() -> Dictionary:
	var owner := {"seed": 1703, "density": 0.4, "biome": 0, "min_up": 0.8, "groves": PackedByteArray()}
	for row: Array in [["field", "TerrainCore"], ["blocks", "NativeBlockWorld"], ["containers", "NativeContainerStore"], ["inventory", "NativePlayerInventory"], ["residents", "NativeZombiePopulation"], ["corpses", "NativeCorpseStore"], ["trees", "NativeHarvestState"], ["ground", "NativeGroundCoverState"], ["water", "NativeRegionalWater"], ["damage", "NativeWorldDurability"]]:
		owner[row[0]] = ClassDB.instantiate(row[1])
	owner.rock_damage = owner.damage
	root.add_child(owner.blocks)
	for item: int in [102, 201, 213, 301]:
		owner.inventory.register_item(item, 999)
	check(owner.containers.configure(owner.inventory, 4096, 16, 213) and owner.corpses.configure(owner.inventory, 4096, 8), "native inventory owners configured")
	check(Codec.reply_ok(owner.field.execute(Codec.command(6, [1703, 5]))) and owner.ground.bind_world(1703, 1), "terrain and ground identities configured")
	check(owner.residents.initialize(1703, Vector3.ZERO) and owner.residents.register_sleepers([{"key": 1001, "position": Vector3(104, 64, 108), "yaw": 0.0, "pose": 1}]).added == 1, "original sleeper")
	owner.models = {}
	for asset: String in [CHEST, DOOR]:
		var collection: Node3D = ClassDB.instantiate("NativeStaticBatch")
		collection.configure_collision_only()
		collection.configure_asset(asset, BoxMesh.new())
		root.add_child(collection)
		owner.models[asset] = collection
		put(collection, 1, Vector3(104 if asset == CHEST else 108, 64, 104))
	var hinges: RefCounted = ClassDB.instantiate("NativeHingedDoors")
	owner.doors = {DOOR: {"state": hinges}}
	check(owner.containers.seed_contents(1, PackedInt64Array([201, 7])) and owner.containers.seed_lock(1, 180, 8), "original supplies and lock")
	owner.models[CHEST].set_removal_protected(1, true)
	var location := {"key": 1, "layout": "test", "origin": Vector3i(100, 60, 100), "rotation": 0, "bounds": BOUNDS, "residents": PackedInt64Array([1001]), "containers": PackedInt64Array([1])}
	var records: Dictionary = {}
	for spec: Array in [["terrain", owner.field, "field", 1, true], ["cubes", owner.field, "cube", 1, false], ["blocks", owner.blocks, "cell", 1, false], ["water", owner.water, "water", 2, false]]:
		var pieces: Array = []
		for tile: Array in Capture.tiles(Vector3i(BOUNDS.position) * spec[3], Vector3i(BOUNDS.size) * spec[3] + (Vector3i.ONE if spec[4] else Vector3i.ZERO)):
			pieces.append(Capture.patch(spec[1], spec[2], tile))
		records[spec[0]] = pieces
	records.models = []
	for asset: String in owner.models:
		records.models.append([asset, Capture.patch(owner.models[asset], "placement", [Vector3i(BOUNDS.position), Vector3i(BOUNDS.size)]), PackedInt64Array([1]), PackedInt64Array([1]) if asset == CHEST else PackedInt64Array()])
	records.doors = [[DOOR, PackedInt64Array([1]), Capture.patch(hinges, "door", [PackedInt64Array([1])])]]
	records.containers = [Capture.patch(owner.containers, "container", [PackedInt64Array([1])])]
	records.residents = [Capture.patch(owner.residents, "resident", [PackedInt64Array([2501])])]
	records.corpses = [Capture.patch(owner.corpses, "corpse", [PackedInt64Array([2501]), PackedInt64Array([1001])])]
	records.trees = [PackedInt64Array([12289]), Capture.patch(owner.trees, "harvest", [PackedInt64Array([12289])]), owner.seed, owner.density, owner.biome, owner.min_up, owner.groves]
	records.ground = [PackedInt64Array([12289]), Capture.patch(owner.ground, "ground", [BOUNDS, PackedInt64Array([12289])])]
	records.damage = ["pristine_generation", owner.damage.capture_storage_snapshot(), owner.damage.capture_storage_snapshot()]
	var sections: Dictionary = {}
	for kind: String in records:
		sections[kind] = Capture.envelope(kind, BOUNDS, records[kind])
	check(sections.size() == 12, "twelve actual native original sections")
	return {"owner": owner, "location": location, "sections": sections, "records": records}

func dispose(world: Dictionary) -> void:
	for collection: Node3D in world.owner.models.values():
		collection.free()
	world.owner.blocks.free()

func mutate(world: Dictionary) -> void:
	var owner: Dictionary = world.owner
	check(owner.containers.damage_lock(1, 180, owner.containers.snapshot(1).store_revision).opened and owner.containers.withdraw(1, owner.inventory, 0, 7, owner.inventory.snapshot().revision, owner.containers.snapshot(1).store_revision).ok, "player loots original chest")
	for asset: String in [CHEST, DOOR]:
		put(owner.models[asset], 2, Vector3(104 if asset == CHEST else 108, 64, 110))
		put(owner.models[asset], 3, Vector3(140, 64, 110))
	check(owner.containers.seed_contents(2, PackedInt64Array([201, 5])) and owner.containers.seed_lock(2, 180, 7) and owner.containers.seed_contents(3, PackedInt64Array([201, 9])), "player adds owned and neighboring supplies")
	owner.models[CHEST].set_removal_protected(2, true)
	check(owner.doors[DOOR].state.toggle(owner.models[DOOR], 2, AABB()).ok, "player-added door opens")
	check(owner.blocks.set_cells(PackedInt32Array([104, 64, 108, 1, 140, 64, 108, 1])), "player blocks inside and outside")
	check(Codec.reply_ok(owner.field.execute(Codec.brush(Vector3(108, 68, 108), Vector3(108, 68, 108), 2, 0, true, 3))), "player sculpts terrain")
	check(owner.ground.mark(12289) and owner.trees.mark(12289), "player harvests natural roots")
	var planted: int = owner.ground.add(3, Transform3D(Basis.IDENTITY, Vector3(110, 64, 110)))
	check(planted > 0, "player plants local root")
	var vitals: PackedByteArray = owner.residents.resident(2501).vitals.duplicate()
	vitals.encode_float(0, 0)
	check(owner.residents.update_resident(2501, Vector3(800, 80, 800), 0.0, vitals) and owner.corpses.create_corpse(Vector3(800, 80, 800), 0, 1703, 2501, 1001) > 0, "original sleeper dies outside location and leaves owned corpse")
	for key: String in ["block:104:64:108", "block:140:64:108", "model:" + CHEST + ":2", "model:" + CHEST + ":3", "cover:12289", "cover:" + str(planted), "vehicle:1", "actor:1"]:
		owner.damage.hit(key, 100, 25)

func run_batch(batch: RefCounted) -> Dictionary:
	for index in 1030:
		if batch.status().terminal:
			return batch.status()
		batch.advance()
	return batch.status()

func restore_with_player_changes() -> void:
	var world := fixture()
	mutate(world)
	for index in 4096:
		world.owner.damage.hit("block:%d:%d:%d" % [100 + index % 16, 60 + index / 256, 100 + (index / 16) % 16], 100, 1)
	var plan := Plan.new()
	var started := Time.get_ticks_usec()
	var result := plan.prepare(world.owner, world.location, world.sections)
	print("LOCATION_PLAN_CAPTURE ", JSON.stringify({"us": Time.get_ticks_usec() - started, "ok": result.ok, "reason": result.get("reason", ""), "bytes": result.get("bytes", 0), "operations": plan.operations.size()}))
	if not check(result.ok, "live ownership plan includes added player objects"):
		dispose(world)
		return
	check(plan.operations.filter(func(row: Dictionary) -> bool: return row.kind == "damage").size() == 2, "more than one damage patch is planned without rejecting a heavily edited location")
	var outside := Capture.patch(world.owner.containers, "container", [PackedInt64Array([3])])
	var player: PackedByteArray = world.owner.inventory.capture_storage_snapshot()
	var damage: PackedByteArray = world.owner.damage.capture_storage_snapshot()
	for record: Dictionary in result.protections:
		record.target.set_removal_protected(record.id, false)
	var batch := plan.create_batch()
	check(batch.status().phase == "prepared" and run_batch(batch).phase == "restored", "validated cached captures restore without recapture")
	for operation: Dictionary in plan.operations:
		check(Capture.patch(operation.target, operation.kind, operation.arguments) == operation.original, "planned original restored: " + operation.kind)
	check(world.owner.models[CHEST].get_instance(2).is_empty() and not world.owner.models[CHEST].get_instance(3).is_empty() and not world.owner.containers.has_contents(2) and not world.owner.doors[DOOR].state.is_open(2), "later local chest and door removed with their dependent state")
	check(Capture.patch(world.owner.containers, "container", [PackedInt64Array([3])]) == outside and world.owner.damage.damage("block:140:64:108", 100) == 25 and world.owner.damage.damage("vehicle:1", 100) == 25 and world.owner.inventory.capture_storage_snapshot() == player, "outside structures, vehicle and player loot preserved")
	batch.cancel()
	check(run_batch(batch).phase == "rolled_back", "complete plan rolls back")
	for operation: Dictionary in plan.operations:
		check(Capture.patch(operation.target, operation.kind, operation.arguments) == operation.captured, "pre-reset state restored: " + operation.kind)
	for record: Dictionary in result.protections:
		record.target.set_removal_protected(record.id, record.current)
	check(world.owner.damage.capture_storage_snapshot() == damage and world.owner.models[CHEST].is_removal_protected(2), "rollback preserves all prior damage and protection")
	dispose(world)

func rejection_cases() -> void:
	var world := fixture()
	var different: Dictionary = world.sections.duplicate()
	different.terrain = Capture.envelope("terrain", BOUNDS, [Capture.patch(world.owner.field, "field", [Vector3i(130, 60, 100), Vector3i.ONE * 17])])
	check(not Plan.new().prepare(world.owner, world.location, different).ok, "valid native patch for wrong region rejected")
	different = world.sections.duplicate()
	var models: Array = world.records.models.duplicate(true)
	models[0][3] = PackedInt64Array([999])
	different.models = Capture.envelope("models", BOUNDS, models)
	check(not Plan.new().prepare(world.owner, world.location, different).ok, "unowned original protection rejected")
	put(world.owner.models[CHEST], 1, Vector3(140, 64, 104))
	check(Plan.new().prepare(world.owner, world.location, world.sections).get("reason") == "original_model_moved_outside", "moved original never stolen from outside")
	put(world.owner.models[CHEST], 1, Vector3(104, 64, 104))
	put(world.owner.models[CHEST], 2, Vector3(116, 64, 104))
	check(not Plan.new().prepare(world.owner, world.location, world.sections).ok, "cross-boundary player model rejects rather than clipping neighbors")
	world.owner.models[CHEST].remove_instances(PackedInt64Array([2]))
	var plan := Plan.new()
	check(plan.prepare(world.owner, world.location, world.sections).ok, "pristine plan contains zero damage mutations")
	world.owner.damage.hit("block:104:64:108", 100, 1)
	check(plan.create_batch().status().phase == "rejected", "new damage after an empty selection invalidates planned guard")
	dispose(world)

func damage_selection() -> void:
	var owner: RefCounted = ClassDB.instantiate("NativeWorldDurability")
	var exact := PackedStringArray(["model:test:1", "cover:12289"])
	for key: String in ["block:100:60:100", "block:115:75:115", "block:116:60:100", "block:100:76:100", "block:0100:60:100", "block:100:60:100tail", "block:100:60:100:1", "model:test:1", "model:test:10", "cover:12289", "vehicle:1"]:
		owner.hit(key, 100, 10)
	var token: Dictionary = owner.damage_patch_state()
	var before: PackedByteArray = owner.capture_storage_snapshot()
	var selected: Dictionary = owner.select_damage_keys(BOUNDS, exact, token.revision, token.owner)
	check(selected.ok and selected["keys"] == PackedStringArray(["block:100:60:100", "block:115:75:115", "cover:12289", "model:test:1"]), "canonical half-open block and exact identity selection")
	check(owner.capture_storage_snapshot() == before and owner.damage_patch_state() == token, "damage selection is read only")
	check(not owner.select_damage_keys(BOUNDS, exact, token.revision + 1, token.owner).ok and not owner.select_damage_keys(BOUNDS, exact, token.revision, token.owner + 1).ok, "stale and foreign damage selections reject")
	check(not owner.select_damage_keys(BOUNDS, PackedStringArray(["vehicle:1"]), token.revision, token.owner).ok and not owner.select_damage_keys(BOUNDS, PackedStringArray(["cover:1", "cover:1"]), token.revision, token.owner).ok, "unsupported or duplicate exact identities reject")
	for index in 4096:
		owner.hit("block:%d:%d:%d" % [100 + index % 16, 60 + index / 256, 100 + (index / 16) % 16], 100, 1)
	token = owner.damage_patch_state()
	selected = owner.select_damage_keys(BOUNDS, exact, token.revision, token.owner)
	check(selected.ok and selected["keys"].size() == 4098, "selection spans multiple bounded damage patches without truncation")
	var count: int = owner.record_count()
	for index in 65536 - count:
		owner.hit("outside:%d" % index, 100, 1)
	token = owner.damage_patch_state()
	var started := Time.get_ticks_usec()
	selected = owner.select_damage_keys(BOUNDS, PackedStringArray(), token.revision, token.owner)
	print("DAMAGE_SELECTION_MAX ", JSON.stringify({"us": Time.get_ticks_usec() - started, "examined": selected.get("examined", 0), "selected": selected.get("keys", []).size()}))
	check(selected.ok and selected.examined == 65536 and selected["keys"].size() == 4096, "full-capacity native scan remains bounded and selects only local damaged blocks")

func run() -> void:
	restore_with_player_changes()
	rejection_cases()
	damage_selection()
	print("LOCATION_RESET_PLAN checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
