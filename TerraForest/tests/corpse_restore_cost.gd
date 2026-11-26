# SPDX-License-Identifier: 0BSD
extends SceneTree
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
class ObservedZombie extends Zombie:
	var debris_builds:=0
	var sever_us:=0
	func sever_limb(part:String,impulse:Vector3=Vector3.ZERO,emit_debris:bool=true)->void:
		var began:=Time.get_ticks_usec()
		super.sever_limb(part,impulse,emit_debris)
		sever_us+=Time.get_ticks_usec()-began
	func _spawn_detached(part:String,chain:Array[String],impulse:Vector3)->void:
		debris_builds+=1
		super._spawn_detached(part,chain,impulse)
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
func run()->void:
	for parts:Array in [["head"],["upper_arm_l","forearm_l","hand_l"],["hand_r","foot_l"]]:
		var mask:=0;var index:=0
		for part:String in Zombie.PARTS:
			if part in parts:mask|=1<<index
			index+=1
		var actor:=ObservedZombie.new(true,mask);actor.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(actor)
		check(actor.initialized,"actor initialized")
		var began:=Time.get_ticks_usec()
		actor.begin_corpse_restore(mask);await process_frame
		while not actor.prepare_corpse_step(1500):await process_frame
		actor.set_simulation_available(true);actor.show()
		var elapsed:=Time.get_ticks_usec()-began
		for part:String in Zombie.PARTS:
			check(bool(actor.missing.get(part,false))==(part in parts),"saved missing limb restored: "+part)
			check(actor.part_meshes[part].visible==(part not in parts),"saved mesh visibility restored: "+part)
			check(actor.physical_bones.has(actor.PARTS[part].bone)==(part not in parts),"saved physical anatomy restored: "+part)
		check(actor.detached_parts.is_empty() and actor.visible and not actor.alive,"restored corpse has no detached debris and is visible/dead")
		check(actor.debris_builds==0,"restoration must not build discarded debris")
		print("CORPSE_RESTORE_COST parts=",parts," debris_builds=",actor.debris_builds," sever_us=",actor.sever_us," elapsed_with_frame_wait_us=",elapsed)
		print("COLLISION_PROFILE ",JSON.stringify(actor.ragdoll_profile))
		actor.queue_free();await process_frame;await process_frame
	print("CORPSE_RESTORE_COST failures=",failures)
	quit(0 if failures==0 else 1)
