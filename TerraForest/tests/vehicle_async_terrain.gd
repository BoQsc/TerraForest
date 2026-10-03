# SPDX-License-Identifier: 0BSD
extends SceneTree
var terrain: Node3D
func _initialize() -> void: call_deferred("run")
func fail(reason: String) -> void:
	print("FAIL ",reason)
	if terrain!=null: print("LOADER_STATE ",{"error":terrain.latest_error,"worker":terrain.backend.status(),"queued":terrain.backend.queued(),"builds":terrain.worker_builds})
	if terrain!=null: terrain.shutdown();terrain.free()
	quit(1)
func run() -> void:
	Engine.max_fps=60;Engine.physics_ticks_per_second=120
	terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.backend.world_generator=2;terrain.backend.region_terrain=true
	terrain.backend.disk_cache.enabled=false;terrain.nearby_first=true
	terrain.focus=Vector3(400,181,405);root.add_child(terrain)
	var material:=StandardMaterial3D.new();material.albedo_color=Color(0.3,0.34,0.29)
	if terrain.start(material,true)!=OK: fail("terrain worker start");return
	var deadline:=Time.get_ticks_msec()+20000
	while not terrain.world_ready and terrain.latest_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	if not terrain.world_ready: fail("world initialization deadline");return
	if not terrain.construct_road_bed(Vector3(400,180,400),Vector3(400,184,464),4,4,6): fail("road edit rejected");return
	while terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
	if terrain.pending_edit: fail("road publication deadline");return
	var car=load("res://vehicle_demo/scenes/car.tscn").instantiate()
	car.position=Vector3(400,182,405);root.add_child(car);car.bind_streamed_world(terrain)
	var camera:=Camera3D.new();root.add_child(camera);camera.make_current()
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);root.add_child(light)
	var waited:=0
	while (not terrain.is_collision_region_ready(car.driving_policy.travel_bounds(car.position,Vector3.ZERO,1.0/120))) and Time.get_ticks_msec()<deadline:
		camera.position=car.position+Vector3(9,7,-12);camera.look_at(car.position)
		await physics_frame;waited+=1
	if Time.get_ticks_msec()>=deadline: fail("initial vehicle collision publication deadline");return
	for tick in 120: await physics_frame
	var start: Vector3=car.position
	var key:=InputEventKey.new();key.keycode=KEY_W;key.physical_keycode=KEY_W;key.pressed=true
	Input.parse_input_event(key);Input.flush_buffered_events()
	var held:=0;var supported:=0
	for tick in 480:
		await physics_frame
		if car.streaming.waiting: held+=1
		if car.loaded_wheels>=3: supported+=1
		camera.position=car.position+Vector3(9,7,-12);camera.look_at(car.position)
	var release:=InputEventKey.new();release.keycode=KEY_W;release.physical_keycode=KEY_W
	Input.parse_input_event(release);Input.flush_buffered_events()
	var passed: bool=car.position.is_finite() and car.position.z>432 and car.position.y>180 and absf(car.position.x-400)<1
	print("ASYNC_VEHICLE_TERRAIN ",{"passed":passed,"start":start,"end":car.position,"initial_wait_ticks":waited,"held_ticks":held,"supported_ticks":supported,"ticks":480,"speed_kph":car.speed_kph,"worker_builds":terrain.worker_builds})
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/vehicle_async_terrain.png")
	car.free();terrain.shutdown();terrain.free();camera.free();light.free()
	quit(0 if passed else 1)
