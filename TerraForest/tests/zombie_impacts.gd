# SPDX-License-Identifier: 0BSD
extends SceneTree
var folder:=""
var checks:=0
var failures:=0
var samples:Array=[]

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):folder=argument.trim_prefix("--review-output=")
	run.call_deferred()

func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("1b252e")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65
	stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);light.light_energy=1.5;light.shadow_enabled=true;stage.add_child(light)
	var floor:=StaticBody3D.new();stage.add_child(floor)
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(30,.2,30);collider.shape=shape;collider.position.y=-.1;floor.add_child(collider)
	var view:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(30,30);view.mesh=plane;floor.add_child(view)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("4e5c60");material.roughness=1;view.material_override=material
	var camera:=Camera3D.new();camera.fov=48;camera.position=Vector3(0,2.1,7.8);stage.add_child(camera);camera.look_at(Vector3(0,.9,0));camera.make_current()
	var title:=Label.new();title.position=Vector2(40,35);title.add_theme_font_size_override("font_size",28);root.add_child(title)
	var caption:=Label.new();caption.position=Vector2(40,80);caption.text="Front / side / rear · actual animated model · localized firearm impulse and recovery";root.add_child(caption)
	for variant:String in ["standing","missing_forearm","sleeper"]:
		var actors:Array=[]
		for index in 3:
			var actor:=preload("res://addons/characters/runtime/zombie.gd").new()
			if not actors.is_empty():actor.geometry_template=actors[0].anatomy
			stage.add_child(actor);actor.position=Vector3((index-1)*2.1,0,0);actor.rotation.y=index*PI*.5;actor.set_behavior(false)
			if variant=="missing_forearm":actor.sever_limb("forearm_l",Vector3.ZERO,false)
			actors.append(actor)
		for tick in 12:await physics_frame
		if variant=="sleeper":
			for actor:CharacterBody3D in actors:check(actor.begin_sleep(1),"live seated sleeper admits before firearm reaction");actor.set_behavior(true)
		for tick in 6:await physics_frame
		title.text=variant+" · before impact";await photograph(variant+"_before")
		for actor:CharacterBody3D in actors:
			var bone:int=actor.skeleton.find_bone(actor.PARTS.torso.bone)
			var contact:Vector3=(actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(bone)).origin+actor.global_basis*Vector3(.18,.2,0)
			var before:float=actor.health
			actor.receive_hit("torso",20,contact,actor.global_basis*Vector3(0,0,-2),false,"firearm")
			check(actor.alive and actor.health<before and actor.hit_reaction.is_active(),variant+" firearm hit damages health and activates native deflection")
		for tick in 180:
			await physics_frame
			if tick in [5,17,59,119]:
				title.text=variant+" · %.2f s after impact"%((tick+1)/60.0)
				for actor:CharacterBody3D in actors:samples.append({"variant":variant,"frame":tick,"angle":actor.rotation.y,"reaction":actor.hit_reaction.statistics(),"position":actor.position,"alive":actor.alive,"state":actor.state})
				await photograph(variant+"_%03d"%(tick+1))
		for actor:CharacterBody3D in actors:
			check(actor.alive and not actor.hit_reaction.is_active() and actor.hit_reaction.statistics().energy==0,variant+" recovers without residual native forces")
			actor.receive_hit("torso",1000,actor.position+Vector3.UP,Vector3(0,0,-1),false,"firearm")
			check(not actor.alive and not actor.hit_reaction.is_active(),"death clears hit spring before articulated ragdoll")
		for tick in 90:await physics_frame
		title.text=variant+" · death transfers to ragdoll";await photograph(variant+"_death")
		for actor:Node in actors:actor.free()
		await process_frame
	FileAccess.open(folder.path_join("samples.json"),FileAccess.WRITE).store_string(JSON.stringify(samples,"  "))
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"review never captures the pointer")
	stage.free();title.free();caption.free();await process_frame
	print("ZOMBIE_SLEEPERS_IMPACTS checks=",checks," failures=",failures);quit(1 if failures else 0)

func photograph(label:String)->void:
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(label+".png"))
