# SPDX-License-Identifier: 0BSD
extends Node3D
## Bounded scene residency for persistent, seeded world inhabitants.
const Zombie = preload("res://addons/characters/runtime/zombie.gd")
const CHARACTER_LAYER := 1 << 16
const RAGDOLL_LAYER := 1 << 18
const LIMIT := 6
const ENCOUNTER_LIMIT := 16
var residency_limit := LIMIT
const RETIRE_RADIUS := 96.0
var population: RefCounted
var population_enabled := true
var enabled := false
var target: Node3D
var readiness: Callable
var water_depth: Callable
var water_footprint: Callable
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
var _sense_cursor:=0
var _alarm_clock:Dictionary={}
var _roam_revision:Dictionary={}
var navigator: Node3D
var navigation_status: Dictionary={}
var _obstacles: Dictionary={}
var _obstacle_clock: Dictionary={}
var _navigation_exclusions: Array[RID]=[]
var residents: Array = []
var _corpse_age: Dictionary = {}
var _capsule: CapsuleShape3D
var _resident_capsule: CapsuleShape3D
var geometry_template:RefCounted
var profiling_enabled:=false
var _navigation_profiling:=false
var update_phase_us:Dictionary={}
var _response_trace_left:=0.
var _response_trace_clock:=0.
var _response_trace_rows:Array=[]
var response_context:Dictionary={}
var trace_responses:=false
var response_trace_path:="user://diagnostics/zombie_response.json"
@export_file("*.json") var encounter_profiles_path:="res://addons/characters/runtime/assets/zombie.encounters.json"
var encounter_profiles:Dictionary={}

func prepare(owner_game: Node, persistence: RefCounted) -> bool:
	population = preload("res://addons/characters/runtime/zombie_population.gd").new()
	return population.prepare(owner_game, self, persistence)

func _ready() -> void:
	var catalog:Variant=JSON.parse_string(FileAccess.get_file_as_string(encounter_profiles_path))
	if catalog is Dictionary and catalog.get("version")==1 and catalog.get("profiles") is Dictionary:
		encounter_profiles=catalog.profiles
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.32
	_capsule.height = 1.8
	_resident_capsule=CapsuleShape3D.new();_resident_capsule.radius=.24;_resident_capsule.height=1.74
	navigator=ClassDB.instantiate("NativeActorNavigator")
	add_child(navigator)
	if not navigator.configure(ENCOUNTER_LIMIT):push_error("Zombie navigation initialization failed")
	awareness=ClassDB.instantiate("NativeZombieAwareness")
	if not awareness.configure(ENCOUNTER_LIMIT,randi()):push_error("Zombie awareness initialization failed")

func retire_location(identities: PackedInt64Array) -> void:
	for index in range(residents.size()-1,-1,-1):
		if is_instance_valid(residents[index]) and identities.has(int(residents[index].get_meta("world_zombie_id",0))):_retire(index)
	population.reset_stream()

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
	_sense_clock.clear();_roam_revision.clear();awareness_status.clear();_alarm_clock.clear();_sense_cursor=0
	if awareness!=null:awareness.clear()
	if navigator!=null:navigator.clear()
	if navigation_interest.is_valid():navigation_interest.call(PackedVector3Array())
	_corpse_age.clear()
	_response_trace_left=0.;_response_trace_rows.clear()
	if population != null:population.reset_stream()

