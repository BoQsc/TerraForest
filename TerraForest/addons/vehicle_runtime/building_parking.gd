# SPDX-License-Identifier: 0BSD
extends RefCounted

const KIND := "terraforest.ranger.v1"
const MAX_PARKED := 32
const CHASSIS := AABB(Vector3(-1.25, -.65, -2.4), Vector3(2.5, 2.1, 4.8))
const CATALOG := {
	"house_c1": {"point": Vector3(9.5, 5.85, 3.5), "portal": Vector3(9.5, 5.85, 9.5), "exit": Vector3(6.7, 5, 3.5), "walk": [Vector3(6.7, 5, 6.5), Vector3(7.5, 5, 6.5), Vector3(7.5, 5, 7.5)]},
	"warehouse_w1": {"point": Vector3(13.5, 5.85, 25), "portal": Vector3(13.5, 5.85, 34), "exit": Vector3(10.7, 5, 25), "walk": [Vector3(10.7, 5, 27), Vector3(11.5, 5, 27), Vector3(11.5, 5, 33)]}
}

static func candidates(lots: Array, world_seed: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for lot: Dictionary in lots:
		var kind: String = lot.asset.get_meta("expansion_id", "")
		if not CATALOG.has(kind): continue
		var origin: Vector3i = lot.origin
		var random := RandomNumberGenerator.new()
		random.seed = world_seed ^ (origin.x * 73856093) ^ (origin.y * 19349663) ^ (origin.z * 83492791) ^ 0x6523f19
		var basis := Basis(Vector3.UP, -int(lot.rotation) * PI * .5)
		var half := Vector3(.5, 0, .5)
		var frame := Transform3D(basis, Vector3(origin) + half - basis * half)
		var bay: Dictionary = CATALOG[kind]
		var walk := PackedVector3Array([frame * bay.exit])
		for point: Vector3 in bay.walk: walk.append(frame * point)
		result.append({"building": kind, "pose": frame * Transform3D(Basis.IDENTITY, bay.point), "portal": frame * bay.portal, "walk": walk, "origin": origin, "rotation": lot.rotation, "rank": random.randi()})
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return first.rank < second.rank if first.rank != second.rank else str(first.origin) < str(second.origin))
	return result

static func _clear(blocks: Node3D, models: Dictionary, volume: AABB) -> bool:
	var poses: Array[Transform3D] = [Transform3D.IDENTITY]
	if blocks.overlap_mask(poses, volume) != PackedByteArray([0]): return false
	for collection: Node3D in models.values():
		if collection.overlap_mask(poses, volume) != PackedByteArray([0]): return false
	return true

static func _floor(blocks: Node3D, frame: Transform3D, half_width: float, half_length: float) -> bool:
	var points := PackedVector3Array()
	var columns := ceili(half_width * 4)
	var rows := ceili(half_length * 4)
	for column in columns + 1:
		for row in rows + 1:
			var point := frame * Vector3(lerpf(-half_width, half_width, float(column) / columns), 0, lerpf(-half_length, half_length, float(row) / rows))
			points.append(point - Vector3.UP * .02)
			points.append(point + Vector3.UP * .02)
	var samples: PackedByteArray = blocks.sample_solid(points)
	if samples.size() != points.size(): return false
	for index in samples.size():
		if samples[index] != (1 if index % 2 == 0 else 0): return false
	return true

