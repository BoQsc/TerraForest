# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
const DEFINITIONS={
	"torso":{"health":180,"parent":""},"head":{"health":50,"parent":"torso"},
	"upper_arm_l":{"health":50,"parent":"torso"},"forearm_l":{"health":38,"parent":"upper_arm_l"},"hand_l":{"health":24,"parent":"forearm_l"},
	"upper_arm_r":{"health":50,"parent":"torso"},"forearm_r":{"health":38,"parent":"upper_arm_r"},"hand_r":{"health":24,"parent":"forearm_r"},
	"thigh_l":{"health":65,"parent":"torso"},"shin_l":{"health":52,"parent":"thigh_l"},"foot_l":{"health":32,"parent":"shin_l"},
	"thigh_r":{"health":65,"parent":"torso"},"shin_r":{"health":52,"parent":"thigh_r"},"foot_r":{"health":32,"parent":"shin_r"}}
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func fresh()->RefCounted:
	var anatomy:RefCounted=ClassDB.instantiate("NativeZombieAnatomy")
	anatomy.configure(DEFINITIONS)
	return anatomy
func _initialize()->void:
	if not ClassDB.class_exists("NativeZombieAnatomy"):GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var anatomy=ClassDB.instantiate("NativeZombieAnatomy")
	check(not anatomy.configure({}) and anatomy.configure(DEFINITIONS) and not anatomy.configure(DEFINITIONS),"native anatomy validates and configures once")
	for part:String in DEFINITIONS:
		var region:=fresh();var hit:Dictionary=region.hit(part,15)
		check(hit.ok and hit.health==165 and hit.remaining==165 and hit.applied==15 and region.snapshot().limbs.torso==165 and not hit.sever,"every hit region spends the same shared health: "+part)
	var focused:=fresh();var distributed:=fresh()
	for part:String in ["head","forearm_l","hand_r","shin_l","foot_r","torso"]:
		focused.hit("torso",15);distributed.hit(part,15)
	check(focused.snapshot().health==90 and distributed.snapshot().health==90,"changing hit regions cannot reset health or reduce total damage")
	var unarmed:=fresh();var dismembered:=false
	for strike in 36:
		var punch:Dictionary=unarmed.hit("hand_l",5,false,"unarmed")
		dismembered=dismembered or punch.sever
	check(unarmed.snapshot().health==0 and not dismembered,"repeated punches kill through shared health without tearing off a hand")
	var blunt:=fresh();var blunt_hit:Dictionary={}
	for strike in 4:
		blunt_hit=blunt.hit("hand_l",20,false,"melee")
		check(blunt_hit.sever==(strike==3),"ordinary melee can sever a hand on the fourth focused hit: "+str(strike+1))
	check(blunt_hit.health==100,"increased melee severing leaves shared damage unchanged")
	var axe:=fresh();var axe_hit:Dictionary={}
	for strike in 4:
		axe_hit=axe.hit("hand_r",15,false,"cutting")
		check(axe_hit.sever==(strike==3),"light cutting now severs a hand on the fourth focused hit: "+str(strike+1))
	check(axe_hit.health==120 and axe_hit.body_damage==15,"cutting detachment does not skip shared damage")
	var forearm:=fresh();var forearm_hit:Dictionary={}
	for strike in 6:
		forearm_hit=forearm.hit("forearm_l",15,false,"cutting")
		check(forearm_hit.sever==(strike==5),"light cutting now severs a forearm on the sixth focused hit: "+str(strike+1))
	var hit:Dictionary=anatomy.hit("forearm_l",15,false,"cutting")
	check(hit.ok and hit.remaining==165 and hit.limb_remaining==30.5 and not hit.sever,"limb integrity is separate from shared combat health")
	hit=anatomy.hit("forearm_l",35,false,"heavy")
	check(hit.ok and hit.sever and hit.health==130 and hit.body_damage==35,"a powerful strike can sever while still deducting full shared damage")
	check(anatomy.detach("forearm_l") and not anatomy.detach("forearm_l"),"one anatomical chain detaches only once")
	var state:Dictionary=anatomy.snapshot()
	check(state.missing.forearm_l and state.missing.hand_l and not state.missing.upper_arm_l and not state.missing.forearm_r,"detachment disables descendants while preserving parent and opposite arm")
	for invalid in [["hand_l",5.0],["unknown",5.0],["torso",0.0],["torso",-1.0],["head",NAN],["head",INF]]:
		check(not anatomy.hit(invalid[0],invalid[1]).ok and anatomy.snapshot()==state,"invalid or missing-region hit cannot mutate health: "+str(invalid))
	check(not anatomy.hit("torso",10,false,"unknown").ok and anatomy.snapshot()==state,"unknown impact profiles cannot mutate health")
	hit=anatomy.hit("head",20,false,"firearm")
	check(hit.ok and hit.body_damage==20 and hit.limb_remaining==30 and hit.remaining==110,"firearm damage uses shared health with stronger sever trauma")
	hit=anatomy.hit("head",30,false,"firearm")
	check(hit.sever and hit.dead and hit.health==0 and hit.body_damage==110,"firearm head destruction remains fatal and accounts for the full health loss")
	anatomy.detach("head");anatomy.kill();state=anatomy.snapshot()
	check(not state.alive and state.health==0 and state.limbs.torso==0,"death health is consistently clamped to zero")
	hit=anatomy.hit("hand_r",24,false,"heavy")
	check(hit.ok and hit.sever and hit.body_damage==0 and hit.health==0,"a corpse can lose another limb without reviving or negative vitality")
	check(not anatomy.track_ragdoll([]),"empty ragdoll groups reject")
	var forced:=fresh();hit=forced.hit("head",0,true)
	check(hit.sever and hit.dead and hit.remaining==0 and forced.snapshot().limbs.torso==0,"explicit developer severing remains available and keeps shared health consistent")
	DirAccess.make_dir_recursive_absolute("res://reports")
	FileAccess.open("res://reports/zombie_anatomy.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("ZOMBIE_ANATOMY checks=",checks," failures=",failures);quit(1 if failures else 0)
