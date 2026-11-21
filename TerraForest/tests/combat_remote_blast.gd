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
	var world_attack:Dictionary={"durability":ClassDB.instantiate("NativeWorldDurability")}
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
	combat.fast_chains=false
	combat.load_chain_setting()
	check(combat.fast_chains,"fast chain preference survives reload")

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
	combat.effects.clear();host.free();await process_frame
	print("COMBAT_REMOTE_BLAST failures=",failures)
	quit(1 if failures else 0)
