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
var obstacle_provider: Callable
var navigator: Node3D
var navigation_status: Dictionary={}
var _obstacles: Dictionary={}
var _obstacle_clock: Dictionary={}
var _navigation_exclusions: Array[RID]=[]
var residents: Array = []
var _spawn_clock := 0.0
var _sequence := 0
var _corpse_age: Dictionary = {}
var _capsule: CapsuleShape3D

func _ready() -> void:
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = 1.8
	navigator=ClassDB.instantiate("NativeActorNavigator")
	add_child(navigator)
	if not navigator.configure(LIMIT):push_error("Zombie navigation initialization failed")

func clear() -> void:
	for zombie in residents:
		if is_instance_valid(zombie):
			zombie.queue_free()
	residents.clear()
	for obstacle in _obstacles.values():
		if is_instance_valid(obstacle):obstacle.queue_free()
	_obstacles.clear();_obstacle_clock.clear()
	if navigator!=null:navigator.clear()
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
		if not ready and not zombie.alive:
			_retire(index)
	_update_navigation(delta,available and pursue)
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

func invalidate_navigation(bounds: AABB=AABB()) -> void:
	if navigator!=null:navigator.invalidate(bounds)
	_obstacle_clock.clear()

func _dry_route(point: Vector3) -> bool:
	return not water_depth.is_valid() or float(water_depth.call(point-Vector3.UP*0.83))<=0.0

func _update_navigation(delta: float, available: bool) -> void:
	var excluded: Array[RID]=[]
	if target.get_parent() is PhysicsBody3D:excluded.append(target.get_parent().get_rid())
	# Refresh only when the recipient body changes: assignment invalidates routes.
	if excluded!=_navigation_exclusions:
		navigator.set_exclusions(excluded);_navigation_exclusions=excluded
	for zombie in residents:
		var id:int=zombie.get_instance_id()
		_obstacle_clock[id]=float(_obstacle_clock.get(id,0.0))-delta
		var obstacle:Node3D=_obstacles.get(id)
		if is_instance_valid(obstacle) and not obstacle.available():
			obstacle.queue_free();_obstacles.erase(id);obstacle=null
		if available and zombie.alive and not zombie._crawling and not is_instance_valid(obstacle) and float(_obstacle_clock[id])<=0 and obstacle_provider.is_valid():
			_obstacle_clock[id]=0.5
			obstacle=obstacle_provider.call(zombie)
			if obstacle!=null:_obstacles[id]=obstacle
		zombie.set_behavior_target(obstacle if is_instance_valid(obstacle) else target)
		var start:Vector3=zombie.global_position+Vector3.UP*1.1
		var end:Vector3=zombie.target.global_position+Vector3.UP*1.1
		var ray:=PhysicsRayQueryParameters3D.create(start,end,7,excluded)
		var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
		zombie.navigation_attack_clear=(hit.is_empty() or (is_instance_valid(obstacle) and hit.get("collider")==obstacle.surface)) and absf(zombie.target.global_position.y-zombie.global_position.y)<=0.5
		var goal:Vector3=obstacle.approach_point if is_instance_valid(obstacle) else target.global_position
		var distance:Vector3=zombie.target.global_position-zombie.global_position;distance.y=0
		var needs_route:bool=available and zombie.alive and zombie.process_mode!=Node.PROCESS_MODE_DISABLED and zombie._active_action.is_empty() and zombie._hit_timer<=0 and (distance.length()>1.0 or not zombie.navigation_attack_clear)
		navigator.set_agent(id,zombie.global_position,goal,1 if zombie._crawling else 0,needs_route)
	navigation_status=navigator.advance(delta,readiness,_dry_route)
	for zombie in residents:
		var id:int=zombie.get_instance_id()
		zombie.navigation_target=navigator.steering_target(id)
		# Within melee range the source controller may approach its contact
		# distance, but each actual step still passes the shared native guard.
		var offset:Vector3=zombie.target.global_position-zombie.global_position;offset.y=0
		if zombie.navigation_attack_clear and offset.length()<=1.0:
			zombie.navigation_target=zombie.target.global_position

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
	var id:int=zombie.get_instance_id()
	navigator.remove_agent(id);_obstacle_clock.erase(id)
	if _obstacles.has(id):
		if is_instance_valid(_obstacles[id]):_obstacles[id].queue_free()
		_obstacles.erase(id)
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
	zombie.navigator=navigator
	zombie.navigation_motor=ClassDB.instantiate("NativePlayerMovement")
	var excluded: Array[RID]=[]
	if target.get_parent() is PhysicsBody3D:excluded.append(target.get_parent().get_rid())
	if excluded!=_navigation_exclusions:
		navigator.set_exclusions(excluded);_navigation_exclusions=excluded
	add_child(zombie)
	residents.append(zombie)
	var id:int=zombie.get_instance_id()
	zombie.tree_exiting.connect(func():
		if is_instance_valid(navigator):navigator.remove_agent(id))
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
