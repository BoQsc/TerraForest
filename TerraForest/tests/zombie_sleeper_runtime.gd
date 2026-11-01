# SPDX-License-Identifier: 0BSD
extends SceneTree
class ContactTool extends RefCounted:
	func contact_ready(_identity:int)->bool:return true
class ContactGame extends Node:
	var zombies:Node3D
	var camera:Camera3D
	var tool_view:=ContactTool.new()
	func _model_edit_available()->bool:return true
class ContactAttack extends "res://addons/player_runtime/world_attack.gd":
	var accepted:=false
	func can_continue()->bool:return true
	func target()->Dictionary:return {"kind":"model","position":Vector3(0,0,3)}
	func apply_target(_target:Dictionary)->bool:return accepted
var checks:=0
var failures:=0
var stage:Node3D
var host:Node3D
var target:Node3D
var camera:Camera3D
var available:=true
var ready:=true
var driving:=false
var folder:=""
var read_path:=""
var samples:Array=[]

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--review-output="):folder=argument.trim_prefix("--review-output=")
		if argument.begins_with("--runtime-read="):read_path=argument.trim_prefix("--runtime-read=")
	run.call_deferred()

func tick()->void:
	if driving:host.update(1./60.,Vector3.ZERO,available)

func wait_frames(count:int)->void:
	for frame in count:await physics_frame

func block(size:Vector3,center:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();stage.add_child(body);body.position=center
	var collider:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;collider.shape=shape;body.add_child(collider)
	var view:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;view.mesh=mesh;body.add_child(view)
	return body

func spawn(pose:int,wake_delay:float=3.)->CharacterBody3D:
	var zombie:CharacterBody3D=host.spawn_at(Vector3.ZERO)
	check(zombie!=null,"normal encounter host admits a supported resident")
	if zombie!=null and wake_delay!=3.:host.awareness.set_profile(zombie.get_instance_id(),{"id":"wake_test","wake_seconds":wake_delay})
	if zombie!=null:check(host.put_to_sleep(zombie,pose),"live resident admits sleeper pose %d"%pose)
	await wait_frames(8)
	return zombie

func reset()->void:
	driving=false;host.clear();await wait_frames(3)
	available=true;ready=true;target.position=Vector3(0,0,25);driving=true

func capture(label:String,zombie:Node3D)->void:
	samples.append({"name":label,"posture":zombie.sleeper.snapshot(),"body":zombie.get_behavior_snapshot()})
	if folder.is_empty() or DisplayServer.get_name()=="headless":return
	camera.position=zombie.position+Vector3(2.1,.85,2.4);camera.look_at(zombie.position+Vector3(0,.65,0))
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))

