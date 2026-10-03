# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var terrain=load("res://addons/volumetric_terrain/terrain_stream.gd").new()
	terrain.planner=ClassDB.instantiate("NativeTerrainPlanner");terrain.world_ready=true
	var car=load("res://vehicle_demo/scenes/car.tscn").instantiate()
	root.add_child(car);car.set_physics_process(false)
	car.position=Vector3(14,50,14);car.linear_velocity=Vector3(60,0,0)
	check(car.bind_streamed_world(terrain),"vehicle binds terrain streaming provider")
	terrain.active_leaves[Vector2i(0,0)]=true
	check(not car.streaming.update(car,car.driving_policy,1.0/120) and car.freeze,"missing neighbor holds vehicle before movement")
	var held: Vector3=car.position
	for tick in 4: await physics_frame
	check(car.position==held,"held body does not drift during physics steps")
	check(terrain.travel_velocity==Vector3(60,0,0),"loading retains travel direction while held")
	check(not car.bind_streamed_world(terrain),"rebinding cannot discard held momentum")
	for z in 2:
		for x in 2: terrain.active_leaves[Vector2i(x,z)]=true
	check(car.streaming.update(car,car.driving_policy,1.0/120) and not car.freeze and car.linear_velocity==Vector3(60,0,0),"published region releases hold and restores velocity")
	car._spawn_transform=car.global_transform
	terrain.world_ready=false;car.streaming.update(car,car.driving_policy,1.0/120)
	car.reset_vehicle()
	terrain.world_ready=true;car.streaming.update(car,car.driving_policy,1.0/120)
	check(not car.freeze and car.linear_velocity==Vector3.ZERO and car._drive_speed==0,"reset while held discards old momentum")
	car.linear_velocity=Vector3(40,0,0);car._drive_speed=40
	var before_reload: Vector3=car.position
	terrain.reload_started.emit();terrain.world_ready=false
	check(car.freeze and car.position==before_reload and car._drive_speed==0,"reload holds without teleporting and clears driving speed")
	terrain.world_ready=true;car.streaming.update(car,car.driving_policy,1.0/120)
	check(not car.freeze and car.linear_velocity==Vector3.ZERO,"reload resumes at rest")
	car.linear_velocity=Vector3(20,0,0);terrain.world_ready=false
	var key:=InputEventKey.new();key.keycode=KEY_R;key.physical_keycode=KEY_R;key.pressed=true
	Input.parse_input_event(key);Input.flush_buffered_events();car._physics_process(1.0/120)
	var released:=InputEventKey.new();released.keycode=KEY_R;released.physical_keycode=KEY_R;released.pressed=false
	Input.parse_input_event(released);Input.flush_buffered_events()
	terrain.world_ready=true;car.streaming.update(car,car.driving_policy,1.0/120)
	check(car.linear_velocity==Vector3.ZERO,"reset key remains usable while streaming holds physics")
	car.freeze=true;terrain.world_ready=false
	car.streaming.update(car,car.driving_policy,1.0/120)
	terrain.world_ready=true;car.streaming.update(car,car.driving_policy,1.0/120)
	check(car.freeze,"streaming does not release an externally frozen vehicle")
	car.freeze=false
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var vegetation=load("res://addons/vegetation/vegetation_world.gd").new();root.add_child(vegetation)
	vegetation.ready_to_render=true
	check(vegetation.enable_trunk_collision() and car.streaming.bind_vegetation(vegetation),"vehicle binds actual native trunk provider")
	var trees: Array[Transform3D]=[Transform3D(Basis.IDENTITY,car.position+Vector3(2,0,0))]
	check(vegetation.upsert_chunk("near",PackedInt64Array([1]),trees),"nearby trunk authored before collider admission")
	vegetation.trunk_collision.set_collision_focus(car.position)
	car.linear_velocity=Vector3(10,0,0)
	check(not car.streaming.update(car,car.driving_policy,1.0/120) and car.freeze,"unpublished trunk collision holds vehicle")
	check(not car.streaming.bind_vegetation(vegetation),"held vehicle rejects provider rebinding")
	for tick in 4: await physics_frame
	check(car.streaming.update(car,car.driving_policy,1.0/120) and not car.freeze and car.linear_velocity==Vector3(10,0,0),"native trunk publication resumes saved motion")
	trees[0].origin+=Vector3(.5,0,0)
	check(vegetation.upsert_chunk("near",PackedInt64Array([1]),trees) and not car.streaming.update(car,car.driving_policy,1.0/120),"moving a tree invalidates stale collider readiness")
	for tick in 4: await physics_frame
	check(car.streaming.update(car,car.driving_policy,1.0/120),"updated trunk collider resumes travel")
	vegetation.remove_chunk("near")
	check(car.streaming.update(car,car.driving_policy,1.0/120),"removed tree does not leave a readiness hold")
	vegetation.free()
	check(not car.streaming.update(car,car.driving_policy,1.0/120) and car.freeze,"lost required vegetation provider fails closed")
	terrain.free()
	check(not car.streaming.update(car,car.driving_policy,1.0/120) and car.freeze,"lost terrain provider fails closed")
	car.free();quit(0 if failures==0 else 1)
