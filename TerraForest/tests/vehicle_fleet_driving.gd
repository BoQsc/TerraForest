# SPDX-License-Identifier: 0BSD
extends "res://tests/settlement_driving.gd"
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	game.terrain.backend.disable_snapshot_writes();game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false
	var session=game.world_vehicle
	check(session.fleet_enabled,"main world fleet enabled")
	if not session.fleet_enabled:game.terrain.shutdown();game.free();quit(1);return
	session.restore_snapshot(PackedByteArray())
	var ends: PackedVector3Array=game.road_palette.prepared_streets[0].ends
	var direction: Vector3=(ends[1]-ends[0]).normalized()
	var start: Vector3=ends[0]+direction*5
	var heading:=Basis(Vector3.UP,atan2(direction.x,direction.z))
	game.terrain.focus=start;game.player.position=start+Vector3.UP*3
	var first: int=session.fleet.spawn(Transform3D(heading,start+Vector3.UP*0.85))
	var second: int=session.fleet.spawn(Transform3D(heading,start+direction*12+Vector3.UP*0.85))
	deadline=Time.get_ticks_msec()+20000
	while session.activation.residents.size()<2 and Time.get_ticks_msec()<deadline:await process_frame
	check(session.activation.residents.size()==2,"normal world update admits both parked vehicles")
	if session.activation.residents.size()!=2:game.terrain.shutdown();game.free();quit(1);return
	var car: RigidBody3D=session.activation.residents[first]
	var parked: RigidBody3D=session.activation.residents[second]
	var parked_pose: Transform3D=parked.global_transform
	game.player.position=car.position+car.global_basis.x*2.8;game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	check(session.enter(game) and session.car_identity==first,"enter first fleet vehicle")
	game.set_physics_process(true)
	for tick in 60:await physics_frame
	var initial: Vector3=car.position
	var contact:=false;var held:=0;var max_speed:=0.0;var furthest:=0.0;var rows: Array=[]
	for tick in 480:
		game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		key_state(KEY_W,true);Input.flush_buffered_events();await physics_frame
		contact=contact or car.get_colliding_bodies().has(parked)
		if car.streaming.waiting:held+=1
		max_speed=maxf(max_speed,car.speed_kph);furthest=maxf(furthest,(car.position-initial).dot(direction))
		if tick%30==0:rows.append({"position":car.position,"speed_kph":car.speed_kph,"contact":contact})
		if contact:break
	key_state(KEY_W,false);Input.flush_buffered_events()
	check(contact,"driven chassis reports contact with parked vehicle")
	check(furthest>3 and (parked.position-car.position).dot(direction)>1.5,"car approaches without passing through parked chassis")
	check(held==0,"loaded two-car route has no collision-readiness holds")
	for tick in 240:
		game.app_focused=true;key_state(KEY_SPACE,true);Input.flush_buffered_events();await physics_frame
		if car.linear_velocity.length()<0.15:break
	key_state(KEY_SPACE,false);Input.flush_buffered_events()
	check(car.linear_velocity.length()<0.15,"handbrake stops driver after contact")
	check(parked.global_transform.is_equal_approx(parked_pose) and parked.freeze and not parked.is_physics_processing(),"unoccupied vehicle stays parked without active simulation")
	var message: String=session.exit_vehicle(game)
	check(not session.driving and game.player.collision_mask!=0,"safe exit beside two vehicles: "+message)
	var snapshot: PackedByteArray=session.capture_snapshot()
	var decoded: Dictionary=session.storage.decode_fleet(snapshot)
	check(decoded.ok and decoded.records.size()==2 and session.fleet.get_record(first).pose.is_equal_approx(car.global_transform),"capture retains moved and parked vehicle poses")
	game.set_physics_process(false);game.camera.global_position=car.position-direction*8+Vector3.UP*6;game.camera.look_at(parked.position)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports/vehicle_fleet_driving")
	root.get_texture().get_image().save_png("res://reports/vehicle_fleet_driving/world.png")
	var file:=FileAccess.open("res://reports/vehicle_fleet_driving/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"distance":furthest,"max_speed_kph":max_speed,"held_ticks":held,"contact":contact,"stop_speed_mps":car.linear_velocity.length(),"rows":rows},"  "));file.close()
	game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
