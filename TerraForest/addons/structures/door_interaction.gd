# SPDX-License-Identifier: 0BSD
extends RefCounted
## Click-time routing only. Each model type owns one native hinge store.
const LEGACY_KEY := "architecture/wooden_door/v1"
# Retain these aliases for existing world-generation clients and saved worlds.
var state: RefCounted
var collection: Node3D
var game: Node
var types: Dictionary = {}
var _by_collection: Dictionary = {}

func prepare(world: Node) -> bool:
	game = world
	var providers: Array[Dictionary] = []
	for id: String in game.structures.object_definitions:
		var definition: Dictionary = game.structures.object_definitions[id]
		if definition.behavior.type != "hinged_door": continue
		var batch: Node3D = game.structures.model(id)
		var hinges: RefCounted = ClassDB.instantiate("NativeHingedDoors")
		var pivot: Array = definition.behavior.pivot
		if batch == null or not hinges.configure(definition.bounds, Vector3(pivot[0], pivot[1], pivot[2]), definition.behavior.opening_degrees): return false
		var entry := {"id":id, "collection":batch, "state":hinges, "definition":definition}
		types[id] = entry
		_by_collection[batch.get_instance_id()] = entry
		# Stable model-ID digest avoids cross-type placement-ID collisions.
		var section := "door_hinges" if id == LEGACY_KEY else "door_" + id.sha256_text().left(40)
		providers.append({"name":section, "capture":hinges.capture_storage_snapshot, "restore":hinges.restore_storage_snapshot, "validator":hinges, "empty":hinges.capture_storage_snapshot()})
		if id == LEGACY_KEY:
			state = hinges
			collection = batch
	return collection != null and game.persistence.register_components(providers)

func for_collection(batch: Object) -> Dictionary:
	return _by_collection.get(batch.get_instance_id(), {}) if is_instance_valid(batch) else {}

func aimed(hit: Dictionary) -> Dictionary:
	var entry := for_collection(hit.get("collider"))
	if entry.is_empty() or not hit.has("rid"): return {}
	var identity: int = entry.collection.placement_for_body(hit.rid)
	if identity <= 0: return {}
	return {"identity":identity, "type":entry}

func aimed_id(hit: Dictionary) -> int:
	return aimed(hit).get("identity", 0)

func describe(hit: Dictionary) -> String:
	var target := aimed(hit)
	if target.is_empty(): return ""
	var entry: Dictionary = target.type
	return "E · %s %s" % ["Close" if entry.state.is_open(target.identity) else "Open", entry.definition.name.to_lower()]

func forget(batch: Node3D, identity: int) -> void:
	var entry := for_collection(batch)
	if not entry.is_empty(): entry.state.forget(identity)

func try_interact(shared_hit: Variant = null) -> bool:
	if not game._model_edit_available(): return false
	var start: Vector3 = game.camera.global_position
	var hit: Dictionary = game.structures.blocks.raycast_scene(start, start-game.camera.global_basis.z*3, 7, [game.player.get_rid()], true) if shared_hit == null else shared_hit
	var target := aimed(hit)
	if target.is_empty(): return false
	var entry: Dictionary = target.type
	var result: Dictionary = entry.state.toggle(entry.collection, target.identity, AABB())
	if result.ok: game.terrain.changed_since_save = true
	game._show_lake_notice(result.reason)
	return true

func breakable_bodies(limit: int = 64) -> Array[RID]:
	var result: Array[RID] = []
	for entry: Dictionary in types.values():
		if not entry.definition.behavior.zombie_breakable: continue
		for identity: int in entry.collection.collision_identities():
			if result.size() >= limit: return result
			if entry.state.is_open(identity) or entry.collection.is_removal_protected(identity): continue
			var rid: RID = entry.collection.collision_body_for(identity)
			if rid.is_valid(): result.append(rid)
	return result