static func admit(blocks: Node3D, models: Dictionary, candidate: Dictionary, roads: Array = [], reserved: Array[AABB] = []) -> Dictionary:
	var pose: Transform3D = candidate.pose
	var chassis: AABB = pose * CHASSIS
	var departure: AABB = chassis.merge(Transform3D(pose.basis, candidate.portal) * CHASSIS)
	for volume: AABB in reserved:
		if volume.intersects(departure): return {"ok": false, "reason": "Reserved encounter or quest"}
	if not _clear(blocks, models, chassis): return {"ok": false, "reason": "Occupied chassis"}
	var floor_pose := Transform3D(pose.basis, pose.origin - Vector3.UP * .85)
	if not _floor(blocks, floor_pose, 1.15, 2.25): return {"ok": false, "reason": "Incomplete parking support"}
	if not _clear(blocks, models, departure): return {"ok": false, "reason": "Blocked vehicle departure"}
	var walk: PackedVector3Array = candidate.walk
	for index in walk.size():
		var start: Vector3 = walk[maxi(index - 1, 0)]
		var end: Vector3 = walk[index]
		var low := start.min(end) + Vector3(-.35, .04, -.35)
		var volume := AABB(low, (start - end).abs() + Vector3(.7, 1.85, .7))
		for reservation: AABB in reserved:
			if reservation.intersects(volume): return {"ok": false, "reason": "Reserved encounter or quest"}
		if volume.intersects(chassis) or not _clear(blocks, models, volume): return {"ok": false, "reason": "Blocked pedestrian exit"}
		var steps := maxi(1, ceili(start.distance_to(end) * 4))
		for step in steps + 1:
			var feet := start.lerp(end, float(step) / steps)
			if not _floor(blocks, Transform3D(Basis.IDENTITY, feet), .3, .3): return {"ok": false, "reason": "Unsupported pedestrian exit"}
	for road: Dictionary in roads:
		var start: Vector3 = road.start
		var finish: Vector3 = road.finish
		var closest := Geometry2D.get_closest_point_to_segment(Vector2(pose.origin.x, pose.origin.z), Vector2(start.x, start.z), Vector2(finish.x, finish.z))
		if closest.distance_to(Vector2(pose.origin.x, pose.origin.z)) < float(road.half_width) + 2.75:
			return {"ok": false, "reason": "Parking overlaps a public approach"}
	return {"ok": true}

static func seed_generated(game: Node, lots: Array, roads: Array, world_seed: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var session: Node = game.world_vehicle
	if not session.fleet_enabled or not session.packs.vehicles.has(KIND): return {"ok": false, "reason": "Parking vehicle provider unavailable"}
	var selected := candidates(lots, world_seed)
	var home_count := 0
	for candidate: Dictionary in selected:
		if candidate.building == "house_c1": home_count += 1
	var home_limit := ceili(home_count / 3.0)
	var homes_parked := 0
	var placements: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	var models: Dictionary = game.structures.model_collections()
	var reserved: Array[AABB] = []
	for location: Dictionary in game.quests.store.get_locations(): reserved.append(location.bounds.grow(1.0))
	var sleepers := preload("res://addons/characters/runtime/house_sleepers.gd").plan(lots, world_seed)
	if not sleepers.ok: return {"ok": false, "reason": "Parking encounter reservations unavailable"}
	for anchor: Dictionary in sleepers.anchors: reserved.append(AABB(anchor.position - Vector3(1, .1, 1), Vector3(2, 2, 2)))
	for candidate: Dictionary in selected:
		if candidate.building == "house_c1" and homes_parked >= home_limit: continue
		if placements.size() >= MAX_PARKED:
			skipped.append({"building": candidate.building, "reason": "Generation parking budget"}); continue
		var fit := admit(game.structures.blocks, models, candidate, roads, reserved)
		if not fit.ok:
			skipped.append({"building": candidate.building, "origin": candidate.origin, "reason": fit.reason}); continue
		var nearby: Dictionary = session.fleet.query_near(candidate.pose.origin, 7, 64, 128)
		if not nearby.ok or not nearby.complete or not nearby.ids.is_empty():
			skipped.append({"building": candidate.building, "reason": "Existing vehicle nearby"}); continue
		var identity: int = session.fleet.spawn_module(candidate.pose, KIND, PackedByteArray())
		if identity == 0: return {"ok": false, "reason": "Native fleet rejected generated parking"}
		var saved: Dictionary = candidate.duplicate()
		saved.id = identity
		placements.append(saved)
		if candidate.building == "house_c1": homes_parked += 1
	if not placements.is_empty(): game.terrain.changed_since_save = true
	return {"ok": true, "placements": placements, "skipped": skipped, "candidates": selected.size(), "limit": MAX_PARKED, "elapsed_us": Time.get_ticks_usec() - started}
