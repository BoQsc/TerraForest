# SPDX-License-Identifier: 0BSD
extends SceneTree
# Real combat admission, native barrel/durability stores and chain propagation.
# Terrain submission is a controllable boundary; integrated terrain is checked
# separately. Actor readiness deliberately stays false at every player position.
class Excavation extends RefCounted:
	var accepted:=true
	var calls:=0
	var accepted_points:Array[Vector3]=[]
	func excavate_blast(point:Vector3,_radius:float)->bool:
		calls+=1
		if accepted:accepted_points.append(point)
		return accepted
class Terrain extends RefCounted:
	var changed_since_save:=false
	var pending_edit:=false
	var epoch:=1
	var edit_ticket:=42
	func _record_stage(_label:String,_ms:float)->void:pass
class History extends RefCounted:
	func clear_history()->void:pass
class Enemies extends RefCounted:
	var residents:Array[Node3D]=[]
	func hear_noise(_point:Vector3,_radius:float)->void:pass
class Host extends Node:
	var terrain:=Terrain.new()
	var structures:Node3D
	var mining_rewards:=Excavation.new()
	var world_attack=preload("res://addons/player_runtime/world_attack.gd").new()
	var model_tool:Dictionary={"history":History.new()}
	var zombies:=Enemies.new()
	var lakes:Dictionary={"water":ClassDB.instantiate("NativeRegionalWater")}
	var player:=Node3D.new()
	func _actor_collision_ready(_bounds:AABB)->bool:return false
