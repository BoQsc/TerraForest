# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func run_for(brain:RefCounted,seconds:float,feet:Vector3,route:String="following")->Dictionary:
	var state:Dictionary
	for tick in int(ceil(seconds*60)):state=brain.advance(1,feet,1.0/60,true,route)
	return state
func _initialize()->void:
	if not ClassDB.class_exists("NativeZombieAwareness"):
		GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	if not ClassDB.class_exists("NativeZombieAwareness"):check(false,"native awareness extension loads");quit(1);return
	var brain=ClassDB.instantiate("NativeZombieAwareness")
	check(brain.configure(6,42) and not brain.configure(6,42),"native awareness is bounded and configured once")
	check(brain.add_agent(1,Vector3.ZERO) and not brain.add_agent(1,Vector3.ZERO),"identities are unique")
	check(not brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,-8)),"unaware zombie cannot see behind itself")
	check(brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,12)),"forward player is eligible for occlusion-tested sight")
	check(brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(12,0,5)),"peripheral player inside the wider 140-degree cone can be noticed")
	check(brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,30)) and not brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,33)),"unaware sight improves to a finite 32 metre range")
	check(brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,-2)),"close awareness still requires the host visibility check")
	brain.observe(1,Vector3(0,0,12),false)
	check(brain.status(1).state=="idle","blocked sight does not alert")
	var roam:=run_for(brain,2.1,Vector3.ZERO)
	check(roam.state=="wander" and roam.goal.length()>=4 and roam.goal.length()<=9 and not roam.combat,"idle chooses a bounded randomized roaming goal without a combat target")
	check(not brain.accept_roam(1,Vector3.INF) and brain.status(1).state=="idle","unsupported roaming rejects before movement")
	brain.observe(1,Vector3(0,0,12),true)
	check(brain.status(1).state=="chase" and brain.status(1).combat,"confirmed sight enters pursuit")
	check(brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,-30)),"engaged tracking has range and bearing hysteresis")
	brain.observe(1,Vector3(0,0,12),false)
	brain.observe(1,Vector3(20,0,20),false)
	check(brain.status(1).state=="investigate" and brain.status(1).goal==Vector3(0,0,12) and not brain.status(1).combat,"lost sight commits to last seen position without tracking the hidden player")
	var frozen:Dictionary=brain.status(1)
	for i in 300:brain.advance(1,Vector3.ZERO,1.0/60,false,"following")
	check(brain.status(1)==frozen,"suspension freezes intent and memory timers")
	var search:Dictionary=brain.advance(1,Vector3(0,0,12),1.0/60,true,"arrived")
	check(search.state=="search" and search.goal.distance_to(Vector3(0,0,12))<=4,"arrival searches near last sighting")
	check(run_for(brain,6.1,Vector3(0,0,12)).state=="idle","unsuccessful search loses interest")
	brain.provoke(1,Vector3(0,0,-8))
	check(brain.status(1).state=="investigate" and brain.status(1).ignore_seconds==0,"being struck provokes investigation even from behind")
	check(run_for(brain,18.1,Vector3.ZERO).state=="idle","unreached last sighting expires after eighteen seconds")
	brain.provoke(1,Vector3(0,0,12));brain.observe(1,Vector3(0,0,12),true)
	check(run_for(brain,6.1,Vector3.ZERO,"blocked").state=="idle" and brain.status(1).ignore_seconds>9,"unreachable visible player does not cause endless blocked pursuit")
	brain.observe(1,Vector3(0,0,12),true)
	check(brain.status(1).state=="idle","blocked-pursuit cooldown prevents immediate reacquisition")
	brain.clear()
	var listener=ClassDB.instantiate("NativeZombieAwareness");listener.configure(1,5);listener.add_agent(1,Vector3.ZERO)
	check(not listener.hear(1,Vector3.ZERO,Vector3(0,0,-8),7),"footsteps beyond their declared radius are inaudible")
	check(listener.hear(1,Vector3.ZERO,Vector3(0,0,-6),7) and listener.status(1).state=="investigate" and not listener.status(1).combat,"audible footsteps behind the zombie start investigation without magical sight")
	check(not listener.hear(1,Vector3.ZERO,Vector3(4,0,-4),7) and listener.status(1).goal==Vector3(0,0,-6),"sound investigation retains its clue instead of continuously tracking a hidden player")
	for id in 6:check(brain.add_agent(id+1,Vector3.ZERO),"bounded resident "+str(id+1))
	check(not brain.add_agent(7,Vector3.ZERO),"seventh awareness record rejects")
	brain.remove_agent(1);check(brain.add_agent(7,Vector3.ZERO),"retirement releases capacity")
	DirAccess.make_dir_recursive_absolute("res://reports")
	FileAccess.open("res://reports/zombie_awareness.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("ZOMBIE_AWARENESS checks=",checks," failures=",failures);quit(1 if failures else 0)
