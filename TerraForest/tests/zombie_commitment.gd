# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var folder:="res://reports/zombie_commitment"
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pressure-output="):folder=arg.trim_prefix("--pressure-output=")
	run.call_deferred()
func run()->void:
	var brain=ClassDB.instantiate("NativeZombieAwareness");brain.configure(1,12);brain.add_agent(1,Vector3.ZERO)
	brain.set_profile(1,{"forget_seconds":20.,"pursuit_seconds":36.,"notice_seconds":.2,"near_sense_range":6.})
	brain.provoke(1,Vector3(0,0,8))
	for frame in 120:brain.advance(1,Vector3.ZERO,1./60.,true,"planning")
	check(brain.status(1).state=="reposition" and brain.status(1).provoked,"stalled pursuit chooses tactical recovery without discarding retaliation")
	var goal:Vector3=brain.status(1).goal
	brain.observe(1,Vector3(0,0,8),true,8)
	check(brain.status(1).state=="reposition" and brain.status(1).goal==goal,"fresh sight updates evidence without cancelling the recovery action")
	check(not brain.accept_roam(1,Vector3.INF) and brain.status(1).provoked and brain.status(1).urgent,"unsupported recovery endpoint cannot erase engagement")
	brain.observe(1,Vector3(50,0,50),false,70)
	for frame in 60*8:brain.advance(1,Vector3.ZERO,1./60.,true,"blocked")
	check(brain.status(1).urgent and brain.status(1).provoked,"blocked navigation retains active pursuit/search rather than causing disinterest")
	check(brain.hear(1,Vector3.ZERO,Vector3(0,0,4),8),"fresh nearby audible evidence renews a blocked encounter")
	for frame in 60*15:brain.advance(1,Vector3.ZERO,1./60.,true,"blocked")
	check(brain.status(1).urgent,"renewed evidence extends the encounter even while paths fail")
	for frame in 60*22:brain.advance(1,Vector3.ZERO,1./60.,true,"blocked")
	check(not brain.status(1).urgent,"escaping without fresh evidence still permits eventual disengagement")
	var stage:=Node3D.new();root.add_child(stage)
	var floor:=StaticBody3D.new();stage.add_child(floor);floor.position.y=-.5
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(20,1,20);collision.shape=box;floor.add_child(collision)
	var player:=CharacterBody3D.new();stage.add_child(player);player.position=Vector3(0,0,.85)
	var target=preload("res://addons/characters/runtime/zombie_target.gd").new();player.add_child(target)
	var host=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(host);host.enabled=true;host.population_enabled=false;host.target=target;host.readiness=func(_bounds:AABB):return true
	await physics_frame;await physics_frame
	var actor:CharacterBody3D=host.spawn_at(Vector3.ZERO);check(actor!=null,"retaliation fixture admits a real standing body")
	if actor==null:stage.free();quit(1);return
	host.configure_encounter(actor,{"profile":"shambler"})
	player.position=Vector3(0,3,8)
	var recovered:=false
	var recovery_travel:=0.;var previous:Vector3=actor.position;var recovery_extent:=0.
	for frame in 60*6:
		host.update(1./60.,player.position,true);await physics_frame
		var step:Vector3=actor.position-previous;step.y=0;recovery_travel+=step.length();previous=actor.position
		recovery_extent=maxf(recovery_extent,Vector2(actor.position.x,actor.position.z).length())
		if actor.awareness_state=="reposition":recovered=true
	check(recovered and recovery_travel>.8 and recovery_extent>.35 and host.awareness.status(actor.get_instance_id()).urgent,"unreachable elevated recipient produces actual validated recovery movement instead of endless standing")
	check(target.damage_received==0,"tactical recovery cannot authorize attacks on an unreachable elevated player")
	host.clear();await physics_frame;await physics_frame
	player.position=Vector3(0,0,.85);actor=host.spawn_at(Vector3.ZERO)
	check(actor!=null,"repeated-hit fixture admits a fresh healthy body")
	if actor==null:stage.free();quit(1);return
	host.configure_encounter(actor,{"profile":"shambler"})
	for frame in 60*6:
		if frame%12==0:actor.receive_hit("torso",1.,actor.position+Vector3.UP)
		host.update(1./60.,player.position,true);await physics_frame
	check(actor.alive and actor.health<180,"repeated blows continue to damage the real anatomy")
	check(target.damage_received>0,"light repeated hits cannot permanently cancel zombie retaliation")
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"recovery_travel":recovery_travel,"recovery_extent":recovery_extent,"retaliation_damage":target.damage_received,"zombie_health":actor.health},"  "))
	host.clear();stage.free();await process_frame
	print("ZOMBIE_COMMITMENT checks=",checks," failures=",failures);quit(1 if failures else 0)
