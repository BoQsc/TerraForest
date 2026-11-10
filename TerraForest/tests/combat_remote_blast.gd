# SPDX-License-Identifier: 0BSD
extends SceneTree
# Real combat admission, native barrel/durability stores and chain propagation.
# Terrain submission is a controllable boundary; integrated terrain is checked
# separately. Actor readiness deliberately stays false at every player position.
class Excavation extends RefCounted:
	var accepted:=true
	var calls:=0
	func excavate_blast(_point:Vector3,_radius:float)->bool:
		calls+=1
		return accepted
class History extends RefCounted:
	func clear_history()->void:pass
class Enemies extends RefCounted:
	var residents:Array[Node3D]=[]
	func hear_noise(_point:Vector3,_radius:float)->void:pass
class Host extends Node:
	var terrain:Dictionary={"changed_since_save":false}
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
	combat.effects.clear();host.free();await process_frame
	print("COMBAT_REMOTE_BLAST failures=",failures)
	quit(1 if failures else 0)
