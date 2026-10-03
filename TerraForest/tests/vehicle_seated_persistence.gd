# SPDX-License-Identifier: 0BSD
extends SceneTree
var game: Node
var slot: String="seated_vehicle_%d" % OS.get_process_id()
var messages: Array[String]=[]
func _initialize() -> void: call_deferred("run")
func open_world() -> bool:
	game=load("res://demo/world.tscn").instantiate()
	game.terrain.save_slot=slot;game.terrain.backend.disk_cache.enabled=false
	root.add_child(game)
	game.terrain.message_changed.connect(func(message: String): messages.append(message))
	var deadline:=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	return not game.loading_active
func close_world() -> void:
	# Do not let shutdown overwrite the F5 snapshot under test.
	game.terrain.backend.temporary=true
	game.terrain.shutdown();game.free()
func finish(ok: bool,reason: String) -> void:
	print(("PASS " if ok else "FAIL ")+reason)
	if is_instance_valid(game): close_world()
	var path:=ProjectSettings.globalize_path("user://worlds/"+slot+".trw")
	for suffix in ["",".bak",".lock"]: DirAccess.remove_absolute(path+suffix)
	quit(0 if ok else 1)
func run() -> void:
	if not await open_world(): finish(false,"initial world startup");return
	game.fly=false;game._clear_motion()
	var base: Vector3=game.player.position
	for offset in [Vector3(0,0,-7),Vector3(7,0,0),Vector3(-7,0,0),Vector3(0,0,7)]:
		var ray:=PhysicsRayQueryParameters3D.create(base+offset+Vector3.UP*8,base+offset-Vector3.UP*12,1)
		var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty(): continue
		game.camera.look_at(hit.position);game.world_vehicle.spawn(game)
		if is_instance_valid(game.world_vehicle.car): break
	if not is_instance_valid(game.world_vehicle.car): finish(false,"vehicle placement");return
	var car=game.world_vehicle.car
	game.player.position=car.position+Vector3.RIGHT*2.8
	if not game.world_vehicle.enter(game): finish(false,"enter vehicle");return
	# Park the occupied vehicle to make asynchronous disk capture deterministic.
	car.freeze=true;car.set_physics_process(false)
	var player_data: PackedByteArray=game._capture_player_pose()
	var expected_player: Dictionary=game.player_pose.decode(player_data)
	var expected_car: Transform3D=car.transform
	if not expected_player.get("ok",false) or not expected_player.has("position"): finish(false,"seated player capture");return
	messages.clear();game.app_focused=true
	var key:=InputEventKey.new();key.physical_keycode=KEY_F5;key.pressed=true
	game._unhandled_input(key)
	var deadline:=Time.get_ticks_msec()+15000
	while not messages.any(func(m):return m.begins_with("World saved and verified")) and Time.get_ticks_msec()<deadline: await process_frame
	if not messages.any(func(m):return m.begins_with("World saved and verified")): finish(false,"F5 seated save publication");return
	print("PASS F5 published compound save while still seated: ",game.world_vehicle.driving)
	close_world()
	if not await open_world(): finish(false,"saved world startup");return
	var restored_car=game.world_vehicle.car
	var passed: bool=is_instance_valid(restored_car) and restored_car.transform.is_equal_approx(expected_car) and restored_car.freeze and not game.world_vehicle.driving
	passed=passed and game.player_pose.decode(game._saved_pose).get("position",Vector3.INF).is_equal_approx(expected_player.position)
	passed=passed and game.player.position.distance_to(expected_player.position)<1 and game.player.position.distance_to(restored_car.position)<4
	print("SEATED_DISK_RESTORE ",{"passed":passed,"expected_player":expected_player.position,"actual_player":game.player.position,"parked_car":expected_car.origin})
	finish(passed,"new world restores player beside parked vehicle")
