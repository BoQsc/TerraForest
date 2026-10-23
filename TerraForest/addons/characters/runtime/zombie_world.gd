# SPDX-License-Identifier: 0BSD
extends Node3D
## Bounded, session-local encounters. No world generation or saved actor changes.
const Zombie = preload("res://addons/characters/runtime/zombie.gd")
const CHARACTER_LAYER := 1 << 16
const HIT_LAYER := 1 << 17
const RAGDOLL_LAYER := 1 << 18
const LIMIT := 6
const MIN_RADIUS := 12.0
const MAX_RADIUS := 24.0
const RETIRE_RADIUS := 64.0
var enabled := false
var target: Node3D
var readiness: Callable
var water_depth: Callable
var residents: Array = []
var _spawn_clock := 0.0
var _sequence := 0
var _corpse_age: Dictionary = {}
var _capsule: CapsuleShape3D

func _ready() -> void:
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = 1.8

func clear() -> void:
	for zombie in residents:
		if is_instance_valid(zombie):
			zombie.queue_free()
	residents.clear()
	_corpse_age.clear()
	_spawn_clock = 0.0

func update(delta: float, focus: Vector3, available: bool, pursue: bool = true) -> void:
	if not enabled or not is_instance_valid(target):
		if not residents.is_empty():
			clear()
		return
	for index in range(residents.size() - 1, -1, -1):
		var zombie = residents[index]
		if not is_instance_valid(zombie):
			residents.remove_at(index)
			continue
		var id: int = zombie.get_instance_id()
		if not zombie.alive:
			_corpse_age[id] = _corpse_age.get(id, 0.0) + delta
		var bounds := AABB(zombie.global_position - Vector3(1.5, 1, 1.5), Vector3(3, 4, 3))
		# Include the next movement tick and ragdoll reach in readiness checks.
		bounds = bounds.grow(zombie.velocity.length() * delta + 0.1)
		var ready := readiness.is_valid() and bool(readiness.call(bounds))
		if zombie.global_position.distance_to(focus) > RETIRE_RADIUS or float(_corpse_age.get(id, 0.0)) > 20.0 or (not available and not zombie.alive):
			_retire(index)
			continue
		# Disable the entire subtree while loading, editing, or showing menus.
		zombie.process_mode = Node.PROCESS_MODE_INHERIT if available and ready else Node.PROCESS_MODE_DISABLED
		for detached in zombie.detached_parts:
			if is_instance_valid(detached):
				_freeze_detached(detached, not available or not ready)
		zombie.set_behavior(available and ready and pursue)
		if not ready:
			_retire(index)
	_update_spacing()
	if not available:
		return
	_spawn_clock -= delta
	if _spawn_clock > 0.0 or residents.size() >= LIMIT:
		return
	_spawn_clock = 4.0
	# At most four candidate positions and one admission each interval.
	for attempt in 4:
		_sequence += 1
		var angle := float(_sequence) * 2.39996323
		var radius := MIN_RADIUS + float(_sequence % 7) / 6.0 * (MAX_RADIUS - MIN_RADIUS)
		var point := supported_point(focus + Vector3(sin(angle), 0, cos(angle)) * radius)
		if point.is_finite() and spawn_at(point) != null:
			break

func _update_spacing() -> void:
	# At most six actors: 30 ordered neighbour checks, with no world scan.
	for index in residents.size():
		var zombie = residents[index]
		zombie.crowd_steering = Vector3.ZERO
		if not zombie.alive:
			continue
		var approach: Vector3 = target.global_position - zombie.global_position
		approach.y = 0.0
		approach = approach.normalized()
		var sideways := Vector3(-approach.z, 0, approach.x)
		var steering := Vector3.ZERO
		for peer in residents:
			if peer == zombie or not peer.alive:
				continue
			var away: Vector3 = zombie.global_position - peer.global_position
			if absf(away.y) > 1.5:
				continue
			away.y = 0.0
			var distance := away.length()
			if distance >= 1.25:
				continue
			var weight := 1.0 - distance / 1.25
			steering += away.normalized() * weight * 0.7
			if -away.dot(approach) > 0.2:
				# Separation alone makes a following zombie stop behind the first.
				# Pass on the nearer side; break a centred tie consistently.
				var lateral := away.dot(sideways)
				var side := signf(lateral) if absf(lateral) > 0.08 else (1.0 if index % 2 == 0 else -1.0)
				steering += sideways * side * weight * 1.8
		zombie.crowd_steering = steering.limit_length(1.2)

func _freeze_detached(node: Node, frozen: bool) -> void:
	if node is RigidBody3D:
		node.freeze = frozen
	for child in node.get_children():
		_freeze_detached(child, frozen)

func _retire(index: int) -> void:
	var zombie = residents[index]
	_corpse_age.erase(zombie.get_instance_id())
	residents.remove_at(index)
	zombie.queue_free()

func supported_point(around: Vector3) -> Vector3:
	if not around.is_finite() or not readiness.is_valid():
		return Vector3.INF
	var bounds := AABB(around - Vector3(0.6, 4, 0.6), Vector3(1.2, 9, 1.2))
	if not readiness.call(bounds):
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(around + Vector3.UP * 4, around - Vector3.UP * 4, 1)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.78:
		return Vector3.INF
	var point: Vector3 = hit.position + Vector3.UP * 0.04
	if water_depth.is_valid() and float(water_depth.call(point + Vector3.UP * 0.5)) > 0.0:
		return Vector3.INF
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.9)
	query.collision_mask = 1 | 2 | CHARACTER_LAYER | RAGDOLL_LAYER
	if not space.intersect_shape(query, 1).is_empty():
		return Vector3.INF
	return point

func spawn_at(point: Vector3) -> CharacterBody3D:
	if not enabled or not point.is_finite() or residents.size() >= LIMIT or not is_instance_valid(target):
		return null
	var supported := supported_point(point)
	if not supported.is_finite():
		return null
	var zombie := Zombie.new()
	zombie.position = to_local(supported)
	zombie.target = target
	zombie.behavior_enabled = true
	add_child(zombie)
	residents.append(zombie)
	return zombie

func pick(start: Vector3, end: Vector3, exclude: Array) -> Dictionary:
	if not enabled or residents.is_empty():
		return {}
	# Areas must be explicitly enabled; the source controller uses fitted limb areas.
	var omitted: Array[RID] = []
	omitted.assign(exclude)
	for resident in residents:
		if is_instance_valid(resident):omitted.append(resident.get_rid())
	var query := PhysicsRayQueryParameters3D.create(start, end, 1 | 2 | CHARACTER_LAYER | HIT_LAYER | RAGDOLL_LAYER, omitted)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Object = hit.collider
	var zombie: Object = collider.get_meta("zombie") if collider.has_meta("zombie") else null
	if collider in residents:
		zombie = collider
	if not is_instance_valid(zombie) or not zombie.alive or not zombie in residents:
		return {}
	return {"kind": "zombie", "zombie": zombie, "part": collider.get_meta("limb_key", "torso"), "position": hit.position, "normal": hit.normal, "material": "other", "name": "Zombie"}

func apply_hit(hit: Dictionary, damage: float, direction: Vector3) -> bool:
	var zombie: Object = hit.get("zombie")
	if not enabled or not is_instance_valid(zombie) or not zombie in residents or not zombie.alive or zombie.process_mode == Node.PROCESS_MODE_DISABLED:
		return false
	zombie.receive_hit(hit.get("part", "torso"), damage, hit.position, direction * 2.0)
	return true