class Combat extends "res://addons/player_runtime/combat_world.gd":
	func play_sound(_point:Vector3,_stream:AudioStream,_gain_db:float=0.0)->void:pass
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var host:=Host.new();root.add_child(host);host.add_child(host.player)
	host.world_attack.durability=ClassDB.instantiate("NativeWorldDurability")
	host.structures=preload("res://addons/structures/structures_world.gd").new();host.add_child(host.structures)
	check(host.structures.prepare(),"native structures prepared")
	var combat:=Combat.new();host.add_child(combat);combat.set_physics_process(false)
	combat.game=host;combat.state=ClassDB.instantiate("NativeCombatState")
	combat.blast_water_settling=true
	combat.barrels=combat.Barrel.register(host.structures);combat.add_child(combat.effects)
	var ids:Array[int]=[]
	for x in [800,803,806]:
		ids.append(combat.barrels.insert_instance(PackedFloat32Array([1,0,0,x,0,1,0,60,0,0,1,800]),AABB()))
	check(combat.damage_barrel(ids[0],50),"remote barrel ignites in authoritative store")
	host.mining_rewards.accepted=false
	check(not combat.detonate(ids[0]) and not combat.barrels.get_instance(ids[0]).is_empty() and combat.explosions==0,"rejected terrain admission retains ignited barrel and damage")
	host.mining_rewards.accepted=true
	for id in ids:
		check(id in combat.detonations,"chain ignition reaches remote barrel")
		check(combat.detonate(id),"blast proceeds without player-relative actor collision readiness")
		combat.detonations.erase(id)
	check(combat.barrels.get_ids().is_empty() and combat.explosions==3,"entire remote chain detonates once with stationary distant player")
	check(combat.detonate(ids[0]) and combat.explosions==3,"retry cannot replay consumed blast")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):combat.chain_settings_path=arg.trim_prefix("--check-evidence-dir=").path_join("barrel_test.cfg")
	check(combat.chain_settings_path.get_file()=="barrel_test.cfg","settings use the isolated report directory")
	if failures:host.free();quit(1);return
	combat.load_chain_setting()
	check(not combat.fast_chains,"default pacing in a fresh profile")
	combat.set_fast_chains(true)
	var old_config:=ConfigFile.new()
	old_config.set_value("barrels","fast_chains",true)
	old_config.save(combat.chain_settings_path)
	combat.fast_chains=false
	combat.load_chain_setting()
	check(combat.fast_chains and combat.barrel_distance==3072,"existing pacing preference gains whole-world simulation by default")
	combat.set_barrel_distance(768)
	combat.set_fast_chains(false)
	combat.set_fast_chains(true)
	combat.barrel_distance=384
	combat.load_chain_setting()
	check(combat.fast_chains and combat.barrel_distance==768,"slider and pacing preferences survive reload together")

	ids.clear()
	for x in [800,840]:
		for n in 10:
			ids.append(combat.barrels.insert_instance(PackedFloat32Array([1,0,0,x,0,1,0,60,0,0,1,800+4*n]),AABB()))
	combat.damage_barrel(ids[0],50)
	combat.damage_barrel(ids[10],50)
	host.terrain.pending_edit=true
	combat.step_detonations()
	check(combat.explosions==3+combat.FAST_DETONATIONS_PER_TICK and combat.craters.pending.size()==16,"two independent chains propagate multiple links in one busy terrain tick")
	check(combat.barrels.get_instance(ids[6]).is_empty() and combat.barrels.get_instance(ids[16]).is_empty(),"both chains advance in the same tick")
	combat.step_detonations()
	check(combat.explosions==23 and combat.detonations.is_empty() and combat.craters.pending.size()==20,"burst overflow finishes exactly once on the next tick")
	combat.set_fast_chains(false)
	host.terrain.pending_edit=false
	host.mining_rewards.accepted=false
	combat.step_detonations()
	check(combat.craters.pending.size()==20 and combat.craters.ticket==-1,"refused crater stays queued after switching back to standard pacing")
	host.mining_rewards.accepted=true
	combat.step_detonations()
	combat._crater_resolved({"epoch":1,"ticket":42,"status":"rejected"})
	check(combat.craters.pending.size()==20 and combat.craters.ticket==-1,"worker rejection retains crater for retry")
	combat.step_detonations()
	combat._crater_resolved({"epoch":1,"ticket":42,"status":"building"})
	var saved:=combat.craters.capture_snapshot()
	var remaining:=combat.craters.pending.duplicate(true)
	check(combat.craters.restore_snapshot(PackedByteArray()) and combat.craters.pending.is_empty(),"older worlds start with no deferred craters")
	check(combat.craters.restore_snapshot(saved) and combat.craters.pending==remaining and remaining.size()==19,"save restores exact remaining crater identities and coordinates")
	host.mining_rewards.accepted_points.clear()
	for crater:Dictionary in remaining:
		combat.step_detonations()
		combat.step_detonations()
		combat._crater_resolved({"epoch":1,"ticket":42,"status":"unchanged"})
	check(host.mining_rewards.accepted_points==remaining.map(func(crater):return crater.point) and combat.craters.pending.is_empty() and combat.explosions==23,"each remaining crater submits once without replaying explosions")
	await check_saved_pages(host,combat)
	combat.effects.clear();host.free();await process_frame
	print("COMBAT_REMOTE_BLAST failures=",failures)
	quit(1 if failures else 0)

