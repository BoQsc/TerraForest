# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func finish(game: Node,passed: bool,message: String) -> void:
	print(("PASS " if passed else "FAIL ")+message)
	game.terrain.shutdown();game.free();quit(0 if passed else 1)
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	if game.loading_active: finish(game,false,"world startup deadline");return
	deadline=Time.get_ticks_msec()+15000
	while not game.world_vehicle.scene_ready() and Time.get_ticks_msec()<deadline: await process_frame
	if not game.world_vehicle.scene_ready(): finish(game,false,"vehicle resource deadline");return
	game.fly=false;game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var base: Vector3=game.player.position
	var outcome: String="no suitable ground"
	var placement_us:=0
	var placement_begin:=0
	for offset in [Vector3(0,0,-7),Vector3(7,0,0),Vector3(-7,0,0),Vector3(0,0,7)]:
		var ray:=PhysicsRayQueryParameters3D.create(base+offset+Vector3.UP*8,base+offset-Vector3.UP*12,1)
		var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty(): continue
		game.camera.look_at(hit.position)
		placement_begin=Time.get_ticks_usec()
		outcome=game.world_vehicle.spawn(game)
		placement_us=Time.get_ticks_usec()-placement_begin
		if is_instance_valid(game.world_vehicle.car): break
	if not is_instance_valid(game.world_vehicle.car): finish(game,false,"placement: "+outcome);return
	var visible_intervals: Array=[]
	var previous:=placement_begin
	for frame in 8:
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		visible_intervals.append((now-previous)/1000.0);previous=now
	print("VEHICLE_FIRST_VISIBLE ",{"placement_us":placement_us,"intervals_ms":visible_intervals,"cap":Engine.max_fps,"size":root.size,"scope":"Whole world wall intervals including streaming and frame cap; first interval begins at placement, not previous frame."})
	var car=game.world_vehicle.car
	var walking_help: String=game.help.text
	game.player.position=car.position+Vector3.RIGHT*2.8
	if not game.world_vehicle.enter(game): finish(game,false,"world vehicle entry");return
	game._clear_motion()
	for tick in 120: await physics_frame
	var saved_player: PackedByteArray=game._capture_player_pose()
	var decoded_player: Dictionary=game.player_pose.decode(saved_player)
	var seated_save_ok: bool=decoded_player.get("ok",false) and decoded_player.has("position") and decoded_player.position.distance_to(car.position)<4 and game.world_vehicle.driving
	game.vegetation._collision_sync_ok=false
	seated_save_ok=seated_save_ok and not game.player_pose.validate_snapshot(game._capture_player_pose())
	game.vegetation._collision_sync_ok=true
	print("SEATED_SAVE ",{"passed":seated_save_ok,"restore_pose":decoded_player,"driving":game.world_vehicle.driving})
	var start: Vector3=car.position
	var press:=InputEventKey.new();press.keycode=KEY_W;press.physical_keycode=KEY_W;press.pressed=true
	Input.parse_input_event(press);Input.flush_buffered_events()
	# Automation can lose OS focus while tools run. Simulate the foreground
	# input contract explicitly; this fixture is not a frame-rate benchmark.
	for tick in 120:
		game.app_focused=true;Engine.max_fps=60
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		Input.parse_input_event(press.duplicate());Input.flush_buffered_events()
		await physics_frame
	var release:=InputEventKey.new();release.keycode=KEY_W;release.physical_keycode=KEY_W
	Input.parse_input_event(release);Input.flush_buffered_events()
	var distance: float=car.position.distance_to(start)
	var passed: bool=game.world_vehicle.driving and distance>1 and car.position.is_finite() and game.player.position.distance_to(car.position)<2 and game.camera.current
	passed=passed and not game.player_hud.visible and not game.player_hud.enabled and game.help.text.contains("Steer")
	print("WORLD_VEHICLE_VISUAL ",{"passed":passed,"distance":distance,"position":car.position,"speed_kph":car.speed_kph,"held":car.streaming.waiting,"controls_enabled":car.controls_enabled,"simulated_foreground":true,"trees":game.vegetation.renderer.roots.size()})
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/world_vehicle_visual.png")
	car.set_physics_process(false);car.linear_velocity=Vector3.ZERO;car._drive_speed=0.0
	var exit_message: String=game.world_vehicle.exit_vehicle(game)
	await process_frame;await process_frame
	var restored: bool=not game.world_vehicle.driving and game.player_hud.visible and game.player_hud.enabled and game.help.text==walking_help
	print("WORLD_VEHICLE_EXIT ",{"passed":restored,"message":exit_message})
	finish(game,passed and restored and seated_save_ok,"main-world placement driving seated save exit and UI restoration")
