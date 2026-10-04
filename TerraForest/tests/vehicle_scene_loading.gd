# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var adapter=load("res://addons/vehicle_runtime/world_vehicle.gd").new()
	var passed: bool=not adapter.scene_ready()
	var begin:=Time.get_ticks_usec()
	adapter.request_scene()
	var request_us:=Time.get_ticks_usec()-begin
	adapter.request_scene() # Repeated requests must retain the same resource job.
	var polls:=0
	var max_poll_us:=0
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		begin=Time.get_ticks_usec()
		var ready: bool=adapter.scene_ready()
		max_poll_us=maxi(max_poll_us,Time.get_ticks_usec()-begin)
		polls+=1
		if ready: break
		await process_frame
	passed=passed and adapter.scene_ready()
	var resource=adapter._vehicle_scene
	adapter.request_scene()
	passed=passed and resource==adapter._vehicle_scene
	if resource!=null:
		var car=resource.instantiate()
		passed=passed and car is RigidBody3D
		car.free()
	print("VEHICLE_SCENE_LOADING ",{"passed":passed,"request_us":request_us,"max_poll_us":max_poll_us,"polls":polls})
	adapter.free()
	quit(0 if passed else 1)
