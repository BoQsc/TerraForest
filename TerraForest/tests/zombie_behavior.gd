# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var stage:Node3D
var encounters:Node3D
var player:CharacterBody3D
var target:Node3D
var camera:Camera3D
var active:=false
var available:=true
var trace:Array=[]
var folder:="res://reports/zombie_behavior"
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func box(at:Vector3,size:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();body.position=at
	var shape:=BoxShape3D.new();shape.size=size
	var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
	var view:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;view.mesh=mesh;body.add_child(view)
	stage.add_child(body);return body
func tick()->void:
	if active:encounters.update(1.0/60,player.global_position,available)
func ticks(count:int)->void:
	for i in count:await physics_frame
func sample(zombie:Node3D,label:String)->void:
	trace.append({"phase":label,"body":zombie.get_behavior_snapshot(),"intent":encounters.awareness.status(zombie.get_instance_id()),"route":encounters.navigator.status(zombie.get_instance_id())})
func capture(name:String)->void:
	if DisplayServer.get_name()!="headless":
		if not encounters.residents.is_empty():
			var feet:Vector3=encounters.residents[0].global_position
			camera.global_position=feet+Vector3(3,2.5,-4);camera.look_at(feet+Vector3.UP)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func _initialize()->void:run.call_deferred()
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zombie-behavior-dir="):folder=arg.trim_prefix("--zombie-behavior-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	stage=Node3D.new();root.add_child(stage);box(Vector3(0,-.5,0),Vector3(180,1,180))
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);stage.add_child(light)
	camera=Camera3D.new();stage.add_child(camera);camera.position=Vector3(12,10,14);camera.look_at(Vector3(0,1,0));camera.current=true
	player=CharacterBody3D.new();player.collision_layer=2;stage.add_child(player);player.position=Vector3(60,0,0)
	var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8
	var collision:=CollisionShape3D.new();collision.position.y=.9;collision.shape=capsule;player.add_child(collision)
	target=preload("res://addons/characters/runtime/zombie_target.gd").new();player.add_child(target)
	encounters=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(encounters)
	encounters.enabled=true;encounters.target=target;encounters.readiness=func(_bounds:AABB):return true;encounters._spawn_clock=100000
	physics_frame.connect(tick);await ticks(3)
	var zombie=encounters.spawn_at(Vector3.ZERO)
	check(zombie!=null and zombie.target==null,"normal admission starts unaware without a player combat target")
	if zombie==null:stage.free();quit(1);return
	active=true;await ticks(60*5)
	check(zombie.global_position.distance_to(Vector3.ZERO)>.3 and zombie.awareness_state=="wander","unaware body walks a native route instead of waiting beside the player")
	check(target.damage_received==0,"wandering cannot attack a roaming destination")
	sample(zombie,"wander");await capture("wander")
	# Put the player in the actual facing cone, then verify physical pursuit.
	player.position=zombie.global_position+zombie.global_basis.z*7
	await ticks(30)
	check(zombie.awareness_state=="chase" and zombie.target==target,"unobstructed player in view alerts the body")
	var before:float=zombie.global_position.distance_to(player.global_position)
	await ticks(60*3)
	check(zombie.global_position.distance_to(player.global_position)<before-.5,"detected player produces real physical pursuit")
	sample(zombie,"chase");await capture("chase")
	# Controlled orientation for the wall and hidden-player memory case.
	active=false;encounters.clear();await ticks(3);player.position=Vector3(0,0,8)
	encounters._spawn_clock=100000;zombie=encounters.spawn_at(Vector3.ZERO);active=true;await ticks(30)
	check(zombie.awareness_state=="chase","second fixture obtains real sight before hiding")
	var last_seen:Vector3=encounters.awareness.status(zombie.get_instance_id()).goal
	var wall:=box(Vector3(0,2,4),Vector3(100,4,.4));await ticks(30)
	check(zombie.awareness_state=="investigate" and zombie.target==null,"solid wall loses sight and cancels player combat target")
	player.position=Vector3(12,0,8);await ticks(30)
	check(encounters.awareness.status(zombie.get_instance_id()).goal.distance_to(last_seen)<.1,"hidden movement does not update the remembered position")
	check(target.damage_received==0,"occluded player takes no invisible attacks")
	sample(zombie,"investigate");await capture("investigate")
	available=false;await ticks(2)
	var frozen:Dictionary=encounters.awareness.status(zombie.get_instance_id());var stopped:Vector3=zombie.global_position
	await ticks(60)
	check(encounters.awareness.status(zombie.get_instance_id())==frozen and zombie.global_position==stopped,"manager suspension freezes both brain and physical body")
	available=true;await ticks(60*19)
	check(zombie.awareness_state in ["idle","wander"] and zombie.target==null,"unreachable last sighting eventually loses interest and returns to roaming")
	sample(zombie,"forgotten");await capture("forgotten")
	# A reachable last sighting must lead to an actual search, then disengage.
	active=false;wall.free();await ticks(3);player.position=Vector3(0,0,5)
	encounters.clear();await ticks(3);encounters._spawn_clock=100000;zombie=encounters.spawn_at(Vector3.ZERO);active=true;await ticks(30)
	check(zombie.awareness_state=="chase","roaming can reacquire a newly visible player")
	player.position=Vector3(60,0,0)
	var searched:=false
	for i in 60*16:
		await physics_frame
		if zombie.awareness_state=="search":searched=true;break
	check(searched and zombie.target==null,"body reaches a reachable last sighting and searches without a combat target")
	sample(zombie,"search");await capture("search")
	await ticks(60*7)
	check(zombie.awareness_state in ["idle","wander"],"finished physical search returns to ordinary wandering")
	# Actual spawn policy with bounded simulated scheduler time and live collision.
	active=false;encounters.clear();await ticks(3);player.position=Vector3.ZERO;await ticks(3)
	encounters.spawn_visible=func(_point:Vector3):return true
	for i in 179:encounters.update(.1,Vector3.ZERO,true)
	check(encounters.residents.is_empty(),"newly spawned player has an eighteen-second active-play grace period")
	for i in 3:encounters.update(.1,Vector3.ZERO,true)
	check(encounters.residents.is_empty(),"automatic candidates in the player's view reject")
	encounters.spawn_visible=func(_point:Vector3):return false
	encounters._spawn_clock=0;encounters.update(1.0/60,Vector3.ZERO,true)
	check(encounters.residents.size()==1,"automatic scheduler admits one offscreen supported resident")
	if not encounters.residents.is_empty():
		var distance:float=encounters.residents[0].global_position.distance_to(player.global_position)
		check(distance>=40 and distance<=64.1,"automatic spawn is forty to sixty-four metres from player")
		check(encounters.residents[0].target==null,"automatic spawn is not born pursuing the player")
	var count:int=encounters.residents.size();var clock:float=encounters._spawn_clock
	for i in 100:encounters.update(.1,Vector3.ZERO,false)
	check(encounters.residents.size()==count and encounters._spawn_clock==clock,"suspension does not spend the spawn clock")
	encounters.clear();check(is_equal_approx(encounters._spawn_clock,18) and encounters.awareness_status.is_empty(),"world reset clears brains and restores spawn grace")
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"trace":trace},"  "))
	await ticks(2);stage.free();await process_frame
	print("ZOMBIE_BEHAVIOR checks=",checks," failures=",failures);quit(1 if failures else 0)
