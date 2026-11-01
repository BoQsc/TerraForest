# SPDX-License-Identifier: 0BSD
extends SceneTree
var folder:="res://reports/zombie_sleepers/review_v1"
var missing_part:=""
var motion:=false

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()

func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):folder=argument.trim_prefix("--review-output=")
		if argument.begins_with("--review-missing="):missing_part=argument.trim_prefix("--review-missing=")
		if argument=="--review-motion":motion=true
	DirAccess.make_dir_recursive_absolute(folder)
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("1b252e")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65
	stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);light.light_energy=1.5;light.shadow_enabled=true;stage.add_child(light)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(60,60);floor.mesh=plane
	var material:=StandardMaterial3D.new();material.albedo_color=Color("4e5c60");material.roughness=1;floor.material_override=material;stage.add_child(floor)
	var library:AnimationLibrary=load("res://addons/characters/runtime/assets/Zombie.sleepers.res")
	var zombies:Array=[]
	for index in 4:
		var zombie=preload("res://addons/characters/runtime/zombie.gd").new()
		if index>0:zombie.geometry_template=zombies[0].anatomy
		stage.add_child(zombie);zombie.set_physics_process(false);zombie.set_behavior(false)
		zombie.animation_player.add_animation_library("sleepers",library)
		if not missing_part.is_empty():zombie.sever_limb(missing_part,Vector3.ZERO,false)
		zombie.position.x=(index-1.5)*1.95
		zombies.append(zombie)
	var camera:=Camera3D.new();camera.fov=50;camera.current=true;stage.add_child(camera)
	camera.position=Vector3(0,2.1,5.9);camera.look_at(Vector3(0,.75,0))
	var title:=Label.new();title.position=Vector2(40,35);title.add_theme_font_size_override("font_size",30);root.add_child(title)
	var note:=Label.new();note.position=Vector2(40,78);note.add_theme_font_size_override("font_size",20);note.text="Start  |  30%  |  65%  |  complete   -   pose review, not gameplay approval";root.add_child(note)
	if motion:
		DirAccess.make_dir_recursive_absolute(folder.path_join("frames"))
		for index in zombies.size():
			zombies[index].visible=index<2
			zombies[index].position.x=(index-.5)*2.6
			zombies[index].rotation.y=0 if index==0 else PI*.5
		camera.position=Vector3(0,1.8,4.2);camera.look_at(Vector3(0,.8,0))
		note.text="Normal speed / front + side / original runtime skin / animation review only"
		var captured:=0
		for clip:String in library.get_animation_list():
			if not clip.begins_with("Zombie_Wake_"):continue
			var animation:Animation=library.get_animation(clip)
			for zombie in zombies:zombie.play_clip(clip)
			for frame in int(round(animation.length*30))+24:
				var elapsed:=clampf((frame-12)/30.0,0,animation.length)
				for zombie in zombies:
					zombie.animation_player.seek(elapsed,true);zombie.animation_player.advance(0)
				title.text=clip+"   %.2f s"%elapsed
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder.path_join("frames/%04d.png"%captured))
				captured+=1
		stage.free();title.free();note.free();await process_frame
		print("ZOMBIE_SLEEPERS_REVIEW motion_frames=",captured);quit();return
	for clip:String in library.get_animation_list():
		if missing_part in ["shin_l","thigh_r"] and clip.begins_with("Zombie_Wake_") and not clip.ends_with("_Crawl"):continue
		for view in 2:
			for index in zombies.size():
				var zombie:Node3D=zombies[index]
				zombie.rotation.y=0 if view==0 else PI*.5
				zombie.play_clip(clip)
				var animation:Animation=library.get_animation(clip)
				zombie.animation_player.seek(animation.length*[0,.3,.65,1][index],true)
				zombie.animation_player.advance(0)
				zombie.skeleton.force_update_all_bone_transforms()
			title.text=clip+(" - front" if view==0 else " - side")+(" - missing "+missing_part if not missing_part.is_empty() else "")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join(clip+("_front.png" if view==0 else "_side.png")))
	stage.free();title.free();note.free();await process_frame
	print("ZOMBIE_SLEEPERS_REVIEW missing=",missing_part)
	quit()