func check_saved_pages(host:Host,combat:Combat)->void:
	var world:=host.structures
	var prop:Node3D=world.register_model("test/distant_prop",BoxMesh.new())
	var ids:Array[int]=[]
	for x in [1022,1026,1030]:
		ids.append(combat.barrels.insert_instance(PackedFloat32Array([1,0,0,x,0,1,0,60,0,0,1,800]),AABB()))
	prop.insert_instance(combat.barrels.get_instance(ids[2]),AABB())
	var cell:=Vector3i(1026,60,800)
	world.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,1]))
	check(combat.damage_barrel(ids[0],50),"source barrel is ignited before the checkpoint")
	var saved_damage:PackedByteArray=host.world_attack.durability.capture_storage_snapshot()
	combat.detonations.clear()
	var source_page:PackedByteArray=combat.barrels.capture_region(Vector3i(31,1,25))
	var archive:RefCounted=ClassDB.instantiate("NativeRegionWorldArchive")
	var raw:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var path:=combat.chain_settings_path.get_base_dir().path_join("barrel_pages.trw")
	check(archive.configure(raw,world.snapshot_validator(),true,true) and archive.acquire(path),"tiny regional archive opens in the admitted report directory")
	var snapshot:PackedByteArray=archive.encode({"terrain":PackedByteArray([1]),"structures":world.capture_snapshot(),"world_durability":saved_damage})
	check(archive.publish(path,snapshot)==OK,"checkpoint includes the ignition and its barrel placement")
	var sections:Dictionary=archive.decode(archive.read(path)).sections
	check(world.restore_storage_snapshot(sections.structures),"saved barrel and building pages reopen from metadata")
	check(combat.barrels.is_instance_paged_out(ids[0]) and prop.get_ids().is_empty() and not world.blocks.is_region_loaded(Vector3i(16,0,12)),"remote barrel, prop and building start unloaded")
	var history:RefCounted=ClassDB.instantiate("NativeStaticHistory")
	history.configure(world.model_collections().values(),1048576,128)
	check(archive.start_region_reads(16,64*1024*1024) and world.enable_region_paging(archive) and world.enable_model_paging(archive,history),"normal pagers share the regional archive")
	combat.set_barrel_distance(combat.WORLD_BARREL_DISTANCE)
	var page_deadline:=Time.get_ticks_msec()+10000
	while (combat.barrels.get_ids().size()!=3 or world._model_scheduler.stats().jobs!=0) and Time.get_ticks_msec()<page_deadline:
		world.step_model_paging(host.player.global_position)
		await process_frame
	check(combat.barrels.get_ids().size()==3 and prop.get_ids().is_empty(),"whole-world distance loads distant barrels independently of other saved objects")
	combat.set_barrel_distance(384)
	page_deadline=Time.get_ticks_msec()+10000
	while (not combat.barrels.get_ids().is_empty() or world._model_scheduler.stats().jobs!=0) and Time.get_ticks_msec()<page_deadline:
		world.step_model_paging(host.player.global_position)
		await process_frame
	check(combat.barrels.get_ids().is_empty(),"lower slider value allows the distant barrel pages to retire")
	check(host.world_attack.durability.restore_storage_snapshot(sections.world_durability),"saved ignition restores with its original barrel identity")
	combat.recover_ignited_barrels()
	check(combat.detonations==[ids[0]],"saved ignition is discovered even with its own placement paged out")
	var initial:=combat.explosions
	var calls:=host.mining_rewards.calls
	combat.step_detonations()
	check(combat.detonations==[ids[0]] and combat.warming_chain,"cold ignited barrel remains queued until its page arrives")
	check(combat.barrels.restore_region(source_page),"source page arrives before the neighboring barrel page")
	combat.step_detonations()
	check(combat.explosions==initial and host.mining_rewards.calls==calls and combat.warming_chain,"ignition waits for missing neighbors before applying any blast")
	combat.destruction_coordinator=ClassDB.instantiate("NativeDestructionCoordinator")
	combat.effects.blocks=world.blocks
	var deadline:=Time.get_ticks_msec()+12000
	while Time.get_ticks_msec()<deadline:
		world.step_model_paging(host.player.global_position)
		world.step_region_paging(host.player.global_position)
		combat.step_detonations()
		combat.step_blasts()
		if combat.explosions==initial+3 and combat.blast_jobs.is_empty():break
		await process_frame
	check(combat.explosions==initial+3 and combat.barrels.get_ids().is_empty() and host.mining_rewards.calls==calls+3,"chain crosses saved pages over a kilometre away with one crater submission per barrel")
	check(combat.destroyed_blocks==1 and world.blocks.get_cell(cell)==0,"remote explosion loads and damages the saved building")
	check(host.player.global_position==Vector3.ZERO and prop.get_ids().is_empty() and not combat.warming_chain,"stationary player completes the chain while the unrelated prop stays cold")
	deadline=Time.get_ticks_msec()+5000
	while not world.drain_model_paging() and Time.get_ticks_msec()<deadline:
		world.step_model_paging(Vector3.ZERO)
		await process_frame
	check(world.finish_model_paging(),"test paging drains before archive release")
	world.stop_region_paging()
	archive.release()
