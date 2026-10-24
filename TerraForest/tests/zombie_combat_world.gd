# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var failures:=0
var checks:=0
var evidence:="res://reports/zombie_combat_world"
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label);return ok
func _initialize()->void:run.call_deferred()
func wait_for(predicate:Callable,seconds:int=10)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func aim_part(zombie:Node3D,part:String)->bool:
	zombie.animation_player.pause();zombie.skeleton.force_update_all_bone_transforms()
	var mesh:ArrayMesh=zombie._bake_cpu(zombie.part_meshes[part],Transform3D.IDENTITY)
	var center:Vector3=mesh.get_aabb().get_center()
	for offset:Vector3 in [Vector3(0,0,2),Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,-2),Vector3(0,1.5,1.5)]:
		game.player.position=Vector3(center.x+offset.x,zombie.global_position.y,center.z+offset.z)
		game.camera.position=Vector3(0,1.62,0);game.camera.look_at(center)
		var target:Dictionary=game.world_attack.target()
		if target.get("kind")=="zombie" and target.zombie==zombie and target.part==part:return true
	return false
func screenshot(name:String)->void:
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(evidence.path_join(name+".png"))
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--zombie-world-evidence="):evidence=argument.trim_prefix("--zombie-world-evidence=")
	DirAccess.make_dir_recursive_absolute(evidence)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"playable world ready"):await finish();return
	await wait_for(func():return not game.needs_floor_spawn,5)
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	game.zombies._spawn_clock=100000;game.player_hud.equip_item(2);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var zombie:Node3D
	for offset:Vector3 in [Vector3(0,0,2),Vector3(2,0,0),Vector3(-2,0,0),Vector3(0,0,-2)]:
		zombie=game.zombies.spawn_at(game.player.global_position+offset)
		if zombie!=null:break
	if not check(zombie!=null,"zombie admits on real streamed forest terrain"):await finish();return
	zombie.set_behavior(false);zombie.set_physics_process(false)
	check(zombie.walk_speed>.45 and zombie.chase_speed_multiplier>1 and zombie.get_crawl_speed()>.32,"healthy roaming, pursuit and crawl speeds improve over the previous defaults")
	var slot:int=game.player_hud.active_slot;var wear:int=game.player_hud.inventory.snapshot().slots[slot].wear
	for strike in 3:
		if not check(aim_part(zombie,"forearm_l"),"actual held-tool ray resolves the visible forearm, strike "+str(strike)):break
		var limb_before:float=zombie.limb_health.forearm_l;var vitality_before:float=zombie.health
		game.world_attack.next_attack=0
		if not check(game.world_attack.attack(),"actual tool animation starts, strike "+str(strike)):break
		check(zombie.limb_health.forearm_l==limb_before and zombie.health==vitality_before,"windup cannot apply damage before animation contact")
		check(await wait_for(func():return game.world_attack.pending.is_empty(),4) and game.world_attack.last_hit,"animation contact resolves a live zombie hit")
		check(zombie.limb_health.forearm_l<limb_before and zombie.health<vitality_before and game.player_hud.inventory.snapshot().slots[slot].wear==wear+strike+1,"contact changes both health pools and wears the held tool exactly once")
		if strike==0:
			var feedback=game.player_hud.damage_feedback
			check(feedback.visible and feedback.remaining==23 and feedback.maximum==38 and feedback.detail_label.visible and feedback.detail_label.text.contains(str(int(ceil(zombie.health)))),"combat HUD shows authoritative limb condition and overall health together")
			await screenshot("limb_and_health")
	check(zombie.alive and zombie.missing.forearm_l and zombie.missing.hand_l and zombie.detached_parts.size()==1,"ordinary player swings sever an exhausted forearm and its hand")
	check(not "left" in zombie.get_available_attacks() and "right" in zombie.get_available_attacks(),"live anatomy changes available zombie attacks in the playable world")
	await screenshot("player_severed_arm")
	zombie.animation_player.pause();zombie.set_physics_process(true)
	check(game.zombies.apply_hit({"zombie":zombie,"part":"head","position":zombie.global_position+Vector3.UP*1.6},50,Vector3.FORWARD),"head destruction enters the real physical corpse path")
	# Measure unforced rest without the player capsule pinning a falling limb.
	game.player.position=zombie.global_position+Vector3(6,1,0)
	for second in 6:
		for i in 60:await physics_frame
		print("FOREST_SETTLE ",second+1," ",JSON.stringify(zombie.anatomy.ragdoll_stats()))
	var stats:Dictionary=zombie.anatomy.ragdoll_stats();print("FOREST_CORPSE ",JSON.stringify(stats))
	var contacts:Dictionary={};var unable_to_sleep:Array=[]
	var awake_bodies:Array=[]
	for body:PhysicalBone3D in zombie.physical_bones.values():
		if not PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_SLEEPING):awake_bodies.append(str(body.name))
		if not PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_CAN_SLEEP):unable_to_sleep.append(body.name)
		var direct:=PhysicsServer3D.body_get_direct_state(body.get_rid())
		if direct!=null:
			for c in direct.get_contact_count():
				var collider:Object=instance_from_id(direct.get_contact_collider_id(c))
				if is_instance_valid(collider):contacts[str(collider.get_instance_id())]=str(collider.name)+":"+collider.get_class()
	for piece:RigidBody3D in zombie.detached_parts:
		for segment:RigidBody3D in piece.get_meta("segment_bodies",[]):
			if not PhysicsServer3D.body_get_state(segment.get_rid(),PhysicsServer3D.BODY_STATE_SLEEPING):awake_bodies.append(str(segment.name))
	print("FOREST_CONTACTS ",JSON.stringify({"contacts":contacts,"no_sleep":unable_to_sleep,"awake":awake_bodies,"world_physics_enabled":game.is_physics_processing()}))
	check(not zombie.alive and zombie.health==0 and not zombie.animation_player.active and stats.sleeping==stats.bodies and stats.bodies>0,"forest corpse and detached arm settle with animation disabled")
	game.zombies.update(.016,game.player.position,true)
	check(not zombie.behavior_enabled,"normal host update leaves the corpse passive")
	game.camera.global_position=zombie.physical_bones.Hips.global_position+Vector3(2,1.8,2.5);game.camera.look_at(zombie.physical_bones.Hips.global_position+Vector3.UP*.2)
	await screenshot("forest_corpse")
	game.zombies.invalidate_navigation(AABB(zombie.physical_bones.Hips.global_position-Vector3.ONE,Vector3.ONE*2))
	var force_settings_restored:=true
	for piece:RigidBody3D in zombie.detached_parts:
		for segment:RigidBody3D in piece.get_meta("segment_bodies",[]):
			if segment.custom_integrator or not segment.continuous_cd:force_settings_restored=false
	check(force_settings_restored and zombie.anatomy.ragdoll_stats().resting==0 and zombie.physical_bones.Spine2.joint_type!=PhysicalBone3D.JOINT_TYPE_NONE,"nearby world edits restore corpse constraints, gravity and swept collision")
	check(not game.persistence._capture().sections.has("zombies"),"encounter anatomy remains session-local without changing saved world schemas")
	await finish()
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("ZOMBIE_COMBAT_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
