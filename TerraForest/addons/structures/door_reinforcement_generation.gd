# SPDX-License-Identifier: 0BSD
extends RefCounted

const DOOR := "architecture/wooden_door/v1"
const HOMES := ["cottage_a2", "house_c1"]
const ONE_IN := 8

static func candidates(lots: Array, world_seed: int, spawn: Vector3) -> Array[Transform3D]:
	var selected: Array[Transform3D] = []
	for lot: Dictionary in lots:
		if not lot.asset.get_meta("expansion_id", "") in HOMES: continue
		var bounds: AABB = lot.asset.placement_bounds(lot.origin, lot.rotation)
		if bounds.grow(2).has_point(spawn): continue
		var origin: Vector3i = lot.origin
		var random := RandomNumberGenerator.new()
		random.seed = world_seed ^ (origin.x * 73856093) ^ (origin.y * 19349663) ^ (origin.z * 83492791) ^ int(lot.rotation) ^ 0x54d8a29
		if random.randi_range(1, ONE_IN) != 1: continue
		var attachments: Array = lot.asset.get_model_attachments().filter(func(row: Dictionary) -> bool: return row.model == DOOR)
		if attachments.is_empty(): continue
		var rotation := Basis(Vector3.UP, -int(lot.rotation) * PI * .5)
		var half := Vector3(.5, 0, .5)
		var pose := Transform3D(rotation, Vector3(origin) + half - rotation * half)
		selected.append(pose * attachments[random.randi_range(0, attachments.size() - 1)].transform)
	return selected

static func seed_generated(game: Node, lots: Array, world_seed: int) -> Dictionary:
	var entry: Dictionary = game.doors.types.get(DOOR, {})
	if entry.is_empty() or not entry.has("locks"): return {"ok": false, "reason": "Door reinforcement owner unavailable"}
	var lookup: Dictionary = {}
	for identity: int in entry.collection.get_ids():
		var values: PackedFloat32Array = entry.collection.get_instance(identity)
		if values.size() != 12: return {"ok": false, "reason": "Generated door not resident"}
		var point := Vector3i((Vector3(values[3], values[7], values[11]) * 1000).round())
		if not lookup.has(point): lookup[point] = []
		lookup[point].append(identity)
	var selected := candidates(lots, world_seed, game._initial_generation_spawn)
	var locked := PackedInt64Array()
	var placements: Array = []
	for pose: Transform3D in selected:
		var identity := 0
		for candidate: int in lookup.get(Vector3i((pose.origin * 1000).round()), []):
			if game.doors._pose(entry.collection.get_instance(candidate)).is_equal_approx(pose):
				if identity != 0: return {"ok": false, "reason": "Ambiguous generated door identity"}
				identity = candidate
		if identity == 0: return {"ok": false, "reason": "Generated reinforcement door missing"}
		if entry.collection.is_removal_protected(identity) or entry.state.is_open(identity): continue
		if not entry.locks.seed(identity, entry.definition.durability.health * 2, world_seed ^ identity):
			return {"ok": false, "reason": "Door reinforcement capacity exceeded"}
		locked.append(identity)
		placements.append({"id": identity, "position": [pose.origin.x, pose.origin.y, pose.origin.z]})
	if not locked.is_empty(): game.terrain.changed_since_save = true
	return {"ok": true, "candidates": selected.size(), "locked": locked, "doors": placements, "one_in_homes": ONE_IN}