func update(delta: float, focus: Vector3, available: bool, pursue: bool = true) -> void:
	var measured_begin:=Time.get_ticks_usec() if profiling_enabled else 0
	if profiling_enabled:update_phase_us.clear()
	if is_instance_valid(corpse_host):corpse_host.update(delta,focus,available)
	if not enabled or not is_instance_valid(target):
		if not residents.is_empty():
			clear()
		return
	_groan_wait = maxf(0.0, _groan_wait - delta)
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
		if zombie.sleeper_active():bounds=bounds.merge(zombie.global_transform*zombie.sleeper.coverage)
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
		if ready and available and zombie.alive:_groan(id,zombie,delta,focus)
		if not ready and not zombie.alive:
			_retire(index)
	if profiling_enabled:update_phase_us["residency"]=Time.get_ticks_usec()-measured_begin
	_update_navigation(delta,available and pursue)
	if _response_trace_left>0:
		_response_trace_left=maxf(0.,_response_trace_left-delta);_response_trace_clock-=delta
		if _response_trace_clock<=0:
			_response_trace_clock=1.
			_record_response_trace(available and pursue)
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
	if _navigation_profiling!=profiling_enabled:
		_navigation_profiling=profiling_enabled;navigator.set_query_profiling(profiling_enabled)
	var measured_begin:=Time.get_ticks_usec() if profiling_enabled else 0
	navigator.set_water_depth(water_depth,water_footprint)
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
	# Fair bounded service: a low update rate or a crowded station must not let
	# the first residents consume every probe forever.
	var probes:Dictionary={}
	for zombie:CharacterBody3D in residents:
		if available and zombie.alive and zombie.process_mode!=Node.PROCESS_MODE_DISABLED:
			var id:int=zombie.get_instance_id();_sense_clock[id]=float(_sense_clock.get(id,0.0))-delta
	var count:=residents.size()
	for offset in count:
		var index:=(_sense_cursor+offset)%count
		var zombie:CharacterBody3D=residents[index];var id:int=zombie.get_instance_id()
		if not available or not zombie.alive or zombie.process_mode==Node.PROCESS_MODE_DISABLED or float(_sense_clock.get(id,0.0))>0:continue
		probes[id]=true;_sense_clock[id]=.1
		if probes.size()==2:_sense_cursor=(index+1)%count;break
	var sight_budget:=2
	for zombie in residents:
		var id:int=zombie.get_instance_id()
		var active:bool=available and zombie.alive and zombie.process_mode!=Node.PROCESS_MODE_DISABLED
		var intent:Dictionary
		if force_pursuit and not zombie.sleeper_active():
			intent={"state":"chase","goal":target.global_position,"moving":true,"combat":true}
		else:
			if active:
				if probes.has(id):
					sight_budget-=1
					var seen:bool=awareness.wants_sight(id,zombie.global_position,zombie.global_basis.z,target.global_position)
					if seen:
						var eye:Vector3=zombie.global_position+Vector3.UP*(0.45 if zombie._crawling else 1.35)
						if zombie.sleeper_active():
							var head:AABB=zombie.anatomy.sample_bounds("head",zombie.global_transform)
							eye=head.get_center()
						var player_eye:Vector3=target.global_position+Vector3.UP*1.1
						var sight_bounds:=AABB(eye,Vector3.ZERO).expand(player_eye).grow(0.1)
						seen=readiness.is_valid() and bool(readiness.call(sight_bounds)) and get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye,player_eye,7,excluded)).is_empty()
					awareness.observe(id,target.global_position,seen,zombie.global_position.distance_to(target.global_position))
					if not seen and noise_speed>1.0:awareness.hear(id,zombie.global_position,target.global_position,12.0 if noise_speed>6.0 else 8.0 if noise_speed>3.0 else 3.0)
			intent=awareness.advance(id,zombie.global_position,minf(delta,0.1),active,navigator.state(id))
			if intent.is_empty():continue
			if active and intent.state in ["wander","search","reposition"] and _roam_revision.get(id,-1)!=intent.revision:
				# A tactical recovery is a new destination/action, not another
				# observation of a moving target. Release the abandoned query once.
				if intent.state=="reposition":navigator.remove_agent(id)
				_roam_revision[id]=intent.revision
				var destination:=supported_roam_point(intent.goal,not zombie._crawling)
				if not destination.is_finite():
					# A quiet room may be smaller than a surface roaming radius. Try
					# bounded shorter goals before abandoning the current clue.
					var offset:Vector3=intent.goal-zombie.global_position
					for fraction:float in [.5,.25]:
						destination=supported_roam_point(zombie.global_position+offset*fraction,not zombie._crawling)
						if destination.is_finite():break
				awareness.accept_roam(id,destination)
				intent=awareness.status(id)
		if active and zombie.sleeper_active() and intent.state=="sleeping" and zombie.sleeper.phase!="sleeping":
			awareness.provoke(id,zombie.global_position);intent=awareness.status(id)
		if active and zombie.sleeper_active() and intent.state=="waking":
			zombie.sleeper.wake_speed=float(intent.wake_speed)
			zombie.sleeper.wake()
			if zombie.sleeper.phase=="ready" and intent.wake_ready and awareness.finish_waking(id):
				zombie.sleeper.finish();intent=awareness.status(id)
		_alarm_clock[id]=maxf(0.,float(_alarm_clock.get(id,0.))-(delta if active else 0.))
		if active and intent.state=="chase" and bool(intent.get("visible",false)) and awareness_status.get(id,{}).get("state","")!="chase" and float(_alarm_clock[id])<=0:
			_alarm_clock[id]=4.
			# Only an actual sighting broadcasts a local clue; listeners cannot
			# propagate an alarm by hearing it, or reveal a hidden player's motion.
			for peer:CharacterBody3D in residents:
				if peer!=zombie and peer.alive and peer.process_mode!=Node.PROCESS_MODE_DISABLED:awareness.hear(peer.get_instance_id(),peer.global_position,zombie.global_position,8.)
		awareness_status[id]=intent
		if intent.has("chase_speed_multiplier"):zombie.chase_speed_multiplier=float(intent.chase_speed_multiplier)
		zombie.awareness_state=intent.state
		zombie.behavior_goal=intent.goal if intent.moving else Vector3.INF
		var may_break_door:bool=intent.state in ["chase","investigate","reposition"]
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
		# Movement/attack animation owns whether the body can move this tick.
		# Keep its planner alive through brief hit/action pauses, ready to resume.
		var needs_route:bool=active and intent.moving and (distance.length()>(1.0 if combat_target else 0.6) or (combat_target and not zombie.navigation_attack_clear))
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

