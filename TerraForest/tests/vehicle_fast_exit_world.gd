# SPDX-License-Identifier: 0BSD
# Reproduction only: drive the actual temporary world, log exit and reset causes.
extends "res://tests/vehicle_exit_world_diagnosis.gd"
var car:RigidBody3D
var rows:Array=[]
var observations:Dictionary={}
var label:="boost"
var requested_speed:=0.0
var target_distance:=384.0
var target_speed:=50.0
func key(code:int,pressed:bool)->void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func trace(phase:String,tick:int)->Dictionary:
	var record:Dictionary=game.world_vehicle.fleet.get_record(game.world_vehicle.car_identity)
	return {"phase":phase,"tick":tick,"position":car.position,"velocity":car.linear_velocity,"angular":car.angular_velocity,
		"loaded":car.loaded_wheels,"freeze":car.freeze,"waiting":car.streaming.waiting,"driving":game.world_vehicle.driving,
		"controls":car.controls_enabled,"events":car.return_events.size(),"player":game.player.position,
		"fleet_position":record.pose.origin if record.get("present",false) else Vector3.INF}
func finish()->void:
	for code in [KEY_W,KEY_SHIFT,KEY_R]:key(code,false)
	observations["failures"]=failures;observations["samples"]=rows
	if is_instance_valid(car):observations["events"]=car.return_events.duplicate();observations["after"]=trace("final",-1)
	var report:=FileAccess.open("res://reports/vehicle_fast_exit_world_"+label+".json",FileAccess.WRITE)
	report.store_string(JSON.stringify(observations,"  "));report.close()
	var brief:=observations.duplicate();brief.erase("samples");print("FAST_EXIT_WORLD ",brief)
	if is_instance_valid(game):game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
	if is_instance_valid(observer):observer.free()
	await process_frame;print("VEHICLE_FAST_EXIT_WORLD_DIAGNOSIS failures=",failures);quit(1 if failures else 0)
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--return-speed="):requested_speed=float(arg.trim_prefix("--return-speed="));label="injected_"+str(int(requested_speed))
		if arg.begins_with("--return-distance="):target_distance=float(arg.trim_prefix("--return-distance="))
	label+="_d"+str(int(target_distance))
	if "--vehicle-fleet" in OS.get_cmdline_user_args():label+="_fleet"
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not await wait_for(func():return not game.loading_active,45):failures+=1;print("FAIL world startup");await finish();return
	if not await wait_for(func():return game.world_vehicle.scene_ready()):failures+=1;print("FAIL vehicle resource");await finish();return
	game.fly=false;game.needs_floor_spawn=false;game._clear_motion();foreground()
	var session:Node=game.world_vehicle
	var model=session._vehicle_scene.instantiate();model.set_script(load("res://tests/vehicle_return_trace_car.gd"))
	var traced:=PackedScene.new();traced.pack(model);model.free();session._vehicle_scene=traced
	var message:String=session.spawn_requested(game)
	if session.fleet_enabled and session.last_spawn_identity>0:
		session.car=session.activation.residents[session.last_spawn_identity];session.car_identity=session.last_spawn_identity
	if not is_instance_valid(session.car):failures+=1;print("FAIL vehicle fixture ",message);await finish();return
	car=session.car
	game.player.position=car.position+car.basis.x*2.8
	for tick in 3:foreground();await physics_frame
	if not session.enter(game):failures+=1;print("FAIL entry");await finish();return
	for tick in 180:foreground();await physics_frame
	var start:Vector3=car.position;var reset_origin:Vector3=car._spawn_transform.origin;var peak:=0.0;var furthest:=0.0
	observations={"label":label,"speed_mode":"real W+Shift input" if requested_speed==0 else "injected initial coasting speed",
		"requested_mps":requested_speed,"start":start,"spawn_reset_target":reset_origin,"fleet_enabled":session.fleet_enabled,
		"target_distance_m":target_distance,"target_speed_mps":target_speed,
		"scope":"Actual temporary world, full vegetation/structure collision, actual player controller and E handler; traced production reset/restore behavior; no player save opened"}
	observer=Camera3D.new();root.add_child(observer);observer.make_current()
	if requested_speed>0:car._drive_speed=requested_speed;car.linear_velocity=car.basis.z*requested_speed
	else:key(KEY_W,true);key(KEY_SHIFT,true)
	var ready_to_exit:=false
	for tick in 120*20:
		foreground();await physics_frame
		peak=maxf(peak,car.linear_velocity.length());furthest=maxf(furthest,car.position.distance_to(start))
		observer.position=car.position+Vector3(8,4,-9);observer.look_at(car.position+Vector3.UP*.5)
		if tick%4==0:rows.append(trace("driving",tick))
		if furthest>=target_distance and car.linear_velocity.length()>=target_speed:ready_to_exit=true;break
		if not car.return_events.is_empty():break
	key(KEY_W,false);key(KEY_SHIFT,false)
	observations["maximum_drive_distance"]=furthest;observations["peak_speed_mps"]=peak;observations["long_fast_drive_qualified"]=ready_to_exit
	observations["before_exit"]=trace("before_exit",-1)
	if not ready_to_exit:
		observations["outcome"]="Long/high-speed exit condition not reached; do not treat as a negative reproduction."
		await finish();return
	var exited:=false
	for tick in 120*4:
		foreground()
		if tick%12==0:
			var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=KEY_E;game._unhandled_input(event)
			if not session.driving:exited=true;break
		await physics_frame
	observations["exit_accepted"]=exited;observations["exit"]=trace("exit",-1)
	if not exited:observations["outcome"]="No supported exit accepted during the high-speed attempt.";await finish();return
	var exit_position:Vector3=car.position;var returned:=false;var previous:Vector3=car.position;var largest_jump:=0.0;var minimum_y:float=car.position.y
	for tick in 60*12:
		foreground();await physics_frame
		var row:=trace("after_exit",tick);rows.append(row)
		largest_jump=maxf(largest_jump,car.position.distance_to(previous));previous=car.position;minimum_y=minf(minimum_y,car.position.y)
		observer.position=car.position+Vector3(8,4,-9);observer.look_at(car.position+Vector3.UP*.5)
		if car.position.distance_to(reset_origin)<5 and exit_position.distance_to(reset_origin)>50:returned=true;break
	observations["returned_to_spawn"]=returned;observations["largest_tick_displacement"]=largest_jump;observations["minimum_y_after_exit"]=minimum_y
	observations["outcome"]="Returned to spawn after exit" if returned else "No return during 12 seconds after the qualified exit"
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/vehicle_fast_exit_world_"+label+".png")
	await finish()
