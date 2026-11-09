# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var folder:="res://reports/px9_preview"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--px9-output="):folder=arg.trim_prefix("--px9-output=")
	DirAccess.make_dir_recursive_absolute(folder)
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("263338")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.8;stage.add_child(environment)
	var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-45,-30,0);key.light_energy=1.7;stage.add_child(key)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-20,140,0);fill.light_energy=.7;stage.add_child(fill)
	var camera:=Camera3D.new();camera.fov=75;camera.near=.04;camera.position=Vector3(0,1.65,0);camera.current=true;stage.add_child(camera)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools)
	var human:Node3D=tools.human;tools.set_process(false);human.set_process(false);var split=preload("res://addons/player_runtime/first_person_meshes.gd").new();split.prepare(tools);split.set_active(true);tools.equip(9)
	var title:=Label.new();title.position=Vector2(40,32);title.add_theme_font_size_override("font_size",30);root.add_child(title)
	human._process(1)
	for phase:Dictionary in [{"name":"idle","action":"idle","time":0.0},{"name":"aim","action":"aim_idle","time":.2},{"name":"fire","action":"fire","time":.08},{"name":"reload","action":"reload_empty","time":.76},{"name":"rack","action":"rack","time":.73}]:
		title.text="PX9 Eclipse · "+phase.name
		human.px9.request(phase.action);human.px9.motion.seek_seconds(phase.time)
		if phase.name=="idle":
			human.handgun_empty=false
			for frame in 180:human._process(1.0/60)
		split.sync()
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(phase.name+".png"))
	split.dispose()
	stage.free();title.free();await process_frame;print("PX9_PREVIEW complete");quit()