## Idle groan for nearby living actors. Each zombie re-rolls every few seconds,
## and a shared clock keeps the group from groaning over each other.
const GROAN_RANGE := 22.0
const GROAN_FIRST := 1.5
const GROAN_MIN := 5.0
const GROAN_MAX := 11.0
## Minimum gap between any two groans across the whole group.
const GROAN_GROUP_GAP := 3.0
var _groan_clock: Dictionary = {}
var _groan_serial := 0
var _groan_wait := 0.0

func _groan(id: int, zombie: Node3D, delta: float, focus: Vector3) -> void:
	# Only eligible actors count down, so a far zombie never burns its turn.
	var at: Vector3 = zombie.global_position
	if not at.is_finite() or at.distance_to(focus) > GROAN_RANGE: return
	var left := float(_groan_clock.get(id, _groan_first())) - delta
	if left > 0.0:
		_groan_clock[id] = left
		return
	# A pending group gap holds this zombie ready instead of spending its turn.
	if _groan_wait > 0.0:
		_groan_clock[id] = 0.0
		return
	_groan_clock[id] = randf_range(GROAN_MIN, GROAN_MAX)
	var host: Node = get_parent()
	var adapter: Node = host.get_node_or_null("WorldAudio") if host != null else null
	if adapter == null or not adapter.has_method("play_event"): return
	adapter.play_event("zombie.vocal.idle", at + Vector3.UP * 1.5, false)
	_groan_wait = GROAN_GROUP_GAP

func _groan_first() -> float:
	_groan_serial += 1
	return GROAN_FIRST + _groan_serial % 3 * 1.0

## A hit interrupts the idle groan: stop the one already playing and hold this
## zombie back so it does not immediately pick up again mid-fight.
const GROAN_AFTER_HIT := 14.0

func _hush_groan(id: int) -> void:
	_groan_clock[id] = GROAN_AFTER_HIT
	var host: Node = get_parent()
	var adapter: Node = host.get_node_or_null("WorldAudio") if host != null else null
	if adapter == null or not adapter.has_method("stop_sound"): return
	adapter.stop_sound("zombie.vocal.idle")

## Flesh impact for melee, cutting and heavy hits. Gunfire already plays its own
## flesh impact, so only non-firearm hits come here. Played at the listener:
## the attacker is the one swinging, so the level must not depend on reach.
## The assigned recording is chosen in the audition selection; Critical Hit 3 is
## rejected for flesh, so this stays silent until a usable clip is approved.
const FLESH_REPEAT_MS := 70
var _flesh_ms := -1000000

func _flesh_hit(point: Vector3, impact: String) -> void:
	if impact == "firearm" or not point.is_finite(): return
	var now := Time.get_ticks_msec()
	if now - _flesh_ms < FLESH_REPEAT_MS: return
	_flesh_ms = now
	var host: Node = get_parent()
	var adapter: Node = host.get_node_or_null("WorldAudio") if host != null else null
	if adapter == null or not adapter.has_method("play_event"): return
	adapter.play_event("flesh.hit", point, true)

func _update_spacing() -> void:
	# Six ordinary actors or sixteen authored encounter actors; no world scan.
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
	awareness.remove_agent(id);awareness_status.erase(id);_sense_clock.erase(id);_roam_revision.erase(id);_alarm_clock.erase(id);_groan_clock.erase(id)
	navigator.remove_agent(id);_obstacle_clock.erase(id)
	if _obstacles.has(id):
		if is_instance_valid(_obstacles[id]):_obstacles[id].queue_free()
		_obstacles.erase(id)
	residents.remove_at(index)
	if population!=null and zombie.get_meta("world_zombie_id",0)>0:population.last_focus=Vector3.INF
	if not keep_corpse:zombie.queue_free()

