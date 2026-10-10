# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	game.terrain.backend.disable_snapshot_writes();game.set_process(false);game.set_physics_process(false);game._clear_motion()
	var session=game.world_vehicle;var activation=session.activation
	check(session.fleet_enabled and activation!=null,"fleet opt-in enabled in main world")
	check(session.restore_snapshot(PackedByteArray()),"reset disposable in-memory vehicle state")
	var ends: PackedVector3Array=game.road_palette.prepared_streets[0].ends
	var direction: Vector3=(ends[1]-ends[0]).normalized()
	var start: Vector3=ends[0]+direction*3+Vector3.UP*0.85
	game.terrain.focus=start;game.player.position=start+Vector3(0,3,8)
	for i in 5:session.fleet.spawn(Transform3D(Basis.IDENTITY,start+direction*i*6))
	deadline=Time.get_ticks_msec()+15000
	while not session.scene_ready() and Time.get_ticks_msec()<deadline:await process_frame
	game.terrain.focus=start-direction*90;activation.timer=0;activation.update(game,0.2)
	check(activation.bodies.size()==1 and activation.parked_view==null,"cold template creation yields before parked batch setup")
	await process_frame;activation.timer=0;activation.update(game,0.2)
	check(activation.residents.is_empty() and activation.parked_status.get("rendered",0)==5,"distant-only saved fleet renders without driving-body admission")
	game.terrain.focus=start
	deadline=Time.get_ticks_msec()+20000
	while activation.residents.size()<4 and Time.get_ticks_msec()<deadline:
		await process_frame;activation.timer=0;activation.update(game,0.2)
	check(activation.residents.size()==4 and activation.bodies.size()==4,"five nearby records use at most four live bodies")
	if activation.residents.size()!=4:game.terrain.shutdown();game.free();quit(1);return
	var nodes: Array=[]
	for body in activation.bodies:nodes.append(body.get_instance_id())
	var wheel_clear:=true
	for body in activation.bodies:
		for wheel in body.wheel_rays:
			wheel.force_raycast_update();wheel_clear=wheel_clear and wheel.get_collider()!=body
	check(wheel_clear,"fleet wheel rays exclude their own chassis")
	check(activation.parked_view!=null and activation.parked_status.ids.has(5),"fifth vehicle has native parked representation: "+str(activation.parked_status))
	var fifth: Vector3=session.fleet.get_record(5).pose.origin
	await physics_frame;await physics_frame
	var ray:=PhysicsRayQueryParameters3D.create(fifth+Vector3.UP*4,fifth-Vector3.UP*2,4)
	var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider==activation.parked_view,"fifth parked vehicle has static chassis collision")
	activation.select_for_entry(fifth+Vector3.RIGHT*2.8)
	check(session.car_identity==5 and activation.residents.has(5) and not activation.parked_status.ids.has(5),"parked fifth identity promotes without duplicate visual")
	await physics_frame;await physics_frame
	hit=game.get_world_3d().direct_space_state.intersect_ray(ray)
	check(not hit.is_empty() and hit.collider==session.car,"promotion replaces parked collider with live chassis")
	var captured: PackedByteArray=session.capture_snapshot()
	check(session.fleet.statistics().records==5,"unadmitted fifth identity remains stored")
	game.terrain.focus=start+Vector3(800,0,0);activation.timer=0;activation.update(game,0.2)
	var retired: bool=activation.residents.is_empty()
	for body in activation.bodies:retired=retired and not body.visible and body.collision_layer==0 and not body.is_physics_processing()
	check(retired,"departure hides and disables every unoccupied body")
	check(activation.place(game,Transform3D(Basis.IDENTITY,start)).begins_with("Another saved vehicle") and session.fleet.statistics().records==5,"inactive saved vehicle still blocks duplicate placement")
	game.terrain.focus=start
	for i in 4:activation.timer=0;activation.update(game,0.2);await physics_frame
	var reused: bool=activation.residents.size()==4
	for body in activation.bodies:reused=reused and nodes.has(body.get_instance_id())
	check(reused,"return reuses the fixed four bodies")
	var target: RigidBody3D=activation.residents[2]
	game.player.global_position=target.global_position+Vector3.RIGHT*2.8
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	check(session.enter(game) and session.car_identity==2,"entry selects nearby vehicle identity2")
	if session.driving:
		session.car.freeze=true;session.car.set_physics_process(false)
		game.terrain.focus=start+Vector3(800,0,0);activation.timer=0;activation.update(game,0.2)
		check(activation.residents.has(2) and session.car==target,"occupied body remains pinned outside selection radius")
	else:check(false,"occupied body remains pinned outside selection radius")
	check(session.restore_snapshot(captured) and not session.driving and activation.residents.is_empty(),"reload retires old residency and releases driving state")
	check(session.fleet.statistics().records==5,"reload preserves all five vehicle identities")
	game.terrain.focus=start
	for i in 4:activation.timer=0;activation.update(game,0.2);await physics_frame
	game.camera.global_position=start-direction*12+Vector3.UP*8;game.camera.look_at(start+direction*10)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports/vehicle_fleet_activation")
	root.get_texture().get_image().save_png("res://reports/vehicle_fleet_activation/world.png")
	var file:=FileAccess.open("res://reports/vehicle_fleet_activation/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"allocated_bodies":activation.bodies.size(),"records":session.fleet.statistics().records}));file.close()
	game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
