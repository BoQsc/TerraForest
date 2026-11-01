# SPDX-License-Identifier: 0BSD
extends SceneTree

var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func advance(brain:RefCounted,seconds:float,active:bool=true)->Dictionary:
	var result:Dictionary
	for tick in int(ceil(seconds*60.0)):
		result=brain.advance(1,Vector3.ZERO,1.0/60.0,active,"following")
	return result

func _initialize()->void:
	if not ClassDB.class_exists("NativeZombieAwareness"):
		GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://addons/characters/runtime/assets/zombie.encounters.json"))
	var brain=ClassDB.instantiate("NativeZombieAwareness")
	check(brain.configure(6,1703) and brain.add_agent(1,Vector3.ZERO),"native bounded encounter fixture initializes")
	for name:String in catalog.profiles:
		check(brain.set_profile(1,catalog.profiles[name]),"shipped profile validates: "+name)
	check(brain.set_profile(1,catalog.profiles.shambler),"gentle surface temperament configures")
	var baseline:Dictionary=brain.status(1)
	for changes:Dictionary in [{"unknown":1},{"sight_range":INF},{"notice_seconds":-1},{"idle_min":4,"idle_max":1},{"roam_min":12,"roam_max":2},{"tracking_range":10},{"id":3},{"walk_speed":"1.0"}]:
		var broken:Dictionary=catalog.profiles.shambler.duplicate(true)
		broken.merge(changes,true)
		check(not brain.set_profile(1,broken) and brain.status(1)==baseline,"invalid profile is atomic: "+str(changes))
	check(not brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,25)),"ordinary surface zombie no longer sees player across the old 32-metre radius")
	brain.observe(1,Vector3(0,0,12),true)
	check(brain.status(1).state=="suspicious" and not brain.status(1).moving and not brain.status(1).combat,"seeing player starts a non-attacking recognition pause")
	advance(brain,0.5)
	check(brain.status(1).state=="suspicious","single glimpse does not immediately chase")
	brain.observe(1,Vector3(0,0,12),false)
	check(brain.status(1).state=="idle" and brain.status(1).notice_seconds==0,"breaking sight during recognition cancels alert")
	brain.observe(1,Vector3(0,0,12),true)
	advance(brain,1.2)
	check(brain.status(1).state=="chase" and brain.status(1).combat,"sustained sight starts pursuit")
	var before_pause:Dictionary=brain.status(1)
	advance(brain,4,false)
	check(brain.status(1)==before_pause,"menu/readiness suspension freezes all encounter timers")
	for tick in 60*23:
		brain.observe(1,Vector3(0,0,12),true)
		brain.advance(1,Vector3.ZERO,1.0/60.0,true,"following")
	check(not brain.status(1).combat and brain.status(1).ignore_seconds>10,"repeated visible sightings cannot renew pursuit forever")
	brain.provoke(1,Vector3(0,0,-8))
	brain.observe(1,Vector3(0,0,-8),true)
	check(brain.status(1).combat and brain.status(1).interest_seconds>30,"player attack overrides disinterest without a recognition delay")
	brain.observe(1,Vector3(0,0,-8),false)
	brain.observe(1,Vector3(9,0,8),false)
	check(brain.status(1).goal==Vector3(0,0,-8),"lost sight retains a clue rather than following hidden player coordinates")
	advance(brain,12.1)
	check(not brain.status(1).combat and brain.status(1).state=="idle","unsuccessful investigation ends")
	brain.remove_agent(1);brain.add_agent(1,Vector3.ZERO);brain.set_profile(1,catalog.profiles.shambler)
	check(not brain.hear(1,Vector3.ZERO,Vector3(0,0,6),7),"gentle profile reduces surface footstep attraction")
	check(brain.hear(1,Vector3.ZERO,Vector3(0,0,4),7),"nearby noise still prompts investigation")
	for pose:int in [1,2]:
		brain.remove_agent(1);brain.add_agent(1,Vector3.ZERO);brain.set_profile(1,catalog.profiles.shambler)
		check(brain.set_sleeping(1,pose),"sleeper pose configures: "+str(pose))
		var asleep:Dictionary=brain.status(1)
		advance(brain,60)
		check(brain.status(1)==asleep and not asleep.moving and not asleep.combat,"sleepers perform no roaming or countdown work")
		check(not brain.wants_sight(1,Vector3.ZERO,Vector3.BACK,Vector3(0,0,1)),"sleepers do not magically see player")
		brain.observe(1,Vector3(0,0,1),true)
		check(brain.status(1)==asleep,"accidental sight callback cannot wake sleeper")
		if pose==1:
			check(not brain.hear(1,Vector3.ZERO,Vector3(0,0,8),7),"distant noise cannot wake sleeper")
			check(brain.hear(1,Vector3.ZERO,Vector3(0,0,3),7),"audible footstep wakes seated sleeper")
		else:
			brain.provoke(1,Vector3(0,0,3))
		check(brain.status(1).state=="waking" and not brain.status(1).moving and not brain.status(1).combat,"waking never permits an instant standing attack")
		check(not brain.finish_waking(1),"animation completion cannot be acknowledged early")
		advance(brain,1)
		var waking:Dictionary=brain.status(1)
		advance(brain,4,false)
		check(brain.status(1)==waking,"suspended wake animation timer freezes")
		brain.provoke(1,Vector3(1,0,3))
		check(brain.status(1).wake_elapsed==waking.wake_elapsed,"repeated hits do not restart wake animation")
		advance(brain,4)
		check(brain.status(1).wake_ready and brain.status(1).state=="waking" and not brain.status(1).combat,"elapsed wake time still requires animation and clearance acknowledgement")
		check(brain.finish_waking(1) and brain.status(1).state=="investigate" and brain.status(1).sleep_pose==0,"completed wake investigates the noise position")
		check(not brain.finish_waking(1) and not brain.set_sleeping(1,pose),"completed active encounters cannot replay wake or be put to sleep")
	var population=ClassDB.instantiate("NativeZombiePopulation")
	population.initialize(1703,Vector3(800,0,1310))
	var saved:PackedByteArray=population.capture_snapshot()
	var twins=ClassDB.instantiate("NativeZombiePopulation")
	twins.restore_snapshot(saved)
	var counts:Dictionary={"shambler":0,"roamer":0,"restless":0,"missing_arm":0,"missing_leg":0}
	var deterministic:=true
	var valid_injuries:=true
	var candidate_id:=0
	for identity in range(1,2501):
		var descriptor:Dictionary=population.encounter(identity)
		deterministic=deterministic and descriptor==twins.encounter(identity)
		counts[descriptor.profile]+=1
		var vitals:PackedByteArray=descriptor.initial_vitals
		if vitals.is_empty():continue
		var mask:=vitals.decode_u32(56)
		counts["missing_leg" if mask&(1<<9|1<<12) else "missing_arm"]+=1
		valid_injuries=valid_injuries and twins.update_resident(identity,twins.resident(identity).position,0,vitals) and vitals.decode_float(0)==180
		candidate_id=identity
	check(deterministic,"temperament and congenital limb loss are stable across reload and independent of activation order")
	check(valid_injuries and candidate_id>0,"all generated missing-limb chains satisfy native anatomy storage invariants with full overall health")
	check(counts.shambler>1100 and counts.roamer>600 and counts.restless>200 and counts.restless<400,"most surface zombies are quiet; faster temperament is a minority")
	check(counts.missing_arm>400 and counts.missing_leg>80 and counts.missing_leg<220,"variety includes arm amputees and fewer crawling leg amputees")
	check(population.capture_snapshot()==saved,"reading encounter recipes does not rewrite legacy save bytes")
	var injured:PackedByteArray=population.encounter(candidate_id).initial_vitals
	check(population.update_resident(candidate_id,Vector3(500,80,500),0,injured),"first admission persists starting anatomy")
	check(population.encounter(candidate_id).initial_vitals.is_empty(),"already activated inhabitants never acquire a new injury on reload")
	check(twins.restore_snapshot(population.capture_snapshot()) and twins.resident(candidate_id).vitals==injured,"binary save roundtrip preserves initial missing limbs")
	check(population.encounter(0).is_empty() and population.encounter(999999).is_empty(),"invalid identities have no encounter recipe")
	DirAccess.make_dir_recursive_absolute("res://reports/zombie_expansion")
	FileAccess.open("res://reports/zombie_expansion/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"distribution":counts},"  "))
	print("ZOMBIE_EXPANSION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
