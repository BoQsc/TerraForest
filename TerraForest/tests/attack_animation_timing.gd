# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var tools=preload("res://addons/player_runtime/tool_view.gd").new();root.add_child(tools);tools.set_process(false)
	var human=tools.human;human.set_process(false)
	var contacts:Array=[];var ends:Array=[]
	tools.attack_contact.connect(func(identity:int):contacts.append({"id":identity,"position":human.animation_player.current_animation_position,"clip":human.active_clip}))
	tools.attack_finished.connect(func(identity:int,cancelled:bool):ends.append({"id":identity,"cancelled":cancelled}))
	tools.equip(1)
	var profile:Dictionary=tools.attack_profile()
	check(is_equal_approx(profile.contact,32.0/60) and is_equal_approx(profile.duration,1.2),"pickaxe contact uses authored frame 32 of the 72-frame swing")
	check(tools.begin_attack(1),"one visible pickaxe swing starts")
	human._process(0.2)
	check(contacts.is_empty() and human.action_remaining>0,"windup has no contact")
	check(not tools.begin_attack(2),"another request cannot restart or hide a swing")
	human._process(0.4)
	check(contacts.size()==1 and contacts[0].id==1 and is_equal_approx(contacts[0].position,profile.contact),"crossing contact holds the exact visible contact pose and emits once")
	human._process(0.1)
	check(contacts.size()==1 and tools.attack_identity==1,"recovery cannot generate another hit")
	human._process(2)
	check(ends.size()==1 and not ends[0].cancelled and tools.attack_identity==0 and human.action_remaining==0,"full recovery finishes before the next attack")
	human.animation_player.speed_scale=0.5
	check(tools.begin_attack(3),"slowed animation starts")
	human._process(0.6)
	check(contacts.size()==1,"slower playback also delays contact")
	human._process(0.6)
	check(contacts.size()==2 and contacts[-1].id==3 and is_equal_approx(contacts[-1].position,profile.contact),"contact follows animation playback speed")
	tools.cancel_attack();human.animation_player.speed_scale=1
	check(tools.begin_attack(4),"fresh swing after cancellation")
	human._process(0.1);tools.equip(2);human._process(2)
	check(contacts.size()==2 and ends[-1].id==4 and ends[-1].cancelled,"equip cancels pending contact without a ghost hit")
	for item in [0,2,3,5]:
		tools.equip(item);var count:=contacts.size();var current:Dictionary=tools.attack_profile()
		check(not current.is_empty() and tools.begin_attack(10+item),"authored tool has an actual visible strike "+str(item))
		human._process(current.contact-0.01)
		check(contacts.size()==count,"authored windup does not hit "+str(item))
		human._process(0.02)
		check(contacts.size()==count+1 and is_equal_approx(contacts[-1].position,current.contact) and tools.contact_ready(10+item),"authored tool emits once at the exact contact pose "+str(item))
		human._process(2)
	for item in [4]:
		tools.equip(item);var count:=contacts.size()
		check(tools.begin_attack(20+item),"procedural held tool starts "+str(item))
		check(contacts.size()==count,"procedural tool has no immediate hit "+str(item))
		var deadline:=Time.get_ticks_msec()+1500
		while tools.attack_identity!=0 and Time.get_ticks_msec()<deadline:await process_frame
		check(contacts.size()==count+1 and is_equal_approx(tools.tools[item].rotation.x,-0.2),"procedural contact/recovery completes once "+str(item))
	tools.free();await process_frame
	print("ATTACK_ANIMATION_TIMING checks=",checks," failures=",failures);quit(1 if failures else 0)
