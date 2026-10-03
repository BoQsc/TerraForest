# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var scene=load("res://vehicle_demo/main.tscn").instantiate();root.add_child(scene)
	var car=scene.get_node("Car")
	for tick in 120: await physics_frame
	var start: Vector3=car.global_position
	var input:=InputEventKey.new();input.keycode=KEY_W;input.physical_keycode=KEY_W;input.pressed=true;Input.parse_input_event(input)
	for tick in 240: await physics_frame
	input.pressed=false;Input.parse_input_event(input)
	var passed: bool=car.driving_policy!=null and car.body_mesh_count>0 and car.global_position.is_finite() and car.global_position.distance_to(start)>2 and car.speed_kph>5
	print("VEHICLE_SMOKE ",{"passed":passed,"distance":car.global_position.distance_to(start),"speed_kph":car.speed_kph,"loaded_wheels":car.loaded_wheels,"body_meshes":car.body_mesh_count,"physics_hz":Engine.physics_ticks_per_second})
	await process_frame;await RenderingServer.frame_post_draw
	var screenshot:=root.get_texture().get_image()
	scene.queue_free();await process_frame
	screenshot.save_png("res://reports/vehicle_demo.png")
	quit(0 if passed else 1)
