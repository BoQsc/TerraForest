# SPDX-License-Identifier: 0BSD
extends Node3D
## Bounded scene residency for persistent, seeded world inhabitants.
const Zombie = preload("res://addons/characters/runtime/zombie.gd")
const CHARACTER_LAYER := 1 << 16
const HIT_LAYER := 1 << 17
const RAGDOLL_LAYER := 1 << 18
const LIMIT := 6
const RETIRE_RADIUS := 96.0
var population: RefCounted
var population_enabled := true
var enabled := false
var target: Node3D
var readiness: Callable
var water_depth: Callable
var obstacle_provider: Callable
var navigation_interest:Callable
var spawn_visible:Callable
var world_geometry:Node3D
var corpse_host:Node
var _last_player_position:=Vector3.INF
var awareness:RefCounted
var awareness_status:Dictionary={}
# Explicit navigation/animation fixture override; normal gameplay uses perception.
var force_pursuit:=false
var _sense_clock:Dictionary={}
var _roam_revision:Dictionary={}
var navigator: Node3D
var navigation_status: Dictionary={}
var _obstacles: Dictionary={}
var _obstacle_clock: Dictionary={}
var _navigation_exclusions: Array[RID]=[]
var residents: Array = []
var _corpse_age: Dictionary = {}
var _capsule: CapsuleShape3D
var geometry_template:RefCounted
var profiling_enabled:=false
var update_phase_us:Dictionary={}

func prepare(owner_game: Node, persistence: RefCounted) -> bool:
	population = preload("res://addons/characters/runtime/zombie_population.gd").new()
	return population.prepare(owner_game, self, persistence)

func _ready() -> void:
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = 1.8
	navigator=ClassDB.instantiate("NativeActorNavigator")
	add_child(navigator)
	if not navigator.configure(LIMIT):push_error("Zombie navigation initialization failed")
	awareness=ClassDB.instantiate("NativeZombieAwareness")
	if not awareness.configure(LIMIT,randi()):push_error("Zombie awareness initialization failed")

func clear() -> void:
	if is_instance_valid(corpse_host):corpse_host.clear_live()
	for zombie in residents:
		if is_instance_valid(zombie):
			if population != null:population.sync(zombie)
			zombie.queue_free()
	residents.clear()
	for obstacle in _obstacles.values():
		if is_instance_valid(obstacle):obstacle.queue_free()
	_obstacles.clear();_obstacle_clock.clear()
	_sense_clock.clear();_roam_revision.clear();awareness_status.clear()
	if awareness!=null:awareness.clear()
	if navigator!=null:navigator.clear()
	if navigation_interest.is_valid():navigation_interest.call(PackedVector3Array())
	_corpse_age.clear()
	if population != null:population.reset_stream()

func update(delta: float, focus: Vector3, available: bool, pursue: bool = true) -> void:
	var measured_begin:=Time.get_ticks_usec() if profiling_enabled else 0
	if profiling_enabled:update_phase_us.clear()
	if is_instance_valid(corpse_host):corpse_host.update(delta,focus,available)
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
		if not zombie.alive and is_instance_valid(corpse_host):
			if corpse_host.retain(zombie):_retire(index,true);continue
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
	if profiling_enabled:update_phase_us["residency"]=Time.get_ticks_usec()-measured_begin
	_update_navigation(delta,available and pursue)
	if profiling_enabled:measured_begin=Time.get_ticks_usec()
	if navigation_interest.is_valid() and (population == null or not population.busy()):navigation_interest.call(navigator.interest_points() if available and pursue else PackedVector3Array())
	_update_spacing()
	if profiling_enabled:update_phase_us["interest_spacing"]=Time.get_ticks_usec()-measured_begin
	if not available or not pursue:
		return
	if profiling_enabled:measured_begin=Time.get_ticks_usec()
	if population != null and population_enabled:population.advance(focus, false)
	if profiling_enabled:update_phase_us["population"]=Time.get_ticks_usec()-measured_begin

