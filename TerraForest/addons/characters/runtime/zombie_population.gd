extends RefCounted

const RADIUS := 88.0
var game: Node
var host: Node3D
var store: RefCounted
var last_focus := Vector3.INF
var queue: Array = []
var sampling: Array = []
var sampled := false
var token := -320000
var waiting := false
var cursor := 0
var examined := 0
var admitted := 0
var began := 0
var failure := ""
var initial_complete := false

func prepare(owner_game: Node, owner_host: Node3D, persistence: RefCounted) -> bool:
	game = owner_game; host = owner_host
	store = ClassDB.instantiate("NativeZombiePopulation")
	game.terrain.surface_batch_ready.connect(_surface_ready)
	return persistence.register_component("zombie_population_v1", capture, restore, store, PackedByteArray())

func reset_stream() -> void:
	token -= 1; waiting = false; sampled = false
	queue.clear(); sampling.clear(); cursor = 0; examined = 0; admitted = 0
	last_focus = Vector3.INF; initial_complete = false; failure = ""

func sync(zombie: Node3D) -> void:
	var identity: int = zombie.get_meta("world_zombie_id", 0)
	if identity == 0 or store.resident(identity).get("state", 2) >= 2:return
	if not store.update_resident(identity, zombie.global_position, zombie.global_rotation.y, zombie.anatomy.capture_vitals(),host.capture_sleep(zombie)):
		failure = "Cannot save world zombie %d" % identity
		push_error(failure)
	else:game.terrain.changed_since_save = true

func capture() -> PackedByteArray:
	for zombie in host.residents:
		if is_instance_valid(zombie):sync(zombie)
	if not failure.is_empty():return PackedByteArray([255])
	return store.capture_snapshot()

func restore(bytes: PackedByteArray) -> bool:
	if not store.validate_snapshot(bytes):return false
	host.clear(); reset_stream()
	return store.restore_snapshot(bytes)

func status() -> Dictionary:
	return {"world":store.statistics(), "active":host.residents.size(), "sample_pending":waiting, "candidates":queue.size(), "examined":examined, "admitted":admitted, "ready":initial_complete, "failure":failure}

func busy() -> bool:
	return host.population_enabled and last_focus.is_finite() and (not sampled or cursor < queue.size())

