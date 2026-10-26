# SPDX-License-Identifier: 0BSD
extends "res://tests/vehicle_exit_world_diagnosis.gd"
var checks:=0
func check(ok:bool,label:String)->bool:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok
func planar(value:Vector3)->Vector3:
	value.y=0;return value.normalized()
func finish()->void:
	var file:=FileAccess.open("res://reports/vehicle_exit_facing_world.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases},"  "));file.close()
	if is_instance_valid(game):game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
	await process_frame;print("VEHICLE_EXIT_FACING_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
func run()->void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"temporary world loads"):await finish();return
	if not check(await wait_for(func():return game.world_vehicle.scene_ready()),"vehicle resource loads"):await finish();return
	game.fly=false;game.needs_floor_spawn=false;game._clear_motion();foreground()
	game.player_view.set_enabled(false,false)
	var session:Node=game.world_vehicle
	session.spawn_requested(game)
	if not check(is_instance_valid(session.car),"vehicle installs"):await finish();return
	var car:RigidBody3D=session.car;var original:Transform3D=car.transform
	for third_person:bool in [false,true]:
		for heading:float in [0,90,180]:
			game.player_view.set_enabled(third_person,false)
			session.coasting.clear();car.restore_parked(original)
			game.yaw=.37;game.pitch=-.25;game.player.rotation=Vector3(0,game.yaw,0)
			game.camera.position=Vector3(0,1.68,0);game.camera.rotation=Vector3(game.pitch,0,0)
			game.player.position=car.position+Vector3.RIGHT*2.8;game.player.velocity=Vector3.ZERO
			for tick in 3:foreground();await physics_frame
			if not check(session.enter(game),"entry in selected player view"):await finish();return
			car.freeze=true;car.set_physics_process(false);car.rotation=Vector3(0,deg_to_rad(heading),0)
			for tick in 6:foreground();await physics_frame
			var expected:Vector3=planar(car.global_basis.z)
			foreground();var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=KEY_E;game._unhandled_input(event)
			if not check(not session.driving,"E accepts supported exit"):await finish();return
			check(planar(-game.player.global_basis.z).dot(expected)>.99999 and planar(-game.camera.global_basis.z).dot(expected)>.99999,"body and eye camera face current vehicle front")
			check(absf(wrapf(game.player.rotation.y-game.yaw,-PI,PI))<.00001 and absf(game.pitch+.25)<.00001,"input heading synchronized and pitch retained")
			var saved:Dictionary=game.player_pose.decode(game._capture_player_pose())
			check(saved.get("ok",false) and absf(wrapf(saved.yaw-game.yaw,-PI,PI))<.00001,"actual world save capture uses exit heading")
			game.player_view.update()
			check(game.player_view.active==third_person and (not third_person or (game.player_view.third_camera.current and game.tool_view.global_basis.z.dot(game.player.global_basis.z)>.99999)),"first/third-person presentation follows aligned player")
			if heading==90:
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://reports/vehicle_exit_facing_"+("third_person" if third_person else "first_person")+".png")
			var before_yaw:float=game.yaw;var before_pitch:float=game.pitch
			var mouse:=InputEventMouseMotion.new();mouse.relative=Vector2(4,2);game._unhandled_input(mouse)
			check(absf(wrapf(game.yaw-(before_yaw-.01),-PI,PI))<.00001 and absf(game.pitch-(before_pitch-.005))<.00001,"next actual mouse event continues without snap-back")
			cases.append({"vehicle_heading_degrees":heading,"third_person":third_person,"vehicle_front":expected,"player_forward_after_mouse":-game.player.global_basis.z,"yaw_before_mouse":before_yaw,"yaw_after_mouse":game.yaw,"saved_yaw":saved.get("yaw",INF)})
	await finish()
