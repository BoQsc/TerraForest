# SPDX-License-Identifier: 0BSD
# Single local vehicle interaction adapter. Driving physics lives in the native addon.
extends Node
var car: RigidBody3D
var driving:=false
var _obstacle_sync_time:=0.0
var _camera_local: Transform3D
var _player_layer:=0
var _player_mask:=0
var _physics_ticks:=60
var _camera_follow: RefCounted
var storage: RefCounted
var fleet: RefCounted
var car_identity:=0
var activation: RefCounted
var fleet_enabled:=false
var _world: Node
const VEHICLE_SCENE_PATH: String="res://vehicle_demo/scenes/car.tscn"
var _vehicle_scene: PackedScene
var _scene_requested:=false
var profile_install:=false
var install_timings: Dictionary={}
var interaction_available: Callable
var last_spawn_identity:=0
var coasting:Dictionary={}
func can_interact() -> bool:
	return not interaction_available.is_valid() or interaction_available.call()
func request_scene() -> void:
	if _vehicle_scene!=null or _scene_requested: return
	_scene_requested=ResourceLoader.load_threaded_request(VEHICLE_SCENE_PATH,"PackedScene")==OK
func scene_ready() -> bool:
	if _vehicle_scene!=null: return true
	if not _scene_requested: return false
	if ResourceLoader.load_threaded_get_status(VEHICLE_SCENE_PATH)!=ResourceLoader.THREAD_LOAD_LOADED: return false
	_take_requested_scene()
	return _vehicle_scene!=null
func _take_requested_scene() -> void:
	if not _scene_requested: return
	_vehicle_scene=ResourceLoader.load_threaded_get(VEHICLE_SCENE_PATH) as PackedScene
	_scene_requested=false
func prepare(world: Node,persistence: RefCounted) -> bool:
	request_scene()
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	storage=ClassDB.instantiate("NativeVehicleStorage");_world=world
	fleet=ClassDB.instantiate("NativeVehicleFleet")
	fleet_enabled="--vehicle-fleet" in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args()))
	if fleet_enabled:activation=preload("res://addons/vehicle_runtime/fleet_activation.gd").new(self)
	return persistence.register_component("vehicles",capture_snapshot,restore_snapshot,fleet,PackedByteArray())
func capture_snapshot() -> PackedByteArray:
	if fleet_enabled:
		if not activation.sync_records():return PackedByteArray([0])
	elif is_instance_valid(car):
		if car_identity==0:car_identity=fleet.spawn(car.global_transform)
		if car_identity==0 or not fleet.set_pose(car_identity,car.global_transform):return PackedByteArray([0])
	var info: Dictionary=fleet.statistics()
	if info.records==0 and info.next_identity==1:return PackedByteArray()
	return fleet.capture_storage_snapshot()
func restore_snapshot(data: PackedByteArray) -> bool:
	var decoded: Dictionary=storage.decode_fleet(data)
	if not decoded.ok:return false
	if not fleet.restore_storage_snapshot(data):return false
	coasting.clear()
	if driving:
		_world.player.collision_layer=_player_layer;_world.player.collision_mask=_player_mask
		_world.camera.transform=_camera_local;Engine.physics_ticks_per_second=_physics_ticks
		driving=false
	if fleet_enabled:
		activation.reset();car=null;car_identity=0;return true
	# Preserve every parked record while the scene still has one live slot.
	# Multiple-body activation will replace this explicit first-record policy.
	var present: bool=not decoded.records.is_empty()
	car_identity=decoded.records[0].identity if present else 0
	if present and is_instance_valid(car):
		car.restore_parked(decoded.records[0].pose)
		return true
	if is_instance_valid(car):car.free()
	car=null
	if present:return _install_vehicle(_world,decoded.records[0].pose)
	return true
func _install_vehicle(world: Node,pose: Transform3D) -> bool:
	# Snapshot restoration is synchronous by contract; placement checks readiness
	# first. Restore may wait for the in-flight request during world loading.
	if _vehicle_scene==null:
		if _scene_requested: _take_requested_scene()
		else: _vehicle_scene=load(VEHICLE_SCENE_PATH) as PackedScene
	if _vehicle_scene==null: return false
	var begin:=Time.get_ticks_usec() if profile_install else 0
	car=_vehicle_scene.instantiate()
	car.profile_setup=profile_install
	var allocated:=Time.get_ticks_usec() if profile_install else 0
	car.transform=pose;car.collision_layer=4;car.collision_mask=15
	world.add_child(car)
	var attached:=Time.get_ticks_usec() if profile_install else 0
	for wheel in car.wheel_rays: wheel.collision_mask=3
	car.set_controls_enabled(false);car.freeze=true;car.set_physics_process(false)
	if car_identity==0:car_identity=fleet.spawn(pose)
	car.bind_streamed_world(world.terrain,world.structures)
	if "vegetation" in world: car.streaming.bind_vegetation(world.vegetation)
	if _camera_follow==null:_camera_follow=ClassDB.instantiate("NativeVehicleCamera")
	if profile_install:
		install_timings={"instantiate_us":allocated-begin,"attach_ready_us":attached-allocated,"bind_us":Time.get_ticks_usec()-attached,"setup":car.setup_timings}
	return true