func advance(focus: Vector3, during_loading: bool) -> bool:
	if not host.enabled or not host.population_enabled:return true
	if not failure.is_empty():
		game.terrain.latest_error = failure
		return false
	if not store.initialize(game.terrain.backend.world_seed, game._initial_generation_spawn):
		failure = "Zombie population does not match this world seed"
		return false
	if not last_focus.is_finite() or focus.distance_to(last_focus) >= 16.0:
		for zombie in host.residents:
			if is_instance_valid(zombie):sync(zombie)
		token -= 1; waiting = false; sampled = false
		initial_complete = false
		last_focus = focus; queue = store.nearby(focus, RADIUS)
		queue=queue.filter(func(record:Dictionary):return record.anchor!=0)+queue.filter(func(record:Dictionary):return record.anchor==0)
		cursor = 0; examined = 0; admitted = 0; began = Time.get_ticks_msec()
		game.terrain.changed_since_save = true
	if not sampled:
		if waiting:return false
		sampling = queue.duplicate(true)
		var points := PackedVector3Array()
		for record: Dictionary in sampling:points.append(record.position)
		if points.is_empty():sampled = true
		elif game.terrain.request_surface_batch(points, token):waiting = true
		return false
	if cursor >= queue.size():
		cursor = queue.size()
		initial_complete = true
		return true
	var record: Dictionary = queue[cursor]
	var point: Vector3 = record.position
	for zombie in host.residents:
		if is_instance_valid(zombie) and zombie.get_meta("world_zombie_id", 0) == record.id:
			cursor += 1; examined += 1
			return false
	if record.state >= 2 or not point.is_finite():
		cursor += 1; examined += 1
		return false
	if point.distance_to(focus) > 94.0:
		cursor += 1; examined += 1
		return false
	var offset := point - focus; offset.y = 0
	var authored:bool=record.anchor!=0
	if not during_loading and (offset.length() < (8.0 if authored else 40.0) or (host.spawn_visible.is_valid() and host.spawn_visible.call(point + Vector3.UP) and (not authored or not _occluded(point)))):
		cursor += 1; examined += 1
		return false
	if host.residents.size()>=host.LIMIT:
		var replacement:=-1
		var farthest:=40.0
		if authored:
			for index in host.residents.size():
				var resident:Node3D=host.residents[index]
				var saved:Dictionary=store.resident(resident.get_meta("world_zombie_id",0))
				if not resident.alive or saved.get("anchor",0)!=0 or host.awareness.status(resident.get_instance_id()).state not in ["idle","wander"]:continue
				var distance:=resident.global_position.distance_to(focus)
				if distance>farthest and host.spawn_visible.is_valid() and not host.spawn_visible.call(resident.global_position+Vector3.UP):replacement=index;farthest=distance
		if replacement<0:cursor+=1;examined+=1;return false
		host._retire(replacement)
	var interest := PackedVector3Array([point])
	for zombie in host.residents:
		if is_instance_valid(zombie):interest.append(zombie.global_position)
	if host.navigation_interest.is_valid():host.navigation_interest.call(interest)
	if not host.readiness.call(AABB(point - Vector3(1, 4, 1), Vector3(2, 9, 2))):
		if Time.get_ticks_msec() - began < 12000:return false
		if not during_loading:
			cursor += 1; examined += 1
			return false
		failure = "Zombie residency timed out waiting for terrain/object collision"
		return false
	cursor += 1; examined += 1
	var zombie: CharacterBody3D = host.spawn_at(point,not record.sleep.is_empty(),authored)
	if zombie == null:return false
	zombie.global_rotation.y = record.yaw
	if not host.configure_encounter(zombie,store.encounter(record.id)):
		failure = "Cannot configure zombie encounter %d" % record.id
		host._retire(host.residents.find(zombie))
		return false
	if not record.vitals.is_empty() and not zombie.restore_population_vitals(record.vitals):
		failure = "Invalid saved zombie health for resident %d" % record.id
		host._retire(host.residents.find(zombie))
		return false
	if not host.restore_sleep(zombie,record.sleep):
		host._retire(host.residents.find(zombie))
		return false
	zombie.set_meta("world_zombie_id", record.id)
	zombie.died.connect(func():sync(zombie);last_focus=Vector3.INF)
	zombie.process_mode = Node.PROCESS_MODE_DISABLED if during_loading else Node.PROCESS_MODE_INHERIT
	zombie.set_behavior(not during_loading)
	sync(zombie); admitted += 1
	return false

func _occluded(point:Vector3)->bool:
	var camera:Camera3D=game.get_viewport().get_camera_3d()
	if camera==null:return false
	var eye:Vector3=camera.global_position
	var query:=PhysicsRayQueryParameters3D.new();query.from=eye;query.collision_mask=1|2|4;query.exclude=[game.player.get_rid()]
	for height in [.15,.9,1.8]:
		for side in [-1.,0.,1.]:
			for depth in [-1.,0.,1.]:
				query.to=point+Vector3(side*1.5,height,depth*1.5)
				if game.get_world_3d().direct_space_state.intersect_ray(query).is_empty():return false
	return true

func _surface_ready(received_token: int, points: PackedVector3Array, normals: PackedVector3Array, epoch: int, revision: int) -> void:
	if not waiting or received_token != token:return
	waiting = false
	if epoch != game.terrain.epoch or revision != game.terrain.published_revision:return
	if points.size() != sampling.size() or normals.size() != sampling.size():
		failure = "Zombie terrain sampling failed"
		return
	for index in sampling.size():
		var record: Dictionary = sampling[index]
		if record.state != 0:continue
		if not points[index].is_finite() or normals[index].y < 0.85 or (host.water_depth.is_valid() and host.water_depth.call(points[index] + Vector3.UP * 0.5) > 0.0):
			store.exclude(record.id); record.state = 3
		else:record.position = points[index]
	queue = sampling; sampled = true
