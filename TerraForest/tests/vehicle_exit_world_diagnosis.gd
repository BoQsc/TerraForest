# SPDX-License-Identifier: 0BSD
# Integrated regression using the same world/E-input path as the baseline.
extends SceneTree
var game:Node
var failures:=0
var cases:Array=[]
var observer:Camera3D
func _initialize()->void:run.call_deferred()
func wait_for(predicate:Callable,seconds:int=30)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func foreground()->void:
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func sample(label:String)->Dictionary:
	var car:RigidBody3D=game.world_vehicle.car
	var physics:Transform3D=PhysicsServer3D.body_get_state(game.player.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
	return {"label":label,"position":car.position,"velocity":car.linear_velocity,"angular":car.angular_velocity,
		"freeze":car.freeze,"loaded":car.loaded_wheels,"springs":car._spring_lengths.duplicate(),
		"player_scene":game.player.position,"player_physics":physics.origin,"player_contact":game.player in car.get_colliding_bodies(),
		"player_layer":game.player.collision_layer,"player_mask":game.player.collision_mask,"exit_guard":game.player in car.get_collision_exceptions()}
func capture(name:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/vehicle_exit_world_"+name+".png")
func run_case(pose:Transform3D,speed:float,repeat:int)->void:
	var session:Node=game.world_vehicle;var car:RigidBody3D=session.car
	if repeat==0:
		session.coasting.clear();car.restore_parked(pose)
		game.player.position=car.position+car.basis.x*2.8;game.player.velocity=Vector3.ZERO
	var player_layer:int=game.player.collision_layer;var player_mask:int=game.player.collision_mask
	foreground()
	for tick in 3:await physics_frame
	if not session.enter(game):failures+=1;print("FAIL world entry");return
	for tick in 180:foreground();await physics_frame
	if car.streaming.waiting:failures+=1;print("FAIL fixture collision unavailable");return
	var name:String="fixed_"+str(speed).replace(".","_")+"_repeat_"+str(repeat)
	observer.position=car.position+Vector3(8,4,-9);observer.look_at(car.position+Vector3.UP*.5);observer.make_current()
	if speed==0.0 and repeat==0:await capture("fixed_before")
	car._drive_speed=speed;car.linear_velocity=car.basis.z*speed
	var before:=sample("before_exit")
	foreground()
	var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=KEY_E
	game._unhandled_input(event)
	if session.driving:failures+=1;print("FAIL world exit ",session.safe_exit_position(game));return
	var immediate:=sample("immediate")
	var rows:Array=[];var minimum_y:float=car.position.y;var contacts:=0
	var collision_restored:=true;var guard_cleared:=false
	for tick in 120:
		foreground();await physics_frame
		var row:=sample(str(tick));rows.append(row);minimum_y=minf(minimum_y,car.position.y)
		if row.player_contact:contacts+=1
		collision_restored=collision_restored and row.player_layer==player_layer and row.player_mask==player_mask
		if tick>=4 and not row.exit_guard:guard_cleared=true
	if repeat==0:
		# Actual final gameplay state; no measured-pose replay or freeze injection.
		observer.position=car.position+Vector3(2.5,1.5,-3);observer.look_at(car.position+Vector3.UP*.4);observer.make_current()
		await capture(name+"_full_foliage")
		game.vegetation.hide()
		observer.position=pose.origin+Vector3(4,2,-4);observer.look_at(pose.origin+Vector3.UP*.3);observer.make_current()
		await capture(name+"_clear_view")
		game.vegetation.show()
	var result:={"initial_speed":speed,"repeat":repeat,"before":before,"immediate":immediate,
		"after":rows[-1],"minimum_y":minimum_y,"maximum_drop":before.position.y-minimum_y,"contact_ticks":contacts,"samples":rows}
	cases.append(result)
	var brief:=result.duplicate();brief.erase("samples");print("WORLD_EXIT_DIAGNOSIS ",brief)
	if contacts>0 or result.maximum_drop>.15:failures+=1;print("FAIL world exit shove ",name)
	if not collision_restored or not guard_cleared or game.player.position.y<45:failures+=1;print("FAIL player collision or exit transition ",name)
	if not car.freeze or not session.coasting.is_empty():failures+=1;print("FAIL unoccupied vehicle did not settle ",name)
func finish()->void:
	var report:=FileAccess.open("res://reports/vehicle_exit_world_diagnosis.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures":failures,"scope":"Temporary generated world, corrected production exit, real player/native walking, streaming, host update, E input and repeated re-entry","physics_engine":ProjectSettings.get_setting("physics/3d/physics_engine","DEFAULT"),"cases":cases},"  "));report.close()
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
	if is_instance_valid(observer):observer.free()
	await process_frame
	print("VEHICLE_EXIT_WORLD_REGRESSION failures=",failures);quit(1 if failures else 0)
func run()->void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not await wait_for(func():return not game.loading_active,45):failures+=1;print("FAIL world load");await finish();return
	if not await wait_for(func():return game.world_vehicle.scene_ready()):failures+=1;print("FAIL vehicle resource");await finish();return
	game.fly=false;game._clear_motion();foreground()
	var base:Vector3=game.player.position
	for offset:Vector3 in [Vector3(0,0,-7),Vector3(7,0,0),Vector3(-7,0,0),Vector3(0,0,7)]:
		var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(base+offset+Vector3.UP*8,base+offset-Vector3.UP*12,1))
		if hit.is_empty():continue
		game.camera.look_at(hit.position);game.world_vehicle.spawn(game)
		if is_instance_valid(game.world_vehicle.car):break
	if not is_instance_valid(game.world_vehicle.car):failures+=1;print("FAIL placement");await finish();return
	var pose:Transform3D=game.world_vehicle.car.transform
	observer=Camera3D.new();root.add_child(observer)
	for speed:float in [0.0,.3,3.0]:
		for repeat:int in 3:await run_case(pose,speed,repeat)
	await finish()