func ready_bounds(world: Node,bounds: AABB) -> bool:
	return world.terrain.is_collision_region_ready(bounds) and world.structures.is_collision_region_ready(bounds) and (not "vegetation" in world or world.vegetation.is_collision_region_ready(bounds))
func overlaps_edit(world_bounds: AABB) -> bool:
	if fleet_enabled:return activation.overlaps_edit(world_bounds)
	if not is_instance_valid(car): return false
	# Reuse the native orientation-independent chassis/suspension envelope.
	# This includes the support immediately beneath the parked vehicle.
	var bounds: AABB=car.driving_policy.travel_bounds(car.global_position,Vector3.ZERO,1.0/120.0)
	return not bounds.position.is_finite() or bounds.intersects(world_bounds)
func spawn(world: Node,carried_slot:int=-1,nearby:bool=false) -> String:
	last_spawn_identity=0
	if not can_interact():return "Vehicle interaction unavailable"
	var inventory:RefCounted
	var state:Dictionary={}
	if carried_slot<0:
		if "session_menu" in world and not world.session_menu.developer:return "Equip an owned vehicle item to place it"
	else:
		inventory=world.player_hud.inventory;state=inventory.snapshot()
		if carried_slot>=32 or state.slots[carried_slot].item!=501:return "Equip an owned vehicle item to place it"
	if nearby and carried_slot>=0:return "Nearby spawning is a development action"
	var message:=_spawn(world,nearby)
	if last_spawn_identity==0:return message
	if carried_slot>=0:
		var row:Dictionary=state.slots[carried_slot]
		if not inventory.consume(carried_slot,1,state.revision).ok:
			remove_vehicle(last_spawn_identity);return "Inventory changed; vehicle placement cancelled"
		if row.wear>0:world.world_attack.durability.hit("vehicle:%d"%last_spawn_identity,300,row.wear)
	if "changed_since_save" in world.terrain:world.terrain.changed_since_save=true
	if "player_hud" in world:world.player_hud.refresh()
	return message
func _spawn(world: Node,nearby:bool=false) -> String:
	if not can_interact(): return "Vehicle interaction unavailable"
	if not fleet_enabled and is_instance_valid(car): return "Vehicle already placed · E nearby to enter"
	request_scene()
	if not scene_ready():
		if not _scene_requested or ResourceLoader.load_threaded_get_status(VEHICLE_SCENE_PATH)==ResourceLoader.THREAD_LOAD_FAILED:
			return "Vehicle resource could not be loaded"
		return "Vehicle model is still loading; try again shortly"
	var placement:Dictionary=preload("res://addons/vehicle_runtime/vehicle_placement.gd").find(world,self,nearby)
	if not placement.ok:return placement.reason
	if fleet_enabled:return activation.place(world,placement.pose)
	if not _install_vehicle(world,placement.pose): return "Vehicle resource could not be loaded"
	last_spawn_identity=car_identity
	return "Vehicle placed · E nearby to enter · F5 saves world"
func candidate(world:Node)->int:
	if driving or not can_interact():return 0
	var result:Dictionary=fleet.query_near(world.player.global_position,3.5,16,4096)
	if not result.ok or not result.complete or result.get("truncated",false):return 0
	for id:int in result.ids:
		if reachable(world,id):return id
	return 0
func reachable(world:Node,id:int)->bool:
	var record:Dictionary=fleet.get_record(id)
	if not record.get("present",false):return false
	var at:Vector3=record.pose.origin
	var body:RigidBody3D=activation.residents.get(id) if fleet_enabled else car
	if is_instance_valid(body):at=body.global_position
	if world.player.global_position.distance_to(at)>3.5:return false
	var exclusions:Array[RID]=[world.player.get_rid()]
	if is_instance_valid(body):exclusions.append(body.get_rid())
	var ray:=PhysicsRayQueryParameters3D.create(world.player.global_position+Vector3.UP,at,7,exclusions)
	var hit:Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():return true
	return fleet_enabled and hit.collider==activation.parked_view and activation.parked_view.identity_for_body(hit.rid)==id
func remove_vehicle(id:int)->bool:
	if not fleet.remove(id):return false
	coasting.erase(id)
	if fleet_enabled:
		if activation.residents.has(id):activation.retire(id)
		activation.refresh_parked(_world)
	elif car_identity==id:
		car.collision_layer=0;car.collision_mask=0;car.freeze=true;car.queue_free();car=null;car_identity=0
	return true
