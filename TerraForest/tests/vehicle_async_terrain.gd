# SPDX-License-Identifier: 0BSD
extends SceneTree
var terrain: Node3D
var crossing:=false
func _initialize() -> void: call_deferred("run")
func fail(reason: String) -> void:
	print("FAIL ",reason)
	if terrain!=null: print("LOADER_STATE ",{"error":terrain.latest_error,"worker":terrain.backend.status(),"queued":terrain.backend.queued(),"builds":terrain.worker_builds})
	if terrain!=null: terrain.shutdown();terrain.free()
	quit(1)
func run() -> void:
	Engine.max_fps=60;Engine.physics_ticks_per_second=120
	crossing="--streamed-crossing" in OS.get_cmdline_user_args()
	terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.backend.world_generator=2;terrain.backend.region_terrain=true
	terrain.backend.disk_cache.enabled=false;terrain.nearby_first=true
	terrain.focus=Vector3(400,181,405);root.add_child(terrain)
	var material:=StandardMaterial3D.new();material.albedo_color=Color(0.3,0.34,0.29)
	if terrain.start(material,true)!=OK: fail("terrain worker start");return
	var deadline:=Time.get_ticks_msec()+20000
	while not terrain.world_ready and terrain.latest_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	if not terrain.world_ready: fail("world initialization deadline");return
	for section in (5 if crossing else 1):
		deadline=Time.get_ticks_msec()+20000
		var road_a:=Vector3(400,180,400+section*64)
		var road_b:=Vector3(400,180 if crossing else 184,464+section*64)
		if not terrain.construct_road_bed(road_a,road_b,4,4,6): fail("road edit rejected");return
		while terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
		if terrain.pending_edit: fail("road publication deadline");return
	deadline=Time.get_ticks_msec()+20000
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
	var target_bounds: AABB=car.driving_policy.travel_bounds(Vector3(400,181,650),Vector3.ZERO,1.0/120)
	var target_initially_ready: bool=terrain.is_collision_region_ready(target_bounds)
	var builds_before: int=terrain.worker_builds
	var held:=0;var supported:=0;var ticks:=0;var max_hold:=0;var current_hold:=0;var max_speed:=0.0
	var rows: Array=[]
	for tick in (3600 if crossing else 480):
		await physics_frame
		ticks+=1
		if car.streaming.waiting: held+=1;current_hold+=1
		else: current_hold=0
		max_hold=maxi(max_hold,current_hold);max_speed=maxf(max_speed,car.speed_kph)
		if tick%60==0: rows.append({"tick":tick,"position":car.position,"waiting":car.streaming.waiting,"wheels":car.loaded_wheels,"worker":terrain.backend.status(),"queued":terrain.backend.queued()})
		if car.loaded_wheels>=3: supported+=1
		camera.position=car.position+Vector3(9,7,-12);camera.look_at(car.position)
		if crossing and (car.position.z>=650 or car.position.y<178): break
	var release:=InputEventKey.new();release.keycode=KEY_W;release.physical_keycode=KEY_W
	Input.parse_input_event(release);Input.flush_buffered_events()
	var passed: bool=car.position.is_finite() and car.position.z>432 and car.position.y>180 and absf(car.position.x-400)<1
	if crossing: passed=passed and car.position.z>=650 and not target_initially_ready and terrain.worker_builds>builds_before and held==0 and supported>=ticks*0.95
	var result: Dictionary={"passed":passed,"start":start,"end":car.position,"initial_wait_ticks":waited,"held_ticks":held,"supported_ticks":supported,"ticks":ticks,"max_hold_ticks":max_hold,"max_speed_kph":max_speed,"target_initially_ready":target_initially_ready,"builds_before":builds_before,"rows":rows,"speed_kph":car.speed_kph,"worker_builds":terrain.worker_builds}
	print("ASYNC_VEHICLE_TERRAIN ",result)
	var file:=FileAccess.open("res://reports/vehicle_async_terrain.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/vehicle_async_terrain.png")
	car.free();terrain.shutdown();terrain.free();camera.free();light.free()
	quit(0 if passed else 1)
