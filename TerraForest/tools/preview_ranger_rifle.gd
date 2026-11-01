# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var folder:="res://reports/ranger_preview"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ranger-output="):folder=arg.trim_prefix("--ranger-output=")
	DirAccess.make_dir_recursive_absolute(folder)
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("263338")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.8;stage.add_child(environment)
	var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-45,-30,0);key.light_energy=1.7;stage.add_child(key)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-20,140,0);fill.light_energy=.7;stage.add_child(fill)
	var camera:=Camera3D.new();camera.fov=75;camera.near=.04;camera.position=Vector3(0,1.65,0);camera.current=true;stage.add_child(camera)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools)
	var human:Node3D=tools.human;tools.set_process(false);human.set_process(false);tools.equip(8)
	var title:=Label.new();title.position=Vector2(40,32);title.add_theme_font_size_override("font_size",30);root.add_child(title)
	for phase:Dictionary in [{"name":"idle","clip":"FP_Rifle_Idle","time":0.0},{"name":"aim","clip":"FP_Rifle_Aim","time":.9},{"name":"fire","clip":"FP_Ranger_HipFire","time":.025},{"name":"reload_out","clip":"FP_Rifle_Reload","time":1.2},{"name":"reload_in","clip":"FP_Rifle_Reload","time":2.0}]:
		title.text="Ranger assault rifle · "+phase.name.replace("_"," ")
		human.animation_player.play(human.clips[phase.clip],0);human.animation_player.seek(phase.time,true);human.animation_player.pause();human.animation_player.advance(0)
		human.model.position=Vector3(0,-.030,-.23) if phase.name=="aim" else Vector3.ZERO
		human.rifle_flash.visible=false
		if phase.name=="aim":
			var sk:Skeleton3D=human.model.find_children("*","Skeleton3D",true,false)[0]
			var t:Transform3D=camera.global_transform.affine_inverse()*sk.global_transform*sk.get_bone_global_pose(sk.find_bone("Weapon_Carbine"))*sk.get_bone_global_rest(sk.find_bone("Weapon_Carbine")).affine_inverse()
			print("RANGER_SIGHTS rear=",t*Vector3(0,.197,-.017)," front=",t*Vector3(0,.2,.36)," stock=",t*Vector3(0,.184,-.321))
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(phase.name+".png"))
	human.set_third_person(true);tools.reparent(stage);tools.transform=Transform3D.IDENTITY;human.position=Vector3.ZERO;human.rotation=Vector3.ZERO
	camera.position=Vector3(-1.8,1.7,2.2);camera.look_at(Vector3(0,1.2,.1))
	human.animation_player.play(human.clips["Rifle_Idle"],0);human.animation_player.seek(0,true);human.animation_player.pause();human.animation_player.advance(0);human.rifle_flash.visible=false
	title.text="Ranger assault rifle · third-person grip"
	await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("third_person.png"))
	tools.hide()
	stage.add_child(preload("res://addons/characters/runtime/assets/Ranger.body.glb").instantiate())
	stage.add_child(preload("res://addons/characters/runtime/assets/Ranger.magazine.glb").instantiate())
	camera.position=Vector3(-.85,.37,.8);camera.look_at(Vector3(0,.065,.12));camera.fov=48
	title.text="Ranger AR · original assault rifle"
	await process_frame;await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("model.png"))
	stage.free();title.free();await process_frame;print("RANGER_PREVIEW complete");quit()