func pickup(world:Node,id:int)->String:
	if driving or not can_interact() or not reachable(world,id):return "Vehicle is no longer reachable"
	var body:RigidBody3D=activation.residents.get(id) if fleet_enabled else car
	if is_instance_valid(body) and body.linear_velocity.length()>.5:return "Wait for the vehicle to stop before picking it up"
	var inventory:RefCounted=world.player_hud.inventory
	var state:Dictionary=inventory.snapshot()
	var key:="vehicle:%d"%id
	var wear:int=world.world_attack.durability.damage(key,300)
	if not inventory.grant_durable(501,wear,state.revision).ok:return "Make an empty inventory slot for the vehicle"
	if not remove_vehicle(id):
		inventory.restore(state,inventory.snapshot().revision);return "Vehicle pickup cancelled"
	world.world_attack.durability.forget(key)
	world.terrain.changed_since_save=true;world.player_hud.refresh()
	return "Vehicle picked up · equip it and right mouse to place"
func enter(world: Node,expected:int=0) -> bool:
	if not can_interact(): return false
	if expected>0 and not reachable(world,expected):return false
	if fleet_enabled and not driving:activation.select_for_entry(world.player.global_position,expected)
	if expected>0 and car_identity!=expected:return false
	if driving or not is_instance_valid(car) or world.player.global_position.distance_to(car.position)>3.5: return false
	var ray:=PhysicsRayQueryParameters3D.create(world.player.global_position+Vector3.UP,car.position,7,[world.player.get_rid(),car.get_rid()])
	if not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	_camera_local=world.camera.transform
	_physics_ticks=Engine.physics_ticks_per_second;Engine.physics_ticks_per_second=120
	_player_layer=world.player.collision_layer;_player_mask=world.player.collision_mask
	world.player.collision_layer=0;world.player.collision_mask=0
	world.player.velocity=Vector3.ZERO
	coasting.erase(car_identity);car.freeze=false;car.set_controls_enabled(true);car.set_physics_process(true)
	driving=true
	return true
func safe_exit_position(world: Node) -> Vector3:
	if not is_instance_valid(car): return Vector3.INF
	for offset:Vector3 in [Vector3(2.8,0,0),Vector3(-2.8,0,0),Vector3(0,0,-3.8),Vector3(3.8,0,0),Vector3(-3.8,0,0)]:
		var desired: Vector3=car.position+car.global_basis*offset
		var ray:=PhysicsRayQueryParameters3D.create(desired+Vector3.UP*2,desired-Vector3.UP*3,3,[car.get_rid()])
		var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.dot(Vector3.UP)<0.7: continue
		var feet: Vector3=hit.position+Vector3.UP*0.06
		if not ready_bounds(world,AABB(feet-Vector3(.4,.1,.4),Vector3(.8,2,.8))): continue
		var capsule:=CapsuleShape3D.new();capsule.height=1.8;capsule.radius=.34
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,feet+Vector3.UP*.9);query.collision_mask=15
		query.exclude=[world.player.get_rid()]
		if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
		return feet
	return Vector3.INF
func exit_vehicle(world: Node) -> String:
	if not can_interact(): return "Vehicle interaction unavailable"
	if not driving: return ""
	var feet:=safe_exit_position(world)
	if not feet.is_finite(): return "No clear, loaded exit beside the vehicle"
	car.set_controls_enabled(false);coasting[car_identity]=car
	world.player.position=feet;world.player.velocity=car.linear_velocity
	world.player.collision_layer=_player_layer;world.player.collision_mask=_player_mask
	world.camera.transform=_camera_local;driving=false
	Engine.physics_ticks_per_second=_physics_ticks
	world.terrain.focus=feet;world.terrain.travel_velocity=Vector3.ZERO
	return "On foot · E nearby to enter vehicle"
func _exit_tree() -> void:
	# Every accepted threaded request needs a matching get, even if the player
	# never places a vehicle. On early exit this can wait for the pending load.
	_take_requested_scene()
	if driving: Engine.physics_ticks_per_second=_physics_ticks
func update(world: Node,delta: float) -> void:
	for id:int in coasting.keys():
		var body:RigidBody3D=coasting[id]
		if not is_instance_valid(body):coasting.erase(id);continue
		if body.sleeping or (body.loaded_wheels>=2 and body.linear_velocity.length()<.15 and body.angular_velocity.length()<.1):
			body.freeze=true;body.set_physics_process(false);coasting.erase(id)
	if fleet_enabled:activation.update(world,delta)
	elif is_instance_valid(car):
		_obstacle_sync_time-=delta
		if _obstacle_sync_time<=0:
			_obstacle_sync_time=0.2
			fleet.set_pose(car_identity,car.global_transform)
	if not driving or not is_instance_valid(car): return
	world.player.position=car.position # Existing vegetation/building focus follows the occupant.
	world.player.velocity=Vector3.ZERO
	car.set_controls_enabled(can_interact() and world.app_focused and not world.player_hud.inventory_open and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED)
	_camera_follow.update(car,world.camera,delta)