func run()->void:
	stage=Node3D.new();root.add_child(stage)
	block(Vector3(80,1,80),Vector3(0,-.5,0))
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-30,0);light.shadow_enabled=true;stage.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;stage.add_child(environment)
	target=Node3D.new();stage.add_child(target);target.position=Vector3(0,0,25)
	host=preload("res://addons/characters/runtime/zombie_world.gd").new();host.target=target;host.enabled=true;host.population_enabled=false
	host.readiness=func(_bounds:AABB):return ready
	stage.add_child(host)
	camera=Camera3D.new();stage.add_child(camera);camera.current=true
	physics_frame.connect(tick);driving=true
	await wait_frames(3)
	if not read_path.is_empty():
		await fresh_restore();return
	var zombie:CharacterBody3D=await spawn(1)
	if zombie==null:quit(1);return
	check(zombie.capsule.shape is BoxShape3D and zombie.get_available_attacks().is_empty() and not zombie.request_jump(),"sleeping body is collidable and cannot attack or jump")
	check(not host.put_to_sleep(zombie,2),"repeated setup cannot reset a sleeper")
	var query_count:int=zombie.sleeper.guard.statistics().queries
	await wait_frames(60)
	check(zombie.sleeper.guard.statistics().queries==query_count,"stationary sleep performs no repeating clearance queries")
	check(zombie.position.distance_to(Vector3.ZERO)<.08,"sleeping actor remains supported without displacement")
	await capture("seated_sleep",zombie)
	check(host.hear_noise(Vector3(0,0,30),7.)==0 and host.awareness.status(zombie.get_instance_id()).state=="sleeping","distant noise does not wake a sleeper")
	var contact_game:=ContactGame.new();stage.add_child(contact_game);contact_game.zombies=host;contact_game.camera=camera
	var contact:=ContactAttack.new();contact.game=contact_game
	contact.pending={"identity":1,"item":0,"slot":0,"contacted":false,"repairing":false};contact.resolve_contact(1)
	check(host.awareness.status(zombie.get_instance_id()).state=="sleeping","rejected player impact makes no harvesting noise")
	contact.accepted=true;contact.pending={"identity":2,"item":0,"slot":0,"contacted":false,"repairing":false};contact.resolve_contact(2)
	check(host.awareness.status(zombie.get_instance_id()).state=="waking","accepted player impact dispatches nearby noise through the actual contact adapter")
	await wait_frames(35)
	var cursor:float=zombie.sleeper.cursor
	zombie.receive_hit("torso",1.,zombie.global_position,Vector3.ZERO)
	check(is_equal_approx(zombie.sleeper.cursor,cursor),"repeated hits do not restart the wake animation")
	available=false;await wait_frames(3)
	var frozen_cursor:float=zombie.sleeper.cursor
	var frozen_timer:float=host.awareness.status(zombie.get_instance_id()).wake_elapsed
	await wait_frames(35)
	check(is_equal_approx(zombie.sleeper.cursor,frozen_cursor) and is_equal_approx(host.awareness.status(zombie.get_instance_id()).wake_elapsed,frozen_timer),"menu suspension freezes both animation and native wake timer")
	available=true;await wait_frames(220)
	check(not zombie.sleeper_active() and zombie.capsule.shape is CapsuleShape3D and not zombie._crawling,"seated wake restores the standing body only after full completion")
	check(cursor>0 and host.awareness.status(zombie.get_instance_id()).state not in ["sleeping","waking"],"physical completion releases native awareness")
	await capture("seated_awake",zombie)
	await reset();zombie=await spawn(1)
	var ceiling:=block(Vector3(4,.2,4),Vector3(0,1.25,0));await wait_frames(3)
	host.hear_noise(Vector3(0,0,3),7.);await wait_frames(260)
	check(zombie.sleeper_active() and zombie.sleeper.blocked and zombie.state=="wake_blocked","low ceiling stops the wake before penetrating it")
	check(host.awareness.status(zombie.get_instance_id()).state=="waking" and zombie.get_available_attacks().is_empty(),"elapsed wake timer cannot authorize combat through a blocked pose")
	var frozen_position:=zombie.position;cursor=zombie.sleeper.cursor;query_count=zombie.sleeper.guard.statistics().queries
	await wait_frames(60)
	check(is_equal_approx(cursor,zombie.sleeper.cursor) and zombie.position.distance_to(frozen_position)<.03,"blocked wake does not reset, teleport or push the actor")
	check(zombie.sleeper.guard.statistics().queries-query_count<=11,"blocked clearance retries are bounded to ten per second")
	await capture("ceiling_blocked",zombie)
	var saved_sleep:PackedByteArray=host.capture_sleep(zombie)
	var saved_vitals:PackedByteArray=zombie.anatomy.capture_vitals()
	var saved_position:=zombie.position
	var population=ClassDB.instantiate("NativeZombiePopulation");population.initialize(1703,Vector3(800,0,1310))
	check(population.update_resident(1,Vector3(maxf(saved_position.x,0),saved_position.y,maxf(saved_position.z,0)),0,saved_vitals,saved_sleep),"actual blocked actor state is accepted by native persistence")
	FileAccess.open(folder.path_join("runtime_sleep_population.bin"),FileAccess.WRITE).store_buffer(population.capture_snapshot())
	await reset()
	zombie=host.spawn_at(saved_position,true)
	var restored:bool=zombie!=null and zombie.restore_population_vitals(saved_vitals) and host.restore_sleep(zombie,saved_sleep)
	check(restored,"streaming restores a blocked sleeper beneath a ceiling without requiring standing clearance")
	if not restored:
		print("Restore details: position=",saved_position," cursor=",cursor," stored=",saved_sleep.decode_float(40)," valid=",ClassDB.instantiate("NativeZombiePosture").validate_snapshot(saved_sleep)," native=",host.awareness.status(zombie.get_instance_id()) if zombie!=null else {})
		driving=false;host.clear();quit(1);return
	await wait_frames(12)
	check(zombie.sleeper.blocked and absf(zombie.sleeper.cursor-cursor)<.001,"restored blocked pose retains its exact animation cursor")
	check(is_equal_approx(host.awareness.status(zombie.get_instance_id()).wake_elapsed,saved_sleep.decode_float(8)),"streaming retains elapsed native wake timer")
	ceiling.queue_free();await wait_frames(260)
	check(not zombie.sleeper_active(),"removing obstruction resumes and completes the same wake")
	await reset();zombie=await spawn(2)
	await capture("lying_sleep",zombie)
	var hit:={"zombie":zombie,"part":"torso","position":zombie.global_position+Vector3.UP*.3}
	check(host.apply_hit(hit,4.,Vector3.FORWARD,"melee"),"damaging the sleeping body follows ordinary hit handling")
	await wait_frames(100)
	check(zombie.sleeper.phase=="waking" and zombie.health==176.,"damage wakes lying resident without a standing-hit animation snap")
	ready=false;await wait_frames(3);cursor=zombie.sleeper.cursor;await wait_frames(20)
	check(is_equal_approx(cursor,zombie.sleeper.cursor),"unavailable collision coverage suspends waking")
	ready=true;await wait_frames(200)
	check(not zombie.sleeper_active() and zombie.get_behavior_snapshot().contact_count==0,"lying wake completes without premature attacks")
	await reset();zombie=await spawn(1)
	host.hear_noise(Vector3(0,0,3),7.);await wait_frames(100)
	var torso_before:Transform3D=zombie.skeleton.get_bone_global_pose(zombie.skeleton.find_bone("Spine2"))
	zombie.sever_limb("shin_l",Vector3.ZERO,false)
	check(zombie.skeleton.get_bone_global_pose(zombie.skeleton.find_bone("Spine2")).origin.distance_to(torso_before.origin)<.001,"mid-wake leg loss preserves the current torso pose")
	await wait_frames(15)
	check(zombie.sleeper.reversing,"leg loss reverses through the authored supported transition")
	await wait_frames(300)
	check(not zombie.sleeper_active() and zombie._crawling and zombie.missing.shin_l,"amputated resident exits into crawling, never standing locomotion")
	await capture("missing_leg_awake",zombie)
	await reset();zombie=await spawn(2)
	zombie.sever_limb("shin_r",Vector3.ZERO,false);host.awareness.provoke(zombie.get_instance_id(),Vector3(0,0,3));await wait_frames(220)
	check(not zombie.sleeper_active() and zombie._crawling,"legless lying sleeper uses the authored crawl wake")
	await reset();zombie=await spawn(1,8.)
	host.hear_noise(Vector3(0,0,3),7.);await wait_frames(210)
	check(zombie.sleeper.phase=="ready" and zombie.get_available_attacks().is_empty(),"finished animation still waits for native wake handshake")
	zombie.sever_limb("shin_l",Vector3.ZERO,false);await wait_frames(12)
	check(zombie.sleeper.phase=="waking" and zombie.sleeper.reversing,"leg loss during completion handshake reopens the physical transition")
	await wait_frames(360)
	check(not zombie.sleeper_active() and zombie._crawling,"interrupted completion handshake cannot release standing locomotion")
	await reset();zombie=await spawn(2)
	host.hear_noise(Vector3(0,0,3),7.);await wait_frames(55)
	zombie.receive_hit("torso",1000.,zombie.global_position,Vector3.ZERO)
	await wait_frames(45)
	check(not zombie.alive and not zombie.sleeper_active() and zombie.state=="ragdoll" and zombie.capsule.disabled,"death during wake transfers ownership to the existing ragdoll")
	await capture("wake_death",zombie)
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"runtime checks leave pointer uncaptured")
	driving=false;host.clear();await wait_frames(3)
	if not folder.is_empty():FileAccess.open(folder.path_join("runtime.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"samples":samples},"  "))
	print("ZOMBIE_SLEEPERS_RUNTIME checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func fresh_restore()->void:
	var population=ClassDB.instantiate("NativeZombiePopulation")
	check(population.restore_snapshot(FileAccess.get_file_as_bytes(read_path)),"fresh process loads the real blocked resident snapshot")
	var record:Dictionary=population.resident(1)
	var ceiling:=block(Vector3(4,.2,4),Vector3(0,1.25,0));await wait_frames(3)
	var zombie:CharacterBody3D=host.spawn_at(record.position,true)
	var restored:bool=zombie!=null and zombie.restore_population_vitals(record.vitals) and host.restore_sleep(zombie,record.sleep)
	check(restored,"fresh process reconstructs the live sleeper under its obstruction")
	if restored:
		await wait_frames(65)
		check(zombie.sleeper.blocked and absf(zombie.sleeper.cursor-record.sleep.decode_float(40))<.001,"fresh body cannot skip the saved obstruction or advance its pose")
		check(zombie.health==record.vitals.decode_float(0) and zombie.sleeper.pose==record.sleep.decode_u32(0),"fresh actor preserves health and sleep pose identity")
		await capture("fresh_process_blocked",zombie)
		ceiling.queue_free();await wait_frames(260)
		check(not zombie.sleeper_active() and zombie.capsule.shape is CapsuleShape3D,"freshly loaded wake completes when clearance returns")
	driving=false;host.clear();await wait_frames(3)
	print("ZOMBIE_SLEEPERS_RUNTIME checks=",checks," failures=",failures)
	quit(1 if failures else 0)