func supported_point(around: Vector3,standing:bool=true) -> Vector3:
	# Ordinary world admission still selects terrain from the original broad probe.
	return _supported_point(around,standing,4.0,1,.85)

func supported_roam_point(around:Vector3,standing:bool=true)->Vector3:
	# Stay below a room's ceiling and recognize its actual walking floor. The
	# native route still proves reachability, support and permitted step/slope limits.
	return _supported_point(around,standing,.3,7,.7072 if standing else .85)

func _supported_point(around:Vector3,standing:bool,probe_height:float,support_mask:int,minimum_normal:float)->Vector3:
	if not around.is_finite() or not readiness.is_valid():
		return Vector3.INF
	var bounds := AABB(around - Vector3(0.6, 4, 0.6), Vector3(1.2, 4+maxf(2.,probe_height+1.), 1.2))
	if not readiness.call(bounds):
		return Vector3.INF
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(around + Vector3.UP * probe_height, around - Vector3.UP * 4, support_mask)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < minimum_normal:
		return Vector3.INF
	var point: Vector3 = hit.position + Vector3.UP * 0.06
	if water_depth.is_valid() and float(water_depth.call(point + Vector3.UP * 0.5)) > 0.0:
		return Vector3.INF
	if not standing:return point
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _capsule
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.9)
	query.collision_mask = 1 | 2 | 4 | 8 | CHARACTER_LAYER | RAGDOLL_LAYER
	if not space.intersect_shape(query, 1).is_empty():
		return Vector3.INF
	return point

func supported_resident_point(point:Vector3,standing:bool)->Vector3:
	if not point.is_finite() or not readiness.is_valid() or not readiness.call(AABB(point-Vector3(2.5,.5,2.5),Vector3(5,5,5))):return Vector3.INF
	var space:=get_world_3d().direct_space_state
	var hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.08,point-Vector3.UP*.18,1|2|4))
	if hit.is_empty() or hit.normal.y<.85:return Vector3.INF
	if water_depth.is_valid() and float(water_depth.call(point+Vector3.UP*.5))>0:return Vector3.INF
	if standing:
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=_resident_capsule;query.transform=Transform3D(Basis.IDENTITY,point+Vector3.UP*(_resident_capsule.height*.5))
		query.collision_mask=1|2|4|8|CHARACTER_LAYER|RAGDOLL_LAYER
		if not space.intersect_shape(query,1).is_empty():return Vector3.INF
	return point

func spawn_at(point: Vector3,restoring_sleep:bool=false,authored:bool=false) -> CharacterBody3D:
	if not enabled or not point.is_finite() or residents.size() >= residency_limit or not is_instance_valid(target):
		return null
	var measured_begin:=Time.get_ticks_usec() if profiling_enabled else 0
	var supported := supported_resident_point(point,not restoring_sleep) if restoring_sleep or authored else supported_point(point)
	if profiling_enabled:update_phase_us["admission support"]=Time.get_ticks_usec()-measured_begin;measured_begin=Time.get_ticks_usec()
	if not supported.is_finite():
		return null
	var zombie := Zombie.new()
	if profiling_enabled:update_phase_us["admission instance"]=Time.get_ticks_usec()-measured_begin;measured_begin=Time.get_ticks_usec()
	zombie.geometry_template=geometry_template
	zombie.position = to_local(point if restoring_sleep else supported)
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
	if profiling_enabled:update_phase_us["admission attach"]=Time.get_ticks_usec()-measured_begin;measured_begin=Time.get_ticks_usec()
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
	zombie.damaged.connect(func(_part:String,_health:float):
		if zombie.alive and is_instance_valid(target):
			awareness.provoke(id,target.global_position)
			if trace_responses:
				_response_trace_left=6.;_response_trace_clock=0.;_response_trace_rows.clear())
	return zombie

