# SPDX-License-Identifier: 0BSD
# Single local vehicle interaction adapter. Driving physics lives in the native addon.
extends Node
var car: RigidBody3D
var driving:=false
var _camera_local: Transform3D
var _player_layer:=0
var _player_mask:=0
var _physics_ticks:=60
var _camera_follow: RefCounted
var storage: RefCounted
var _world: Node
func prepare(world: Node,persistence: RefCounted) -> bool:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	storage=ClassDB.instantiate("NativeVehicleStorage");_world=world
	return persistence.register_component("vehicles",capture_snapshot,restore_snapshot,storage,PackedByteArray())
func capture_snapshot() -> PackedByteArray:
	if not is_instance_valid(car): return PackedByteArray()
	var data: PackedByteArray=storage.encode(car.global_transform)
	# Invalid live state must reject the compound save, not silently delete a car.
	return PackedByteArray([0]) if data.is_empty() else data
func restore_snapshot(data: PackedByteArray) -> bool:
	var decoded: Dictionary=storage.decode(data)
	if not decoded.ok: return false
	if driving:
		_world.player.collision_layer=_player_layer;_world.player.collision_mask=_player_mask
		_world.camera.transform=_camera_local;Engine.physics_ticks_per_second=_physics_ticks
		driving=false
	if is_instance_valid(car): car.free()
	car=null
	if decoded.present: _install_vehicle(_world,decoded.pose)
	return true
func _install_vehicle(world: Node,pose: Transform3D) -> void:
	car=load("res://vehicle_demo/scenes/car.tscn").instantiate()
	car.transform=pose;car.collision_layer=4;car.collision_mask=3
	world.add_child(car)
	for wheel in car.wheel_rays: wheel.collision_mask=3
	car.set_controls_enabled(false);car.freeze=true;car.set_physics_process(false)
	car.bind_streamed_world(world.terrain,world.structures)
	if "vegetation" in world: car.streaming.bind_vegetation(world.vegetation)
	_camera_follow=ClassDB.instantiate("NativeVehicleCamera")
func ready_bounds(world: Node,bounds: AABB) -> bool:
	return world.terrain.is_collision_region_ready(bounds) and world.structures.is_collision_region_ready(bounds) and (not "vegetation" in world or world.vegetation.is_collision_region_ready(bounds))
func spawn(world: Node) -> String:
	if is_instance_valid(car): return "Vehicle already placed · E nearby to enter"
	var from: Vector3=world.camera.global_position
	var ray:=PhysicsRayQueryParameters3D.create(from,from-world.camera.global_basis.z*12,3,[world.player.get_rid()])
	var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.dot(Vector3.UP)<0.9: return "Aim at nearby level ground"
	var at: Vector3=hit.position+Vector3.UP*0.85
	var bounds:=AABB(at-Vector3(3.25,1,3.25),Vector3(6.5,3,6.5))
	if not ready_bounds(world,bounds): return "Vehicle area is still loading"
	var box:=BoxShape3D.new();box.size=Vector3(2.2,1.8,4.4)
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=box;query.transform=Transform3D(Basis.IDENTITY,at+Vector3.UP*0.3);query.collision_mask=3
	# Keep the ground below the initial chassis and reject walls/objects/player.
	if bounds.has_point(world.player.global_position): return "Place vehicle farther from the player"
	if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return "Vehicle space is obstructed"
	_install_vehicle(world,Transform3D(Basis.IDENTITY,at))
	return "Vehicle placed · E nearby to enter · F5 saves world"
func enter(world: Node) -> bool:
	if driving or not is_instance_valid(car) or world.player.global_position.distance_to(car.position)>3.5: return false
	var ray:=PhysicsRayQueryParameters3D.create(world.player.global_position+Vector3.UP,car.position,3,[world.player.get_rid(),car.get_rid()])
	if not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	_camera_local=world.camera.transform
	_physics_ticks=Engine.physics_ticks_per_second;Engine.physics_ticks_per_second=120
	_player_layer=world.player.collision_layer;_player_mask=world.player.collision_mask
	world.player.collision_layer=0;world.player.collision_mask=0
	world.player.velocity=Vector3.ZERO
	car.freeze=false;car.set_controls_enabled(true);car.set_physics_process(true)
	driving=true
	return true
func exit_vehicle(world: Node) -> String:
	if not driving: return ""
	if car.linear_velocity.length()>1.5: return "Stop the vehicle before exiting"
	for side in [1.0,-1.0]:
		var desired: Vector3=car.position+car.global_basis.x*side*2.8
		var ray:=PhysicsRayQueryParameters3D.create(desired+Vector3.UP*2,desired-Vector3.UP*3,3,[car.get_rid()])
		var hit: Dictionary=world.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.dot(Vector3.UP)<0.7: continue
		var feet: Vector3=hit.position+Vector3.UP*0.06
		if not ready_bounds(world,AABB(feet-Vector3(.4,.1,.4),Vector3(.8,2,.8))): continue
		var capsule:=CapsuleShape3D.new();capsule.height=1.8;capsule.radius=.34
		var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,feet+Vector3.UP*.9);query.collision_mask=7
		query.exclude=[world.player.get_rid()]
		if not world.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
		car.set_controls_enabled(false);car.freeze=true;car.set_physics_process(false)
		world.player.position=feet;world.player.velocity=Vector3.ZERO
		world.player.collision_layer=_player_layer;world.player.collision_mask=_player_mask
		world.camera.transform=_camera_local;driving=false
		Engine.physics_ticks_per_second=_physics_ticks
		world.terrain.focus=feet;world.terrain.travel_velocity=Vector3.ZERO
		return "On foot · E nearby to enter vehicle"
	return "No clear, loaded exit beside the vehicle"
func _exit_tree() -> void:
	if driving: Engine.physics_ticks_per_second=_physics_ticks
func update(world: Node,delta: float) -> void:
	if not driving or not is_instance_valid(car): return
	world.player.position=car.position # Existing vegetation/building focus follows the occupant.
	world.player.velocity=Vector3.ZERO
	car.set_controls_enabled(world.app_focused and not world.player_hud.inventory_open and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED)
	_camera_follow.update(car,world.camera,delta)
