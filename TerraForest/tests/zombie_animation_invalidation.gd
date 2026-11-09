# SPDX-License-Identifier: 0BSD
extends SceneTree
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
var failures:=0
var changes:=0
var clears:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func changed()->void:changes+=1
func cleared()->void:clears+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var first:=Zombie.new();first.process_mode=Node.PROCESS_MODE_DISABLED;stage.add_child(first)
	check(first.initialized and first._r4_enabled,"real resident animation contract is ready")
	for key:StringName in first.animation_player.get_animation_list():
		var animation:Animation=first.animation_player.get_animation(key)
		if not animation.changed.is_connected(changed):animation.changed.connect(changed)
	first.animation_player.caches_cleared.connect(cleared)
	first.animation_player.advance(.1)
	var position:float=first.animation_player.current_animation_position
	changes=0;clears=0
	for tick in 60:first._play_animation("Zombie_Idle")
	check(changes==0 and clears==0,"repeated idle selection leaves shared resources and caches unchanged: changes=%d clears=%d"%[changes,clears])
	check(first.animation_player.current_animation_position==position,"repeated selection preserves the playback cursor")
	changes=0;clears=0
	var second:=Zombie.new();second.process_mode=Node.PROCESS_MODE_DISABLED;stage.add_child(second)
	check(second.initialized and changes==0 and clears==0,"admitting another resident leaves existing animation caches intact: changes=%d clears=%d"%[changes,clears])
	var exact:=true
	for clip:String in first.behavior_contract.actions:
		var expected:=Animation.LOOP_LINEAR if bool(first.behavior_contract.actions[clip].get("loop",false)) else Animation.LOOP_NONE
		exact=exact and second.animation_player.get_animation(second._animation_key(clip)).loop_mode==expected
	check(exact,"all action loop modes still match the authored contract")
	var idle:Animation=first.animation_player.get_animation(first._animation_key("Zombie_Idle"))
	idle.loop_mode=Animation.LOOP_NONE;changes=0
	first._play_animation("Zombie_Idle")
	check(idle.loop_mode==Animation.LOOP_LINEAR and changes==1,"a real loop-mode change is still applied")
	for key:StringName in first.animation_player.get_animation_list():
		var animation:Animation=first.animation_player.get_animation(key)
		if animation.changed.is_connected(changed):animation.changed.disconnect(changed)
	stage.free();await process_frame;await process_frame
	print("ZOMBIE_ANIMATION_INVALIDATION failures=",failures)
	quit(1 if failures else 0)
