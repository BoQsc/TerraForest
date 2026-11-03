# SPDX-License-Identifier: 0BSD
extends SceneTree

const Parking = preload("res://addons/vehicle_runtime/building_parking.gd")
const Catalog = preload("res://addons/structures/expansion_catalog.gd")
var checks := 0
var failures := 0

class VehicleHost extends Node:
	var fleet: RefCounted = ClassDB.instantiate("NativeVehicleFleet")
	var fleet_enabled := true
	var packs: Dictionary = {"vehicles": {"terraforest.ranger.v1": {}}}

class GenerationHost extends Node:
	var world_vehicle := VehicleHost.new()
	var structures: Node3D
	var quests: Dictionary = {"store": ClassDB.instantiate("NativeQuestLog")}
	var terrain: Dictionary = {"changed_since_save": false}

func _initialize() -> void:
	ProjectSettings.set_setting("terraforest/offscreen_session", true)
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func run() -> void:
	var structures := preload("res://addons/structures/structures_world.gd").new()
	root.add_child(structures)
	check(structures.prepare(), "native structure owners prepare")
	preload("res://addons/structures/furniture_catalog.gd").register(structures)
	preload("res://addons/structures/storage_catalog.gd").register(structures)
	preload("res://addons/structures/door_catalog.gd").register(structures)
	preload("res://addons/structures/window_catalog.gd").register(structures)
	var empty: PackedByteArray = structures.capture_storage_snapshot()
	var placement: RefCounted = ClassDB.instantiate("NativePrefabPlacement")
	var fleet: RefCounted = ClassDB.instantiate("NativeVehicleFleet")
	for building: String in Parking.CATALOG:
		var asset: Resource = Catalog.asset(building)
		var original: PackedInt32Array = asset.get_records()
		for rotation in 4:
			check(structures.restore_storage_snapshot(empty), "empty fixture restores")
			var lot: Dictionary = {"asset": asset, "origin": Vector3i(100, 30, 100), "rotation": rotation}
			check(placement.place(structures.blocks, asset, lot.origin, rotation, structures.model_collections(), []).ok, "approved " + building + " publishes at rotation " + str(rotation))
			var selected: Array[Dictionary] = []
			for seed_value in 32:
				selected = Parking.candidates([lot], seed_value)
				if not selected.is_empty(): break
			if selected.is_empty(): check(false, "candidate exists"); continue
			var candidate: Dictionary = selected[0]
			var accepted := Parking.admit(structures.blocks, structures.model_collections(), candidate)
			check(accepted.ok, building + " supported bay, departure and pedestrian exit: " + str(accepted))
			var pose: Transform3D = candidate.pose
			if building == "house_c1":
				var frame := Transform3D(pose.basis, pose.origin - pose.basis * Parking.CATALOG.house_c1.point)
				var anchor: Vector3 = frame * preload("res://addons/characters/runtime/house_sleepers.gd").HOMES.house_c1
				var sleeper_box := AABB(anchor - Vector3(.85, 0, .85), Vector3(1.7, 1.8, 1.7))
				check(Parking._clear(structures.blocks, structures.model_collections(), sleeper_box), "C1 sleeper has clear room space away from garage")
				check(Parking._floor(structures.blocks, Transform3D(Basis.IDENTITY, anchor - Vector3.UP * .002), .75, .75), "C1 sleeper room has supported floor across lying pose")
				var sleeper_reserved: Array[AABB] = [AABB(anchor - Vector3(1, .1, 1), Vector3(2, 2, 2))]
				check(Parking.admit(structures.blocks, structures.model_collections(), candidate, [], sleeper_reserved).ok, "C1 sleeper and vehicle departure never overlap")
			var reserved: Array[AABB] = [AABB(pose.origin - Vector3.ONE, Vector3.ONE * 2)]
			check(not Parking.admit(structures.blocks, structures.model_collections(), candidate, [], reserved).ok, "authored sleepers and resettable quests keep their reserved space")
			var identity: int = fleet.spawn_module(pose, Parking.KIND, PackedByteArray())
			check(identity > 0 and fleet.get_record(identity).pose.is_equal_approx(pose), "native fleet owns exact rotated parking transform")
			var snapshot: PackedByteArray = fleet.capture_storage_snapshot()
			var restored: RefCounted = ClassDB.instantiate("NativeVehicleFleet")
			check(restored.restore_storage_snapshot(snapshot) and restored.capture_storage_snapshot() == snapshot, "native binary fleet roundtrip preserves bay")
			var road := {"start": pose.origin - Vector3.FORWARD * 10, "finish": pose.origin + Vector3.FORWARD * 10, "half_width": 3.0}
			check(not Parking.admit(structures.blocks, structures.model_collections(), candidate, [road]).ok, "parking cannot overlap public road")
			var cell := Vector3i(pose.origin.floor())
			structures.blocks.set_cells(PackedInt32Array([cell.x, cell.y, cell.z, structures.blocks.encode_block(1, 0, 0)]))
			check(not Parking.admit(structures.blocks, structures.model_collections(), candidate).ok, "new solid obstruction prevents admission")
			structures.blocks.set_cells(PackedInt32Array([cell.x, cell.y, cell.z, 0]))
			var floor_cell := Vector3i((pose.origin - Vector3.UP).floor())
			var word: int = structures.blocks.get_cell(floor_cell)
			structures.blocks.set_cells(PackedInt32Array([floor_cell.x, floor_cell.y, floor_cell.z, 0]))
			check(not Parking.admit(structures.blocks, structures.model_collections(), candidate).ok, "missing floor prevents admission")
			structures.blocks.set_cells(PackedInt32Array([floor_cell.x, floor_cell.y, floor_cell.z, word]))
		check(asset.get_records() == original, "approved building geometry remains unchanged")
	var lots: Array = []
	for index in 60: lots.append({"asset": Catalog.asset("house_c1"), "origin": Vector3i(100 + index * 20, 30, 400), "rotation": index % 4})
	var chosen := Parking.candidates(lots, 1703)
	check(chosen == Parking.candidates(lots, 1703) and chosen.size() == 60 and chosen[0].origin != lots[0].origin, "deterministic ranked fallback garages before bounded admission quota")
	check(Parking.candidates([{"asset": Catalog.asset("trader_t1"), "origin": Vector3i.ZERO, "rotation": 0}], 1703).is_empty(), "unqualified buildings are not used for parking")
	var host := GenerationHost.new(); root.add_child(host); host.add_child(host.world_vehicle); host.structures = structures
	var warehouse: Dictionary = {"asset": Catalog.asset("warehouse_w1"), "origin": Vector3i(100, 30, 100), "rotation": 3}
	var seeded := Parking.seed_generated(host, [warehouse], [], 1703)
	check(seeded.ok and seeded.placements.size() == 1 and host.terrain.changed_since_save, "generation publishes only an admitted vehicle and marks persistence dirty")
	var before: PackedByteArray = host.world_vehicle.fleet.capture_storage_snapshot()
	var repeated := Parking.seed_generated(host, [warehouse], [], 1703)
	check(repeated.ok and repeated.placements.is_empty() and repeated.skipped[0].reason == "Existing vehicle nearby", "existing fleet record prevents duplicate bay population")
	check(host.world_vehicle.fleet.capture_storage_snapshot() == before, "duplicate admission leaves original fleet bytes unchanged")
	host.world_vehicle.packs.vehicles.clear()
	check(not Parking.seed_generated(host, [warehouse], [], 1703).ok and host.world_vehicle.fleet.capture_storage_snapshot() == before, "missing provider fails without mutating fleet")
	host.free()
	structures.free()
	print("BUILDING_PARKING checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
