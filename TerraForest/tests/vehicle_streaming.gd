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
	car.freeze=true;terrain.world_ready=false
	car.streaming.update(car,car.driving_policy,1.0/120)
	terrain.world_ready=true;car.streaming.update(car,car.driving_policy,1.0/120)
	check(car.freeze,"streaming does not release an externally frozen vehicle")
	car.freeze=false;terrain.free()
	check(not car.streaming.update(car,car.driving_policy,1.0/120) and car.freeze,"lost terrain provider fails closed")
	car.free();quit(0 if failures==0 else 1)
