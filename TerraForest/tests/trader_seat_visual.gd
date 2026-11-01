# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true);run.call_deferred()
func run()->void:
	var folder:="res://reports/trader_seats"
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--output="):folder=value.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(folder)
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("9cbac7");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.8;world.add_child(environment)
	var light:=DirectionalLight3D.new();world.add_child(light);light.rotation=Vector3(-.7,-.5,0)
	var car=preload("res://vehicle_demo/scenes/car.tscn").instantiate();world.add_child(car);car.freeze=true;car.set_physics_process(false)
	var seat=preload("res://addons/player_runtime/trader_seat.gd")
	seat.create(car,[{"item":301,"count":1},{"item":302,"count":1},{"item":303,"count":1}],true)
	seat.create(car,[],false)
	var camera:=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,.8,.72);camera.look_at(Vector3(0,.7,.1));camera.fov=110;camera.make_current()
	for frame in 20:await process_frame
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("interior.png"))
	camera.position=Vector3(3,1.8,3.3);camera.look_at(Vector3(0,.65,0));camera.fov=55
	for frame in 3:await process_frame
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("exterior.png"))
	print("TRADER_SEAT_VISUAL captured; visual acceptance requires image inspection")
	world.free();quit()