func invalidate_navigation(bounds: AABB=AABB()) -> void:
	if navigator!=null:navigator.invalidate(bounds)
	if is_instance_valid(corpse_host):
		for zombie:Node3D in corpse_host.active.values():
			if is_instance_valid(zombie) and zombie.anatomy!=null:zombie.anatomy.wake_ragdolls(bounds)
	for zombie in residents:
		if is_instance_valid(zombie) and zombie.anatomy!=null:zombie.anatomy.wake_ragdolls(bounds)
	_obstacle_clock.clear()

func _update_navigation(delta: float, available: bool) -> void:
	var measured_begin:=Time.get_ticks_usec() if profiling_enabled else 0
	navigator.set_water_depth(water_depth)
	var noise_speed:=0.0
	if _last_player_position.is_finite() and delta>0:
		var step:Vector3=target.global_position-_last_player_position;step.y=0
		if step.length()<2.0:noise_speed=step.length()/delta
	_last_player_position=target.global_position
	var excluded: Array[RID]=[]
	if target.get_parent() is PhysicsBody3D:excluded.append(target.get_parent().get_rid())
	# Refresh only when the recipient body changes: assignment invalidates routes.
	if excluded!=_navigation_exclusions:
		navigator.set_exclusions(excluded);_navigation_exclusions=excluded
	var sight_budget:=2
	for zombie in residents:
		var id:int=zombie.get_instance_id()
		var active:bool=available and zombie.alive and zombie.process_mode!=Node.PROCESS_MODE_DISABLED
		var intent:Dictionary
		if force_pursuit:
			intent={"state":"chase","goal":target.global_position,"moving":true,"combat":true}
		else:
			if active:
				_sense_clock[id]=float(_sense_clock.get(id,0.0))-delta
				if float(_sense_clock[id])<=0 and sight_budget>0:
					sight_budget-=1;_sense_clock[id]=0.15
					var seen:bool=awareness.wants_sight(id,zombie.global_position,zombie.global_basis.z,target.global_position)
					if seen:
						var eye:Vector3=zombie.global_position+Vector3.UP*(0.45 if zombie._crawling else 1.35)
						var player_eye:Vector3=target.global_position+Vector3.UP*1.1
						var sight_bounds:=AABB(eye,Vector3.ZERO).expand(player_eye).grow(0.1)
						seen=readiness.is_valid() and bool(readiness.call(sight_bounds)) and get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye,player_eye,7,excluded)).is_empty()
					awareness.observe(id,target.global_position,seen)
					if not seen and noise_speed>1.0:awareness.hear(id,zombie.global_position,target.global_position,12.0 if noise_speed>7.0 else 7.0)
			intent=awareness.advance(id,zombie.global_position,minf(delta,0.1),active,navigator.state(id))
			if intent.is_empty():continue
			if active and intent.state in ["wander","search"] and _roam_revision.get(id,-1)!=intent.revision:
				_roam_revision[id]=intent.revision
				awareness.accept_roam(id,supported_point(intent.goal))
				intent=awareness.status(id)
		awareness_status[id]=intent
		zombie.awareness_state=intent.state
		zombie.behavior_goal=intent.goal if intent.moving else Vector3.INF
		var may_break_door:bool=intent.state in ["chase","investigate"]
		_obstacle_clock[id]=float(_obstacle_clock.get(id,0.0))-(delta if active else 0.0)
		var obstacle:Node3D=_obstacles.get(id)
		if is_instance_valid(obstacle) and (not active or not may_break_door or not obstacle.available()):
			obstacle.queue_free();_obstacles.erase(id);obstacle=null
		if active and may_break_door and not zombie._crawling and not is_instance_valid(obstacle) and float(_obstacle_clock[id])<=0 and obstacle_provider.is_valid():
			_obstacle_clock[id]=0.5
			obstacle=obstacle_provider.call(zombie)
			if obstacle!=null:_obstacles[id]=obstacle
		zombie.set_behavior_target(obstacle if is_instance_valid(obstacle) else (target if intent.combat else null))
		zombie.navigation_attack_clear=false
		if active and is_instance_valid(zombie.target) and zombie.global_position.distance_to(zombie.target.global_position)<1.6:
			var start:Vector3=zombie.global_position+Vector3.UP*1.1
			var end:Vector3=zombie.target.global_position+Vector3.UP*1.1
			var hit:Dictionary=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,end,7,excluded))
			zombie.navigation_attack_clear=(hit.is_empty() or (is_instance_valid(obstacle) and hit.get("collider")==obstacle.surface)) and absf(zombie.target.global_position.y-zombie.global_position.y)<=0.5
		var goal:Vector3=obstacle.approach_point if is_instance_valid(obstacle) else intent.goal
		var combat_target:=is_instance_valid(zombie.target)
		var distance:Vector3=(zombie.target.global_position if combat_target else goal)-zombie.global_position;distance.y=0
		var needs_route:bool=active and intent.moving and zombie._active_action.is_empty() and zombie._hit_timer<=0 and (distance.length()>(1.0 if combat_target else 0.6) or (combat_target and not zombie.navigation_attack_clear))
		navigator.set_agent(id,zombie.global_position,goal,1 if zombie._crawling else 0,needs_route)
	if profiling_enabled:
		update_phase_us["intent"]=Time.get_ticks_usec()-measured_begin
		measured_begin=Time.get_ticks_usec()
	navigation_status=navigator.advance(delta,readiness,Callable())
	if profiling_enabled:
		update_phase_us["planning"]=Time.get_ticks_usec()-measured_begin
		measured_begin=Time.get_ticks_usec()
	navigation_status["perception_probes"]=2-sight_budget
	navigation_status["perception_probe_limit"]=2
	for zombie in residents:
		var id:int=zombie.get_instance_id()
		zombie.navigation_target=navigator.steering_target(id)
		# Within melee range the source controller may approach its contact
		# distance, but each actual step still passes the shared native guard.
		if is_instance_valid(zombie.target):
			var offset:Vector3=zombie.target.global_position-zombie.global_position;offset.y=0
			if zombie.navigation_attack_clear and offset.length()<=1.0:
				zombie.navigation_target=zombie.target.global_position
	if profiling_enabled:update_phase_us["steering"]=Time.get_ticks_usec()-measured_begin

