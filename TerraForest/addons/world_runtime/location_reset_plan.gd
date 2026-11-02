# SPDX-License-Identifier: 0BSD
extends RefCounted

const Capture = preload("res://addons/world_runtime/location_capture.gd")
const Scope = preload("res://addons/world_runtime/location_patch_scope.gd")
const Batch = preload("res://addons/world_runtime/location_reset_batch.gd")
const CHEST := "storage/wooden_chest/v1"
var operations: Array = []
var protections: Array = []
var guards: Array = []
var reason := ""
var retained_bytes := 0

func create_batch() -> RefCounted:
	var batch := Batch.new()
	batch.prepare(operations, guards)
	return batch

static func context(game: Node) -> Dictionary:
	return {"field": game.terrain.backend.native, "blocks": game.structures.blocks, "models": game.structures.model_collections(), "doors": game.doors.types, "water": game.lakes.water, "containers": game.storage.store, "residents": game.zombies.population.store, "corpses": game.corpse_loot.store, "trees": game.ecosystem.harvest_state, "ground": game.ground_cover.removed, "damage": game.world_attack.durability, "rock_damage": game.ground_cover.rock_damage, "inventory": game.player_hud.inventory, "seed": game.terrain.backend.world_seed, "density": game.ecosystem.density, "biome": game.ecosystem.biome_profile, "min_up": cos(deg_to_rad(game.ecosystem.max_slope_degrees)), "groves": game.ecosystem._scatter().capture_storage_snapshot()}

func load_and_prepare(game: Node, location: Dictionary) -> Dictionary:
	var worker := Thread.new()
	if worker.start(game.persistence.location_baselines.load_baseline.bind(location.key, Capture.definition(location))) != OK:
		return {"ok": false, "reason": "original_reader_unavailable"}
	while worker.is_alive():
		await game.get_tree().process_frame
	var original: Dictionary = worker.wait_to_finish()
	if not original.get("ok", false):
		return original
	return prepare(context(game), location, original.sections)

func _fail(message: String) -> Dictionary:
	reason = message
	operations.clear()
	protections.clear()
	return {"ok": false, "reason": reason}

static func ordered(ids: PackedInt64Array) -> PackedInt64Array:
	var result := ids.duplicate()
	result.sort()
	return result

static func united(first: PackedInt64Array, second: PackedInt64Array) -> PackedInt64Array:
	var selected: Dictionary = {}
	for identity in first:
		selected[identity] = true
	for identity in second:
		selected[identity] = true
	return ordered(PackedInt64Array(selected.keys()))

static func added(current: PackedInt64Array, original: PackedInt64Array) -> PackedInt64Array:
	var existing: Dictionary = {}
	for identity in original:
		existing[identity] = true
	var result := PackedInt64Array()
	for identity in current:
		if not existing.has(identity):
			result.append(identity)
	return result

func _append(owner: Object, kind: String, arguments: Array, original: PackedByteArray) -> Dictionary:
	var token: Dictionary = owner.call(kind + "_patch_state")
	var before := Capture.patch(owner, kind, arguments)
	var desired := Scope.describe(owner, kind, original)
	var current := Scope.describe(owner, kind, before)
	if desired.is_empty() or current.is_empty() or desired.arguments != arguments or current.arguments != arguments or desired.signature != current.signature:
		reason = "scope_or_readiness:" + kind
		return {}
	if owner.call(kind + "_patch_state") != token:
		reason = "owner_changed_during_plan:" + kind
		return {}
	retained_bytes += original.size() + before.size()
	if operations.size() >= Batch.MAX_OPERATIONS or retained_bytes > Batch.MAX_BYTES:
		reason = "plan_limit"
		return {}
	operations.append({"target": owner, "kind": kind, "arguments": arguments, "original": original, "captured": before, "expected": token})
	guards.append([owner, kind, token])
	return {"original": desired, "current": current, "before": before}

func _grid(owner: Object, kind: String, bounds: AABB, records: Array, scale: int = 1, lattice: bool = false) -> bool:
	var tiles := Capture.tiles(Vector3i(bounds.position) * scale, Vector3i(bounds.size) * scale + (Vector3i.ONE if lattice else Vector3i.ZERO))
	if tiles.size() != records.size():
		reason = "tile_count:" + kind
		return false
	for index in tiles.size():
		if not records[index] is PackedByteArray or _append(owner, kind, tiles[index], records[index]).is_empty():
			return false
	return true

