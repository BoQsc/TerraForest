# SPDX-License-Identifier: 0BSD
extends RefCounted

const Catalog = preload("res://addons/house_lights/catalog.gd")
const Parking = preload("res://addons/vehicle_runtime/building_parking.gd")
const LIMIT := 2048

static func publish(game: Node, lots: Array) -> Dictionary:
	var started := Time.get_ticks_usec()
	var catalog := Catalog.new()
	if not catalog.prepare(): return {"ok": false, "reason": "House-light definitions unavailable"}
	var models: Dictionary = game.structures.model_collections()
	var plans: Dictionary = {}
	var placements: Array[Dictionary] = []
	var skipped: Array[Dictionary] = []
	var room_count := 0
	var sleepers := preload("res://addons/characters/runtime/house_sleepers.gd").plan(lots, game.terrain.backend.world_seed)
	if not sleepers.ok: return {"ok": false, "reason": "Room encounter reservations unavailable"}
	for lot: Dictionary in lots:
		var asset: Resource = lot.asset
		var digest := HashingContext.new(); digest.start(HashingContext.HASH_SHA256)
		digest.update(asset.get_records().to_byte_array()); digest.update(var_to_bytes(asset.get_model_attachments()))
		var identity := digest.finish().hex_encode()
		if not plans.has(identity): plans[identity] = asset.interior_light_sites()
		var plan: Dictionary = plans[identity]
		if not plan.ok: return {"ok": false, "reason": "Room survey exceeds authoring budget", "lot": lot.label}
		var basis := Basis(Vector3.UP, -int(lot.rotation) * PI * .5)
		var half := Vector3(.5, 0, .5)
		var frame := Transform3D(basis, Vector3(lot.origin) + half - basis * half)
		var fireplace_placed := false
		for room: Dictionary in plan.rooms:
			room_count += 1
			if placements.size() >= LIMIT: return {"ok": false, "reason": "World-light placement budget exceeded"}
			var placed := false
			var kind := "lighting/room_lamp/v1"
			var building: String = asset.get_meta("expansion_id", "")
			if building in ["cottage_a2", "house_c1"]:
				var grade := int(asset.get_meta("site_surface_offset", 0))
				if int(room.floor) < grade: kind = "lighting/standing_torch/v1"
				elif int(room.floor) == grade and room.area >= 20 and not fireplace_placed: kind = "lighting/iron_fireplace/v1"
			var definition: Dictionary = catalog.definitions[kind]
			for point: Vector3 in room.candidates:
				var pose := frame * Transform3D(Basis.IDENTITY, point)
				var bounds: AABB = pose * definition.bounds
				if "_initial_generation_spawn" in game and bounds.grow(.8).has_point(game._initial_generation_spawn): continue
				if not Parking._clear(game.structures.blocks, models, bounds.grow(-.005)): continue
				if not Parking._floor(game.structures.blocks, Transform3D(basis, pose.origin), definition.bounds.size.x * .48, definition.bounds.size.z * .48): continue
				var near_car: Dictionary = game.world_vehicle.fleet.query_near(pose.origin, 5, 32, 128)
				if not near_car.ok or not near_car.complete or not near_car.ids.is_empty(): continue
				var reserved := false
				for anchor: Dictionary in sleepers.anchors:
					if bounds.intersects(AABB(anchor.position - Vector3(1, .1, 1), Vector3(2, 2, 2))): reserved = true; break
				for location: Dictionary in game.quests.store.get_locations():
					if location.bounds.intersects(bounds): reserved = true; break
				if reserved: continue
				var packed := PackedFloat32Array()
				for row in 3:
					for column in 3: packed.append(pose.basis[column][row])
					packed.append(pose.origin[row])
				var placement_id: int = models[kind].insert_instance(packed, AABB())
				if placement_id == 0: return {"ok": false, "reason": "Native light-object publication failed"}
				placements.append({"asset": kind, "id": placement_id, "position": pose.origin, "building": building, "room_floor": room.floor})
				if kind == "lighting/iron_fireplace/v1": fireplace_placed = true
				placed = true; break
			if not placed: skipped.append({"lot": lot.get("label", "Building"), "floor": room.floor, "area": room.area, "reason": "No supported unobstructed light position"})
	if not placements.is_empty(): game.terrain.changed_since_save = true
	return {"ok": true, "rooms": room_count, "placements": placements, "skipped": skipped, "elapsed_us": Time.get_ticks_usec() - started}
