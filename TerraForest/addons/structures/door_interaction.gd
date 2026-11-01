# SPDX-License-Identifier: 0BSD
extends Node
## Native motion/collision; compact authored BG5 hardware rigs only while moving.
const LEGACY_KEY := "architecture/wooden_door/v1"
const MOTION:PackedScene=preload("res://addons/structures/door_animation/bg5_motion.scn")
# Retain these aliases for existing world-generation clients and saved worlds.
var state: RefCounted
var collection: Node3D
var game: Node
var types: Dictionary = {}
var _by_collection: Dictionary = {}

func prepare(world: Node) -> bool:
	game = world
	game.add_child(self)
	set_physics_process(game.has_method("_model_edit_available"))
	var providers: Array[Dictionary] = []
	for id: String in game.structures.object_definitions:
		var definition: Dictionary = game.structures.object_definitions[id]
		if definition.behavior.type != "hinged_door": continue
		var batch: Node3D = game.structures.model(id)
		var hinges: RefCounted = ClassDB.instantiate("NativeHingedDoors")
		var pivot: Array = definition.behavior.pivot
		if batch == null or not hinges.configure(definition.bounds, Vector3(pivot[0], pivot[1], pivot[2]), definition.behavior.opening_degrees): return false
		if not hinges.configure_animation(MOTION.get_meta("open_curve"),MOTION.get_meta("close_curve")):return false
		var entry := {"id":id, "collection":batch, "state":hinges, "definition":definition,"visuals":{}}
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
	return "E · %s %s%s" % ["Close" if entry.state.is_open(target.identity) else "Open", entry.definition.name.to_lower()," (swing blocked)" if entry.state.is_blocked(target.identity) else ""]

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
	var result: Dictionary = entry.state.animate_toggle(entry.collection, target.identity, AABB())
	if result.ok:
		game.terrain.changed_since_save = true
		_sync_visuals(entry)
	game._show_lake_notice(result.reason)
	return true

func _physics_process(delta:float)->void:
	if not is_instance_valid(game) or game.loading_active or game.shutdown_requested or not game.terrain.world_ready or game.session_menu.pauses_world() or not game.app_focused:return
	update(delta)

func update(delta:float)->void:
	for entry:Dictionary in types.values():
		if entry.state.advance(entry.collection,delta)>0:game.terrain.changed_since_save=true
		_sync_visuals(entry)

func _vector(value:Array)->Vector3:return Vector3(value[0],value[1],value[2])
func _pose(values:PackedFloat32Array)->Transform3D:
	return Transform3D(Basis(Vector3(values[0],values[4],values[8]),Vector3(values[1],values[5],values[9]),Vector3(values[2],values[6],values[10])),Vector3(values[3],values[7],values[11]))

func _sync_visuals(entry:Dictionary)->void:
	for identity:int in entry.visuals.keys():
		if not entry.state.is_moving(identity) or entry.collection.get_instance(identity).size()!=12:
			entry.collection.set_instance_visual_hidden(identity,false)
			entry.visuals[identity].hide();entry.visuals[identity].queue_free();entry.visuals.erase(identity)
	# A loose replacement owns its visual. Never substitute BG5 hardware over it.
	if entry.definition.visual.source!="builtin:wooden_door":return
	for identity:int in entry.state.moving_ids():
		var values:PackedFloat32Array=entry.collection.get_instance(identity)
		if values.size()!=12:continue
		var motion:Dictionary=entry.state.motion_state(identity)
		if not entry.visuals.has(identity):
			var rig:Node3D=MOTION.instantiate();entry.collection.add_child(rig);entry.visuals[identity]=rig
		var rig:Node3D=entry.visuals[identity]
		var visual:Dictionary=entry.definition.visual
		var fitted:=Transform3D(Basis.from_euler(_vector(visual.get("rotation_degrees",[0,0,0]))*PI/180.0).scaled(_vector(visual.get("scale",[1,1,1]))),_vector(visual.get("offset",[0,0,0])))
		rig.transform=_pose(values)*fitted
		var player:AnimationPlayer=rig.get_node("AnimationPlayer")
		if player.assigned_animation!=motion.clip:player.assigned_animation=motion.clip
		player.seek(motion.time,true)
		if not entry.collection.is_instance_visual_hidden(identity):entry.collection.set_instance_visual_hidden(identity,true)

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
