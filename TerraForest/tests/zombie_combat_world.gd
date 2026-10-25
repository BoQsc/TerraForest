# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var failures:=0
var checks:=0
var evidence:="res://reports/zombie_combat_world"
var health_only:=false
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
func record_swing(identity:int,cancelled:bool)->void:
	print("COMBAT_SWING ",JSON.stringify({"identity":identity,"cancelled":cancelled,"focused":game.app_focused,"mouse_mode":Input.mouse_mode,"available":game._model_edit_available(),"hit":game.world_attack.last_hit}))
func run()->void:
	if DisplayServer.get_name()=="headless":push_error("Zombie world combat requires a graphical viewport and captured input");quit(2);return
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--zombie-world-evidence="):evidence=argument.trim_prefix("--zombie-world-evidence=")
		if argument=="--zombie-health-only":health_only=true
	DirAccess.make_dir_recursive_absolute(evidence)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"playable world ready"):await finish();return
	await wait_for(func():return not game.needs_floor_spawn,5)
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	game.zombies.population_enabled=false;game.zombies.clear();game.player_hud.equip_item(2);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	game.tool_view.attack_finished.connect(record_swing)
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
		check(zombie.limb_health.forearm_l==limb_before-7.5 and zombie.health==vitality_before-15 and game.player_hud.inventory.snapshot().slots[slot].wear==wear+strike+1,"contact applies full shared damage, increased cutting trauma and exactly one tool wear")
		if strike==0:
			var feedback=game.player_hud.damage_feedback
			check(feedback.visible and feedback.remaining==165 and feedback.maximum==180 and feedback.name_label.text=="Zombie" and feedback.detail_label.visible and feedback.detail_label.text.contains("31 / 38") and feedback.limb_bar.visible and feedback.limb_bar.value==30.5 and feedback.limb_bar.max_value==38,"combat HUD keeps overall health primary and exact limb health secondary")
			await screenshot("shared_health")
	check(zombie.alive and not zombie.missing.forearm_l and not zombie.missing.hand_l and zombie.detached_parts.is_empty(),"three ordinary hatchet strikes no longer sever the forearm")
	var strikes:=3
	for part:String in ["torso","upper_arm_r","head"]:
		if not check(aim_part(zombie,part),"live tool ray selects another visible region: "+part):break
		var health_before:float=zombie.health
		game.world_attack.next_attack=0
		check(game.world_attack.attack() and await wait_for(func():return game.world_attack.pending.is_empty(),4) and game.world_attack.last_hit,"animation contacts the selected region: "+part)
		strikes+=1
		var feedback=game.player_hud.damage_feedback
		check(zombie.health==health_before-15 and feedback.remaining==int(zombie.health) and feedback.maximum==180 and game.player_hud.inventory.snapshot().slots[slot].wear==wear+strikes,"changing regions continues the same health and charges one tool wear: "+part)
		check(feedback.limb_bar.value==zombie.limb_health[part] and feedback.limb_bar.max_value==zombie.PARTS[part].health,"secondary health follows the actual hit limb without changing overall health: "+part)
	if health_only:
		var feedback=game.player_hud.damage_feedback
		feedback.show_hit("Building block",30,90)
		check(feedback.visible and not feedback.limb_bar.visible and not feedback.detail_label.visible,"ordinary world targets hide secondary limb information")
		feedback.show_zombie_hit("Forearm L",int(zombie.health),180,zombie.limb_health.forearm_l,38)
		check(feedback.remaining==int(zombie.health) and feedback.limb_bar.value==15.5 and feedback.limb_bar.visible,"returning to the wounded limb retains its independent health")
		await screenshot("overall_and_limb_health")
		for strike in 3:
			if not check(aim_part(zombie,"forearm_l"),"the remaining forearm is still targetable before severing"):break
			game.world_attack.next_attack=0
			check(game.world_attack.attack() and await wait_for(func():return game.world_attack.pending.is_empty(),4) and game.world_attack.last_hit,"additional ordinary hatchet swing lands at animation contact")
			check(zombie.missing.forearm_l==(strike==2) and zombie.health==75-strike*15,"the sixth focused forearm hit severs without changing overall damage")
		check(zombie.alive and zombie.missing.hand_l and zombie.detached_parts.size()==1 and feedback.remaining==45 and feedback.limb_bar.value==0 and feedback.detail_label.text.contains("Severed"),"ordinary hatchet severing updates both health displays and detaches the anatomical chain")
		await screenshot("increased_severing")
		feedback.clear();check(not feedback.visible,"clearing the hit display hides both health readouts")
		print("ZOMBIE_HEALTH_ONLY scope=health_and_feedback_not_ragdoll")
		await finish();return
	check(game.zombies.apply_hit({"zombie":zombie,"part":"forearm_l","position":zombie.global_position+Vector3.UP},30,Vector3.FORWARD,"heavy") and zombie.alive and zombie.missing.forearm_l and zombie.missing.hand_l and zombie.detached_parts.size()==1,"strong damage still detaches the injured forearm and its hand")
	check(not "left" in zombie.get_available_attacks() and "right" in zombie.get_available_attacks(),"live anatomy changes available zombie attacks in the playable world")
	await screenshot("player_severed_arm")
	zombie.animation_player.pause();zombie.set_physics_process(true)
	check(game.zombies.apply_hit({"zombie":zombie,"part":"head","position":zombie.global_position+Vector3.UP*1.6},50,Vector3.FORWARD,"firearm"),"firearm head destruction enters the real physical corpse path")
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
	var corpse_id:int=zombie.get_meta("corpse_identity",0)
	var corpse_bytes:PackedByteArray=game.corpse_loot.capture()
	var saved:Dictionary=game.corpse_loot.store.corpse(corpse_id)
	check(corpse_id>0 and saved.missing&26==26 and saved.pose.size()==180 and game.corpse_loot.store.validate_corpse_snapshot(corpse_bytes),"severed head and arm save with valid poses and a missing-parts mask")
	var restored:RefCounted=ClassDB.instantiate("NativeCorpseStore")
	check(restored.configure(game.player_hud.inventory,4096) and restored.restore_corpse_snapshot(corpse_bytes) and restored.corpse(corpse_id).missing==saved.missing and restored.corpse(corpse_id).pose==saved.pose,"corpse snapshot restores without resurrecting missing limbs or losing loot identity")
	game.zombies.clear();await process_frame;await process_frame
	game.corpse_loot.clock=0;game.corpse_loot.update(.1,game.player.global_position,true)
	for frame in 360:await physics_frame
	var restored_corpse:Node3D=game.corpse_loot.active.get(corpse_id)
	check(is_instance_valid(restored_corpse) and restored_corpse.is_visible_in_tree() and restored_corpse.missing.head and restored_corpse.missing.forearm_l and restored_corpse.missing.hand_l and restored_corpse.physical_bones.size()==12,"real corpse restoration preserves the severed head and arm mask")
	if is_instance_valid(restored_corpse):
		var rest:Dictionary=restored_corpse.anatomy.ragdoll_stats()
		check(rest.bodies==12 and rest.sleeping==12,"restored severed corpse settles without recreating removed fragments")
	await finish()
func finish()->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("ZOMBIE_COMBAT_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
