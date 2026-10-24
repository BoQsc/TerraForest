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
func _initialize()->void:
	if not ClassDB.class_exists("NativeZombieAnatomy"):GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var anatomy=ClassDB.instantiate("NativeZombieAnatomy")
	check(not anatomy.configure({}) and anatomy.configure(DEFINITIONS) and not anatomy.configure(DEFINITIONS),"native anatomy validates and configures once")
	var hit:Dictionary=anatomy.hit("forearm_l",15)
	check(hit.ok and hit.remaining==23 and is_equal_approx(hit.health,174.75) and not hit.sever,"a limb wound damages both its own pool and body vitality")
	hit=anatomy.hit("forearm_l",23)
	check(hit.ok and hit.sever and is_equal_approx(hit.health,166.7) and hit.body_damage>0,"the severing blow still damages body vitality")
	check(anatomy.detach("forearm_l") and not anatomy.detach("forearm_l"),"one anatomical chain detaches only once")
	var state:Dictionary=anatomy.snapshot()
	check(state.missing.forearm_l and state.missing.hand_l and not state.missing.upper_arm_l and not state.missing.forearm_r,"detachment disables descendants while preserving parent and opposite arm")
	for invalid in [["hand_l",5.0],["unknown",5.0],["torso",0.0],["torso",-1.0],["head",NAN],["head",INF]]:
		check(not anatomy.hit(invalid[0],invalid[1]).ok and anatomy.snapshot()==state,"invalid or missing-region hit cannot mutate health: "+str(invalid))
	hit=anatomy.hit("head",20)
	check(hit.ok and is_equal_approx(hit.body_damage,35) and hit.remaining==30,"head wounds are a stronger vital weak point")
	hit=anatomy.hit("head",30)
	check(hit.sever and hit.dead and hit.health==0,"head destruction is fatal even with body vitality remaining")
	anatomy.detach("head");anatomy.kill();state=anatomy.snapshot()
	check(not state.alive and state.health==0 and state.limbs.torso==0,"death health is consistently clamped to zero")
	hit=anatomy.hit("hand_r",24)
	check(hit.ok and hit.sever and hit.body_damage==0 and hit.health==0,"a corpse can lose another limb without reviving or negative vitality")
	check(not anatomy.track_ragdoll([]),"empty ragdoll groups reject")
	DirAccess.make_dir_recursive_absolute("res://reports")
	FileAccess.open("res://reports/zombie_anatomy.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("ZOMBIE_ANATOMY checks=",checks," failures=",failures);quit(1 if failures else 0)
