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
	if "--junction-turn" in OS.get_cmdline_user_args():
		await junction_turn(game,car,b)
		game.terrain.backend.disable_snapshot_writes();game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0);return
	var brake_exit: bool="--brake-exit" in OS.get_cmdline_user_args()
	var initial: Vector3=car.position;var rows: Array=[];var held:=0;var max_speed:=0.0
	var press:=InputEventKey.new();press.keycode=KEY_W;press.physical_keycode=KEY_W;press.pressed=true
	for tick in 600:
		game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		Input.parse_input_event(press.duplicate());Input.flush_buffered_events();await physics_frame
		if car.streaming.waiting:held+=1
		max_speed=maxf(max_speed,car.speed_kph)
		if tick%30==0:rows.append({"position":car.position,"speed_kph":car.speed_kph,"waiting":car.streaming.waiting})
		if (car.position-initial).dot(direction)>=(6 if brake_exit else 15):break
	press.pressed=false;Input.parse_input_event(press);Input.flush_buffered_events()
	var braking: Dictionary={}
	if brake_exit:
		var brake_start: Vector3=car.position
		var brake:=InputEventKey.new();brake.keycode=KEY_S;brake.physical_keycode=KEY_S;brake.pressed=true
		var stop_ticks:=0
		for tick in 360:
			game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
			Input.parse_input_event(brake.duplicate());Input.flush_buffered_events();await physics_frame
			stop_ticks=tick+1
			if car.linear_velocity.length()<0.15:break
		brake.pressed=false;Input.parse_input_event(brake);Input.flush_buffered_events()
		braking={"distance":(car.position-brake_start).dot(direction),"ticks":stop_ticks,"speed":car.linear_velocity.length()}
		check(braking.speed<0.15 and braking.distance>=0 and braking.distance<8,"brakes to rest within eight metres without reversing")
	var along: float=(car.position-initial).dot(direction)
	var lateral: float=absf((car.position-start).dot(Vector3(-direction.z,0,direction.x)))
	check(along>=(6 if brake_exit else 15) and lateral<2 and car.position.is_finite(),"drive continuously along street")
	check(car.position.y>start.y-2 and car.position.y<start.y+3,"vehicle remains supported by asphalt road")
	check(game.world_vehicle.driving and game.player.position.distance_to(car.position)<2,"driver and camera remain attached")
	check(held==0,"no collision-readiness holds on short loaded street")
	if brake_exit:
		var message: String=game.world_vehicle.exit_vehicle(game)
		await process_frame;await process_frame
		check(not game.world_vehicle.driving and game.player_hud.visible and game.player_hud.enabled and game.player.collision_mask!=0,"exit stopped vehicle restores walking and toolbelt: "+message)
		var exit_start: Vector3=game.player.position
		game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
		for tick in 20:
			game.app_focused=true;await physics_frame
		game.controls.clear(Time.get_ticks_usec())
		check(game.player.position.distance_to(exit_start)>0.4 and game.player.is_on_floor(),"player walks on road after exiting")
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(DIR+"driving.png")
	var report:={"failures":failures,"road":street,"distance":along,"lateral":lateral,"max_speed_kph":max_speed,"held_ticks":held,"braking":braking,"rows":rows,"scope":"Short real vehicle drive in saved furnished settlement with terrain/forest. Optional brake/exit check. No region-boundary, high-speed, dense fleet, frame or thermal qualification."}
	var f:=FileAccess.open(DIR+"result.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	# Preserve the fixture input save; shutdown intentionally reports save blocked.
	game.terrain.backend.disable_snapshot_writes();game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)

func key_state(code: int,pressed: bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)
func junction_turn(game: Node,car: RigidBody3D,junction: Vector3) -> void:
	# This fixture's first street runs +X, and the connecting street runs +Z.
	# Only keyboard controls are applied; no pose or velocity correction.
	var points: Array[Vector3]=[junction+Vector3(-8,0,0),junction+Vector3(-4,0,1),junction+Vector3(-1,0,4),junction+Vector3(0,0,9),junction+Vector3(0,0,18)]
	var next:=0;var held:=0;var rows: Array=[];var max_speed:=0.0;var max_deviation:=0.0
	for tick in 1800:
		var here: Vector3=car.position;here.y=junction.y
		if here.distance_to(points[next])<2.5:
			next+=1
			if next==points.size():break
		var desired: Vector3=(points[next]-here).normalized()
		var forward: Vector3=car.global_basis.z;forward.y=0;forward=forward.normalized()
		var angle:=atan2(forward.cross(desired).y,forward.dot(desired))
		game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		key_state(KEY_W,car.speed_kph<15);key_state(KEY_S,car.speed_kph>19)
		key_state(KEY_A,angle>0.06);key_state(KEY_D,angle< -0.06);Input.flush_buffered_events()
		await physics_frame
		if car.streaming.waiting:held+=1
		max_speed=maxf(max_speed,car.speed_kph)
		var deviation: float=minf(absf(car.position.z-junction.z),absf(car.position.x-junction.x))
		max_deviation=maxf(max_deviation,deviation)
		if tick%30==0:rows.append({"position":car.position,"speed_kph":car.speed_kph,"waypoint":next,"angle":angle,"waiting":car.streaming.waiting})
	for code in [KEY_W,KEY_S,KEY_A,KEY_D]:key_state(code,false)
	Input.flush_buffered_events()
	check(next==points.size(),"keyboard-driven right turn reaches connecting street")
	check(max_deviation<3 and absf(car.position.y-junction.y)<2,"turn remains on the authored road surface")
	check(held==0,"junction crossing has no collision readiness holds")
	check(car.global_basis.z.dot(Vector3.BACK)>0.8,"vehicle leaves junction facing connecting street")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR+"junction.png")
	var f:=FileAccess.open(DIR+"junction.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures,"waypoints_reached":next,"max_speed_kph":max_speed,"max_deviation":max_deviation,"held_ticks":held,"rows":rows,"scope":"Keyboard-controlled right turn on loaded saved settlement roads. No physics pose correction, no streamed-boundary or frame-performance claim."},"  "));f.close()