func _update_spacing() -> void:
	# At most six actors: 30 ordered neighbour checks, with no world scan.
	for index in residents.size():
		var zombie = residents[index]
		zombie.crowd_steering = Vector3.ZERO
		if not zombie.alive:
			continue
		var destination:Vector3=zombie.target.global_position if is_instance_valid(zombie.target) else zombie.behavior_goal
		if not destination.is_finite():continue
		var approach: Vector3 = destination - zombie.global_position
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
	if node is RigidBody3D and node.freeze!=frozen:
		node.freeze = frozen
	for child in node.get_children():
		_freeze_detached(child, frozen)

func _retire(index: int,keep_corpse:bool=false) -> void:
	var zombie = residents[index]
	if population != null:population.sync(zombie)
	_corpse_age.erase(zombie.get_instance_id())
	var id:int=zombie.get_instance_id()
	awareness.remove_agent(id);awareness_status.erase(id);_sense_clock.erase(id);_roam_revision.erase(id)
	navigator.remove_agent(id);_obstacle_clock.erase(id)
	if _obstacles.has(id):
		if is_instance_valid(_obstacles[id]):_obstacles[id].queue_free()
		_obstacles.erase(id)
	residents.remove_at(index)
	if not keep_corpse:zombie.queue_free()

func supported_point(around: Vector3) -> Vector3:
	if not around.is_finite() or not readiness.is_valid():
		return Vector3.INF
	var bounds := AABB(around - Vector3(0.6, 4, 0.6), Vector3(1.2, 9, 1.2))
	if not readiness.call(bounds):
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(around + Vector3.UP * 4, around - Vector3.UP * 4, 1)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.85:
		return Vector3.INF
	var point: Vector3 = hit.position + Vector3.UP * 0.06
	if water_depth.is_valid() and float(water_depth.call(point + Vector3.UP * 0.5)) > 0.0:
		return Vector3.INF
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.9)
	query.collision_mask = 1 | 2 | 4 | 8 | CHARACTER_LAYER | RAGDOLL_LAYER
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
	zombie.geometry_template=geometry_template
	zombie.position = to_local(supported)
	zombie.target = target if force_pursuit else null
	zombie.behavior_enabled = true
	zombie.navigator=navigator
	zombie.navigation_motor=ClassDB.instantiate("NativePlayerMovement")
	zombie.navigation_motor.set_step_radius(.24)
	var excluded: Array[RID]=[]
	if target.get_parent() is PhysicsBody3D:excluded.append(target.get_parent().get_rid())
	if excluded!=_navigation_exclusions:
		navigator.set_exclusions(excluded);_navigation_exclusions=excluded
	add_child(zombie)
	if not zombie.initialized:
		zombie.queue_free();return null
	geometry_template=zombie.anatomy
	residents.append(zombie)
	if is_instance_valid(corpse_host):zombie.died.connect(func():corpse_host.retain(zombie))
	var id:int=zombie.get_instance_id()
	awareness.add_agent(id,zombie.global_position)
	_sense_clock[id]=float(residents.size()%3)*0.08
	zombie.tree_exiting.connect(func():
		if is_instance_valid(navigator):navigator.remove_agent(id)
		if is_instance_valid(awareness):awareness.remove_agent(id))
	return zombie

