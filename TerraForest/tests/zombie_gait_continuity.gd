# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var stage:Node3D
var host:Node3D
var target:Node3D
var driving:=false
var rows:Array=[]
var camera:Camera3D
var folder:="res://reports/zombie_gait_continuity"

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func _initialize()->void:run.call_deferred()
func tick()->void:
	if driving:host.update(1./60.,target.global_position,true)
func ticks(count:int)->void:
	for frame in count:await physics_frame

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--gait-output="):folder=arg.trim_prefix("--gait-output=")
	DirAccess.make_dir_recursive_absolute(folder)
	stage=Node3D.new();root.add_child(stage)
	var floor_body:=StaticBody3D.new();stage.add_child(floor_body)
	var collision:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=Vector3(120,1,120);collision.shape=shape;collision.position.y=-.5;floor_body.add_child(collision)
	var floor_view:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(120,120);floor_view.mesh=plane;floor_body.add_child(floor_view)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("465349");floor_view.material_override=material
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-35,0);stage.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;stage.add_child(environment)
	camera=Camera3D.new();stage.add_child(camera);camera.current=true
	target=preload("res://addons/characters/runtime/zombie_target.gd").new();stage.add_child(target);target.position=Vector3(0,0,25)
	host=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(host);host.enabled=true;host.population_enabled=false;host.target=target;host.force_pursuit=true
	host.readiness=func(_bounds:AABB):return true
	physics_frame.connect(tick);await ticks(3)
	var zombie:CharacterBody3D=host.spawn_at(Vector3.ZERO)
	check(zombie!=null,"normal host admits continuity fixture")
	if zombie==null:quit(1);return
	check(host.configure_encounter(zombie,{"profile":"restless","ambusher":true}),"fixture uses the fast 1.98 m/s sleeper pursuit")
	zombie.set_physics_process(false)
	for name:String in ["Zombie_Walk_Drag_Right","Zombie_Alert_Walk"]:
		var animation:Animation=zombie.animation_player.get_animation(zombie._animation_key(name))
		check(animation.loop_mode==Animation.LOOP_LINEAR,name+" is configured to loop")
		animation.loop_mode=Animation.LOOP_NONE
		zombie._play_animation(name,true);zombie.animation_player.seek(0,true);zombie.animation_player.advance(0)
		var first:Array[Transform3D]=[]
		for bone in zombie.skeleton.get_bone_count():first.append(zombie.skeleton.get_bone_pose(bone))
		zombie.animation_player.seek(animation.length,true);zombie.animation_player.advance(0)
		var error:=0.0
		for bone in first.size():
			var pose:Transform3D=zombie.skeleton.get_bone_pose(bone)
			error=maxf(error,pose.origin.distance_to(first[bone].origin))
			for axis in 3:error=maxf(error,pose.basis[axis].distance_to(first[bone].basis[axis]))
		check(error<.0001,name+" authored end pose joins start; error="+str(error))
		animation.loop_mode=Animation.LOOP_LINEAR
	zombie._play_animation("Zombie_Walk_Drag_Right",true);zombie.animation_player.seek(.73,true);zombie.animation_player.advance(0)
	zombie._play_animation("Zombie_Walk_Drag_Right");zombie.animation_player.advance(0)
	check(absf(zombie.animation_player.current_animation_position-.73)<.001,"reapplying the same walk does not restart it")
	var feet:Array[Vector3]=[]
	for bone_name:String in ["Hips","LeftFoot","RightFoot"]:feet.append(zombie.skeleton.get_bone_global_pose(zombie.skeleton.find_bone(bone_name)).origin)
	zombie._play_animation("Zombie_Alert_Walk");zombie.animation_player.advance(0)
	check(absf(zombie.animation_player.current_animation_position-.73)<.001,"relaxed to alert walk keeps the shared foot phase")
	var foot_error:=0.0
	for index in 3:
		var name:String=["Hips","LeftFoot","RightFoot"][index]
		foot_error=maxf(foot_error,feet[index].distance_to(zombie.skeleton.get_bone_global_pose(zombie.skeleton.find_bone(name)).origin))
	check(foot_error<.001,"intent change preserves actual supporting hips and feet; error="+str(foot_error))
	zombie.animation_player.seek(1.41,true);zombie._play_animation("Zombie_Walk_Drag_Right");zombie.animation_player.advance(0)
	check(absf(zombie.animation_player.current_animation_position-1.41)<.001,"alert to relaxed walk keeps the shared foot phase")
	zombie.navigation_target=Vector3.INF
	zombie._tick_navigation(1./60.,Vector3(0,0,20),.6)
	var held:float=zombie.animation_player.current_animation_position
	for frame in 6:
		zombie.animation_player.advance(1./60.);zombie._tick_navigation(1./60.,Vector3(0,0,20),.6)
	check(zombie._current_clip.ends_with("Zombie_Walk_Drag_Right") and is_equal_approx(zombie.animation_player.current_animation_position,held) and zombie.velocity.length()<.001,"short missing-route interval stops motion and holds the gait cursor")
	for frame in 20:zombie._tick_navigation(1./60.,Vector3(0,0,20),.6)
	check(zombie._current_clip.ends_with("Zombie_Idle"),"longer route stop settles into idle")
	zombie._play_animation("Zombie_Alert_Walk",true);zombie.animation_player.advance(0)
	check(is_zero_approx(zombie.animation_player.current_animation_position),"explicit restart still resets a preview or action")
	zombie.set_physics_process(true);driving=true
	var previous_clip:="";var interruptions:=0;var walk_frames:=0
	for frame in 480:
		await ticks(1)
		if frame%90==0:target.position=Vector3(sin(frame*.02)*3,0,zombie.position.z+12)
		var current:String=zombie._current_clip
		if current.ends_with("Zombie_Idle") and previous_clip.ends_with("Zombie_Alert_Walk") and zombie._route_gait_pause<=.25:interruptions+=1
		if current.ends_with("Zombie_Alert_Walk"):walk_frames+=1
		rows.append({"frame":frame,"clip":current,"cursor":zombie.animation_player.current_animation_position,"speed_scale":zombie.animation_player.speed_scale,"state":zombie.state,"route":host.navigator.state(zombie.get_instance_id()),"position":zombie.position})
		previous_clip=current
		if DisplayServer.get_name()!="headless" and frame in [120,121,122,123,124,125,126,127,128,129,130,131]:
			camera.position=zombie.position+Vector3(3,1.5,-1.6);camera.look_at(zombie.position+Vector3.UP*.85)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join("stride_%03d.png"%frame))
	check(walk_frames>300 and zombie.position.z>3,"fast real-body pursuit cycles through the walking animation")
	check(interruptions==0,"short waypoint handoffs do not reset walk through idle; interruptions="+str(interruptions))
	driving=false;host.clear();await ticks(3);stage.free();await process_frame
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"rows":rows},"  "))
	print("ZOMBIE_GAIT_CONTINUITY checks=",checks," failures=",failures);quit(1 if failures else 0)