static func closed_doors(owner: Object, ids: PackedInt64Array) -> PackedByteArray:
	var current := Capture.patch(owner, "door", [ids])
	if Scope.describe(owner, "door", current).is_empty():
		return PackedByteArray()
	var result := current.slice(0, 88)
	var empty := PackedByteArray()
	empty.resize(112)
	empty.fill(0)
	for index in ids.size():
		result.append_array(current.slice(88 + index * 120, 96 + index * 120))
		result.append_array(empty)
	result.append_array(Capture.digest(result))
	return result

func prepare(owners: Dictionary, location: Dictionary, sections: Dictionary) -> Dictionary:
	if not operations.is_empty() or not reason.is_empty():
		return {"ok": false, "reason": "plan_already_used"}
	var bounds: AABB = location.bounds
	if not Capture.valid_bounds(bounds):
		return _fail("location_bounds")
	var records: Dictionary = {}
	for kind: String in Capture.OWNERS:
		if not sections.get(kind) is PackedByteArray:
			return _fail("missing_owner:" + kind)
		var envelope := Capture.unpack(sections[kind], kind, bounds)
		if envelope.is_empty():
			return _fail("owner_envelope:" + kind)
		records[kind] = envelope.records
	if not _grid(owners.field, "field", bounds, records.terrain, 1, true) or not _grid(owners.field, "cube", bounds, records.cubes) or not _grid(owners.blocks, "cell", bounds, records.blocks) or not _grid(owners.water, "water", bounds, records.water, 2):
		return _fail(reason if not reason.is_empty() else "invalid_grid_record")
	var model_ids: Dictionary = {}
	var current_ids: Dictionary = {}
	var exact := PackedStringArray()
	if records.models.size() != owners.models.size():
		return _fail("model_namespaces_changed")
	for row: Variant in records.models:
		if not row is Array or row.size() != 4 or not row[0] is String or not row[1] is PackedByteArray or not row[2] is PackedInt64Array or not row[3] is PackedInt64Array or not owners.models.has(row[0]) or model_ids.has(row[0]):
			return _fail("model_record")
		var collection: Node3D = owners.models[row[0]]
		if collection.global_transform != Transform3D.IDENTITY:
			return _fail("transformed_model_collection")
		var selected := _append(collection, "placement", [Vector3i(bounds.position), Vector3i(bounds.size)], row[1])
		if selected.is_empty():
			return _fail(reason + ":" + row[0])
		if selected.original.asset != row[0] or selected.original.ids != ordered(row[2]) or not added(row[3], row[2]).is_empty() or united(row[3], row[3]).size() != row[3].size():
			return _fail("model_identity")
		model_ids[row[0]] = selected.original.ids
		current_ids[row[0]] = selected.current.ids
		for identity in selected.original.ids:
			if not selected.current.ids.has(identity) and not collection.get_instance(identity).is_empty():
				return _fail("original_model_moved_outside")
		for identity in united(selected.original.ids, selected.current.ids):
			exact.append("model:%s:%d" % [row[0], identity])
			protections.append({"target": collection, "id": identity, "current": collection.is_removal_protected(identity), "original": row[3].has(identity)})
	var door_names: Dictionary = {}
	if records.doors.size() != owners.doors.size():
		return _fail("door_namespaces_changed")
	for row: Variant in records.doors:
		if not row is Array or row.size() != 3 or not row[0] is String or not row[1] is PackedInt64Array or not row[2] is PackedByteArray or not owners.doors.has(row[0]) or door_names.has(row[0]) or ordered(row[1]) != model_ids.get(row[0]):
			return _fail("door_record")
		door_names[row[0]] = true
		var hinges: RefCounted = owners.doors[row[0]].state
		if not row[1].is_empty():
			if _append(hinges, "door", [ordered(row[1])], row[2]).is_empty():
				return _fail(reason)
		elif not row[2].is_empty():
			return _fail("nonempty_unowned_door_patch")
		var extra := added(current_ids[row[0]], model_ids[row[0]])
		if not extra.is_empty() and _append(hinges, "door", [extra], closed_doors(hinges, extra)).is_empty():
			return _fail(reason)
	var resident_ids: PackedInt64Array = owners.residents.authored_identities(location.residents)
	if resident_ids.size() != location.residents.size():
		return _fail("resident_identity")
	var anchor_pairs: Dictionary = {}
	for index in resident_ids.size():
		anchor_pairs[resident_ids[index]] = location.residents[index]
	resident_ids = ordered(resident_ids)
	var anchors := PackedInt64Array()
	for identity in resident_ids:
		anchors.append(anchor_pairs[identity])
	for spec: Array in [["containers", "container", [ordered(location.containers)]], ["residents", "resident", [resident_ids]], ["corpses", "corpse", [resident_ids, anchors]]]:
		if records[spec[0]].size() != 1 or not records[spec[0]][0] is PackedByteArray:
			return _fail("identity_record:" + spec[0])
		var selected := _append(owners[spec[0]], spec[1], spec[2], records[spec[0]][0])
		if selected.is_empty() or (spec[1] == "resident" and selected.original.anchors != anchors):
			return _fail(reason if not reason.is_empty() else "resident_anchor")
	if model_ids.get(CHEST, PackedInt64Array()) != ordered(location.containers):
		return _fail("container_model_ownership")
	var extra_chests := added(current_ids.get(CHEST, PackedInt64Array()), model_ids.get(CHEST, PackedInt64Array()))
	if not extra_chests.is_empty():
		var schema: PackedByteArray = records.containers[0]
		var empty: RefCounted = ClassDB.instantiate("NativeContainerStore")
		if not empty.configure(owners.inventory, 64, schema.decode_u32(12), schema.decode_u64(16)):
			return _fail("container_schema")
		if _append(owners.containers, "container", [extra_chests], Capture.patch(empty, "container", [extra_chests])).is_empty():
			return _fail(reason)
	if records.trees.size() != 7 or not records.trees[0] is PackedInt64Array or not records.trees[1] is PackedByteArray or records.trees.slice(2) != [owners.seed, owners.density, owners.biome, owners.min_up, owners.groves]:
		return _fail("tree_generation_identity")
	if not records.trees[0].is_empty():
		if _append(owners.trees, "harvest", [ordered(records.trees[0])], records.trees[1]).is_empty():
			return _fail(reason)
	elif not records.trees[1].is_empty():
		return _fail("nonempty_unowned_tree_patch")
	if records.ground.size() != 2 or not records.ground[0] is PackedInt64Array or not records.ground[1] is PackedByteArray:
		return _fail("ground_record")
	var plants := _append(owners.ground, "ground", [bounds, ordered(records.ground[0])], records.ground[1])
	if plants.is_empty():
		return _fail(reason)
	for identity in united(ordered(records.ground[0]), united(plants.original.plants, plants.current.plants)):
		exact.append("cover:%d" % identity)
	if records.damage.size() != 3 or records.damage[0] != "pristine_generation":
		return _fail("damage_record")
	var handled: Dictionary = {}
	for index in 2:
		var owner: RefCounted = owners.damage if index == 0 else owners.rock_damage
		if not records.damage[index + 1] is PackedByteArray or not owner.validate_snapshot(records.damage[index + 1]) or records.damage[index + 1].size() != 8:
			return _fail("damage_original_not_pristine")
		if handled.has(owner.get_instance_id()):
			continue
		handled[owner.get_instance_id()] = true
		var token: Dictionary = owner.damage_patch_state()
		guards.append([owner, "damage", token])
		var selected: Dictionary = owner.select_damage_keys(bounds, exact, token.revision, token.owner)
		if not selected.get("ok", false):
			return _fail("damage_selection:" + str(selected.get("reason", "unknown")))
		for offset in range(0, selected["keys"].size(), 4096):
			var keys: PackedStringArray = selected["keys"].slice(offset, offset + 4096)
			var pristine: RefCounted = ClassDB.instantiate("NativeWorldDurability")
			if _append(owner, "damage", [keys], Capture.patch(pristine, "damage", [keys])).is_empty():
				return _fail(reason)
	for guard: Array in guards:
		if guard[0].call(guard[1] + "_patch_state") != guard[2]:
			return _fail("owner_changed_during_plan")
	return {"ok": true, "operations": operations, "protections": protections, "guards": guards, "bounds": bounds, "resident_ids": resident_ids, "anchors": anchors, "bytes": retained_bytes}