func pick(start: Vector3, end: Vector3, exclude: Array) -> Dictionary:
	var bodies:Array=residents.duplicate()
	if is_instance_valid(corpse_host):
		for zombie:Node3D in corpse_host.active.values():
			if zombie not in bodies:bodies.append(zombie)
	if bodies.is_empty():
		return {}
	# World collision occludes the evaluated skinned surface, not a broad movement
	# capsule or a convex hull fitted to an earlier animation pose.
	var omitted: Array[RID] = []
	omitted.assign(exclude)
	for resident in bodies:
		if is_instance_valid(resident):
			omitted.append(resident.get_rid())
			for body:PhysicalBone3D in resident.physical_bones.values():omitted.append(body.get_rid())
	var solid:Dictionary=world_geometry.raycast_scene(start,end,15|RAGDOLL_LAYER,omitted) if is_instance_valid(world_geometry) else get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start,end,15|RAGDOLL_LAYER,omitted))
	var stop:Vector3=solid.position if not solid.is_empty() else end
	var nearest:Dictionary={};var distance:=start.distance_squared_to(stop)
	for resident in bodies:
		if not is_instance_valid(resident) or resident.anatomy==null:continue
		var hit:Dictionary=resident.anatomy.pick(start,stop)
		if hit.is_empty() or start.distance_squared_to(hit.position)>distance:continue
		distance=start.distance_squared_to(hit.position);nearest=hit
		nearest.merge({"kind":"zombie","zombie":resident,"material":"other","name":"Zombie"})
	return nearest

func apply_hit(hit: Dictionary, damage: float, direction: Vector3, impact: String = "melee") -> bool:
	var zombie: Object = hit.get("zombie")
	if not enabled or not is_instance_valid(zombie) or (not zombie in residents and (not is_instance_valid(corpse_host) or not zombie in corpse_host.active.values())) or zombie.process_mode == Node.PROCESS_MODE_DISABLED or not is_finite(damage) or damage<=0 or damage>1000000 or not direction.is_finite():
		return false
	var part:String=hit.get("part","")
	if impact not in ["unarmed","melee","cutting","heavy","firearm"]:return false
	if not zombie.PARTS.has(part) or zombie.missing.get(part,true) or not hit.get("position",Vector3.INF).is_finite():return false
	zombie.receive_hit(hit.get("part", "torso"), damage, hit.position, direction * 2.0, false, impact)
	if zombie.alive:awareness.provoke(zombie.get_instance_id(),target.global_position)
	return true
