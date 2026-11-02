# SPDX-License-Identifier: 0BSD
extends "res://tests/zombie_impacts.gd"
func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("293947");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_energy=.7;stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-30,0);light.light_energy=1.5;stage.add_child(light)
	var camera:=Camera3D.new();camera.fov=48;camera.position=Vector3(0,2.1,8);stage.add_child(camera);camera.look_at(Vector3(0,1,0));camera.make_current()
	var label:=Label.new();label.position=Vector2(28,25);label.add_theme_font_size_override("font_size",25);root.add_child(label)
	var actors:Array=[]
	for index in 3:
		var actor=preload("res://addons/characters/runtime/zombie.gd").new();stage.add_child(actor);actor.position=Vector3((index-1)*2,0,0);actor.rotation.y=index*PI*.5;actor.set_physics_process(false);actor.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL;actors.append(actor)
	var first:Node=actors[0]
	first.awareness_state="chase";check(first._standing_walk_clip()=="Zombie_Alert_Walk","pursuit selects authored aggressive upper body")
	first.awareness_state="wander";check(first._standing_walk_clip()=="Zombie_Walk_Drag_Right","unaware wandering retains relaxed drag walk")
	var maximum_error:=0.0
	for frame in 121:
		var original:Array=[]
		for name:String in ["Zombie_Walk_Drag_Right","Zombie_Alert_Walk"]:
			first.play_clip(name);first.animation_player.seek(frame/60.0,true);first.animation_player.advance(0)
			for bone_name:String in ["Hips","LeftUpLeg","LeftLeg","LeftFoot","RightUpLeg","RightLeg","RightFoot"]:
				var bone:int=first.skeleton.find_bone(bone_name);var pose:Transform3D=first.skeleton.get_bone_global_pose(bone)
				if name=="Zombie_Walk_Drag_Right":original.append(pose)
				else:
					var expected:Transform3D=original.pop_front();maximum_error=maxf(maximum_error,expected.origin.distance_to(pose.origin))
	check(maximum_error<.001,"all 121 frames retain planted hips/feet; maximum error="+str(maximum_error))
	for clip:String in ["Zombie_Walk_Drag_Right","Zombie_Alert_Walk"]:
		for frame in [0,30,60,90]:
			for actor:Node in actors:actor.play_clip(clip);actor.animation_player.seek(frame/60.0,true);actor.animation_player.advance(0)
			label.text="TERRAFOREST / "+clip+" / front · side · rear"
			await photograph(clip+"_%03d"%frame)
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"review never captures mouse")
	stage.free();label.free();print("ZOMBIE_ALERT checks=",checks," failures=",failures);quit(1 if failures else 0)
