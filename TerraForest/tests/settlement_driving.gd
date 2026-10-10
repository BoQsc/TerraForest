# SPDX-License-Identifier: 0BSD
extends SceneTree
const DIR="res://reports/settlement_driving/"
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence/staged_placement/manifest.json"))
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	if game.terrain.save_slot!=source.slot or game.loading_active:
		check(false,"disposable saved settlement ready");game.terrain.shutdown();quit(1);return
	game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false
	var street: Dictionary=game.road_palette.prepared_streets[0]
	var a: Vector3=street.ends[0];var b: Vector3=street.ends[1];var direction: Vector3=(b-a).normalized()
	var start: Vector3=a+direction*5
	game.yaw=atan2(-direction.x,-direction.z);game.player.rotation.y=game.yaw
	game.player.position=start-direction*6+Vector3.UP*1.0
	game.terrain.focus=start
	game.camera.global_position=start-direction*6+Vector3.UP*4;game.camera.look_at(start)
	deadline=Time.get_ticks_msec()+15000
	while (not game.world_vehicle.scene_ready() or not game.world_vehicle.ready_bounds(game,AABB(start-Vector3.ONE*4,Vector3.ONE*8))) and Time.get_ticks_msec()<deadline:await process_frame
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var placed: String=game.world_vehicle.spawn(game)
	check(is_instance_valid(game.world_vehicle.car),"place vehicle on authored street: "+placed)
	if not is_instance_valid(game.world_vehicle.car):game.terrain.shutdown();quit(1);return
	var car=game.world_vehicle.car
	check(car.global_basis.z.dot(direction)>0.99,"vehicle faces player's road heading")
	game.player.position=car.position+car.global_basis.x*2.8
	check(game.world_vehicle.enter(game),"enter vehicle on loaded settlement road")
	game.set_physics_process(true)
	for tick in 60:await physics_frame
	var initial: Vector3=car.position;var rows: Array=[];var held:=0;var max_speed:=0.0
	var press:=InputEventKey.new();press.keycode=KEY_W;press.physical_keycode=KEY_W;press.pressed=true
	for tick in 600:
		game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		Input.parse_input_event(press.duplicate());Input.flush_buffered_events();await physics_frame
		if car.streaming.waiting:held+=1
		max_speed=maxf(max_speed,car.speed_kph)
		if tick%30==0:rows.append({"position":car.position,"speed_kph":car.speed_kph,"waiting":car.streaming.waiting})
		if (car.position-initial).dot(direction)>=15:break
	press.pressed=false;Input.parse_input_event(press);Input.flush_buffered_events()
	var along: float=(car.position-initial).dot(direction)
	var lateral: float=absf((car.position-start).dot(Vector3(-direction.z,0,direction.x)))
	check(along>=15 and lateral<2 and car.position.is_finite(),"drive fifteen metres continuously along street")
	check(car.position.y>start.y-2 and car.position.y<start.y+3,"vehicle remains supported by asphalt road")
	check(game.world_vehicle.driving and game.player.position.distance_to(car.position)<2,"driver and camera remain attached")
	check(held==0,"no collision-readiness holds on short loaded street")
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(DIR+"driving.png")
	var report:={"failures":failures,"road":street,"distance":along,"lateral":lateral,"max_speed_kph":max_speed,"held_ticks":held,"rows":rows,"scope":"Short real vehicle drive in saved furnished settlement with terrain/forest. No region-boundary, high-speed, dense fleet, frame or thermal qualification."}
	var f:=FileAccess.open(DIR+"result.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	# Preserve the fixture input save; shutdown intentionally reports save blocked.
	game.terrain.backend.disable_snapshot_writes();game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
