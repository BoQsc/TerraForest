# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var folder:="res://reports/px9_locomotion"
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
	var actor:=CharacterBody3D.new();stage.add_child(actor);human.body=actor
	var shape:=CollisionShape3D.new();shape.shape=CapsuleShape3D.new();actor.add_child(shape);actor.position.y=1
	var floor_body:=StaticBody3D.new();stage.add_child(floor_body)
	var floor_shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(1000,1,1000);floor_shape.shape=box;floor_shape.position.y=-.5;floor_body.add_child(floor_shape)
	var empty_mode:= "--empty" in OS.get_cmdline_user_args()
	human.handgun_empty=empty_mode;human.px9.request("idle_empty" if empty_mode else "idle");human.action_remaining=0
	var weapon_skeleton:Skeleton3D=human.px9.item.find_children("*","Skeleton3D",true,false)[0]
	var slide_position:=weapon_skeleton.get_bone_pose_position(weapon_skeleton.find_bone("slide"))
	var previous:="";var jump_count:=0;var failures:=0;var held_frames:=0;var landings:=0;var was_airborne:=false
	var skeleton:Skeleton3D=human.model.find_children("*","Skeleton3D",true,false)[0]
	var baseline:={}
	for bone:String in ["Root","Hips"]:baseline[bone]=skeleton.get_bone_pose(skeleton.find_bone(bone))
	for frame in 400:
		await physics_frame
		actor.velocity.x=9.9 if frame>=35 else (5.5 if frame>=15 else 0)
		actor.velocity.y-=(20.0 if frame<160 else 8.0)/60
		if frame==45:actor.velocity.y=8
		if frame==160:actor.velocity.y=12
		actor.move_and_slide()
		human._process(1.0/60);split.sync()
		for bone:String in baseline:
			if not skeleton.get_bone_pose(skeleton.find_bone(bone)).is_equal_approx(baseline[bone]):failures+=1
		if empty_mode and weapon_skeleton.get_bone_pose_position(weapon_skeleton.find_bone("slide")).distance_to(slide_position)>.0001:failures+=1
		var action:String=String(human.px9.motion.current_action).trim_suffix("_empty")
		if not actor.is_on_floor() and action!="jump":failures+=1
		if actor.is_on_floor() and frame>=20 and frame<35 and action!="walk":failures+=1
		if empty_mode and not String(human.px9.motion.current_action).ends_with("_empty"):failures+=1
		if was_airborne and actor.is_on_floor():
			landings+=1
			if action!="run":failures+=1
		was_airborne=not actor.is_on_floor()
		if action=="jump" and not human.px9.motion.active:held_frames+=1
		if action!=previous or frame in [68,71,250]:
			print("MOTION frame=",frame," action=",action," grounded=",actor.is_on_floor()," vy=",actor.velocity.y)
			if action=="jump" and previous!="jump":jump_count+=1
			title.text="PX9 · frame %d · %s · vertical %.2f"%[frame,action,actor.velocity.y]
			if DisplayServer.get_name()!="headless":
				await process_frame;await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(folder.path_join("motion_%03d.png"%frame))
		previous=action
	if jump_count!=2 or landings!=2 or held_frames<60:failures+=1
	print("PX9_LOCOMOTION jump starts=",jump_count," landings=",landings," held_frames=",held_frames," failures=",failures)
	split.dispose();stage.free();title.free();await process_frame;quit(1 if failures else 0)