func _record_response_trace(available:bool)->void:
	# One bounded local receipt after a real hit makes a further standing report
	# diagnosable in its actual saved geometry. Never touch a world/save file.
	var actors:Array=[]
	for actor:CharacterBody3D in residents:
		actors.append({"identity":actor.get_meta("world_zombie_id",0),"position":actor.global_position,"velocity":actor.velocity,"state":actor.state,"behavior":actor.behavior_enabled,"process":actor.process_mode,"action":actor._active_action,"hit_seconds":actor._hit_timer,"intent":awareness.status(actor.get_instance_id()),"route":navigator.status(actor.get_instance_id())})
	_response_trace_rows.append({"player":target.global_position,"available":available,"context":response_context.duplicate(),"actors":actors})
	if _response_trace_rows.size()>7:_response_trace_rows.pop_front()
	DirAccess.make_dir_recursive_absolute(response_trace_path.get_base_dir())
	var file:=FileAccess.open(response_trace_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify({"schema":1,"rows":_response_trace_rows},"  "))

func configure_encounter(zombie:CharacterBody3D,descriptor:Dictionary)->bool:
	if zombie not in residents or not zombie.alive:return false
	var profile_id:String=descriptor.get("profile","")
	var profile:Variant=encounter_profiles.get(profile_id)
	if not profile is Dictionary:return false
	profile=profile.duplicate()
	profile["ambusher"]=bool(descriptor.get("ambusher",false))
	if not awareness.set_profile(zombie.get_instance_id(),profile):return false
	var vitals:PackedByteArray=descriptor.get("initial_vitals",PackedByteArray())
	if not vitals.is_empty() and not zombie.restore_population_vitals(vitals):return false
	var intent:Dictionary=awareness.status(zombie.get_instance_id())
	zombie.walk_speed=float(intent.walk_speed)
	zombie.chase_speed_multiplier=float(intent.chase_speed_multiplier)
	zombie.set_meta("encounter_profile",profile_id)
	if int(descriptor.get("sleep_pose",0))!=0:return put_to_sleep(zombie,int(descriptor.sleep_pose))
	return true

func put_to_sleep(zombie:CharacterBody3D,pose:int)->bool:
	if zombie not in residents or awareness.status(zombie.get_instance_id()).get("state","") not in ["idle","wander"]:return false
	if not zombie.begin_sleep(pose):return false
	return awareness.set_sleeping(zombie.get_instance_id(),pose)

func hear_noise(source:Vector3,radius:float)->int:
	var heard:=0
	for zombie in residents:
		if zombie.alive and zombie.process_mode!=Node.PROCESS_MODE_DISABLED and awareness.hear(zombie.get_instance_id(),zombie.global_position,source,radius):heard+=1
	return heard

func capture_sleep(zombie:CharacterBody3D)->PackedByteArray:
	if not zombie.sleeper_active():return PackedByteArray()
	var id:=zombie.get_instance_id()
	if zombie.sleeper.phase!="sleeping" and awareness.status(id).state=="sleeping":awareness.provoke(id,zombie.global_position)
	var bytes:PackedByteArray=awareness.capture_sleep(id)
	bytes.append_array(zombie.sleeper.capture())
	return bytes

func restore_sleep(zombie:CharacterBody3D,bytes:PackedByteArray)->bool:
	if bytes.is_empty():return true
	if zombie not in residents or awareness.status(zombie.get_instance_id()).get("state","")!="idle":return false
	var validator=ClassDB.instantiate("NativeZombiePosture")
	if not validator.validate_snapshot(bytes) or not zombie.begin_sleep(bytes.decode_u32(0),bytes):return false
	return awareness.restore_sleep(zombie.get_instance_id(),bytes.slice(0,28))

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

func apply_hit(hit: Dictionary, damage: float, direction: Vector3, impact: String = "melee", response: Dictionary = {}) -> bool:
	var zombie: Object = hit.get("zombie")
	if not enabled or not is_instance_valid(zombie) or (not zombie in residents and (not is_instance_valid(corpse_host) or not zombie in corpse_host.active.values())) or zombie.process_mode == Node.PROCESS_MODE_DISABLED or not is_finite(damage) or damage<=0 or damage>1000000 or not direction.is_finite():
		return false
	var part:String=hit.get("part","")
	if impact not in ["unarmed","melee","cutting","heavy","firearm"]:return false
	if not zombie.PARTS.has(part) or zombie.missing.get(part,true) or not hit.get("position",Vector3.INF).is_finite():return false
	zombie.receive_hit(hit.get("part", "torso"), damage, hit.position, direction * 2.0, impact=="firearm" and response.get("force_sever",false), impact, response.get("reaction",true), response.get("animation",true))
	if zombie.alive:awareness.provoke(zombie.get_instance_id(),target.global_position)
	_hush_groan(zombie.get_instance_id())
	_flesh_hit(hit.get("position", zombie.global_position), impact)
	return true
