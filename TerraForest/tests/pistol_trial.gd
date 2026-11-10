# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/pistol_trial_settings_path","")
	run.call_deferred()
func run()->void:
	var trial=preload("res://addons/player_runtime/pistol_trial.gd").new()
	check(trial.values.size()==7 and not false in trial.values.values(),"seven independent trial effects default on")
	var menu=preload("res://addons/player_runtime/session_menu.gd").new()
	var controls:=VBoxContainer.new();root.add_child(controls);trial.add_controls(menu,controls)
	for key:String in trial.OPTIONS:
		var toggle:CheckButton=controls.get_node("Pistol_"+key)
		toggle.button_pressed=false
		check(not trial.values[key],"menu disables "+key)
		toggle.button_pressed=true
		check(trial.values[key],"menu restores "+key)
	var moved:=Transform3D.IDENTITY
	for frame in 60:moved=trial.motion(1.0/60,Vector3(2,0,-4),true,2,false)
	check(moved.origin.length()>.001 and moved.origin.length()<.03,"walking motion is visible and bounded")
	trial.set_option("bobbing",false,false);trial.set_option("sway",false,false)
	check(trial.motion(.016,Vector3(2,0,-4),true,2,false)==Transform3D.IDENTITY,"both motion switches remove offsets completely")
	trial.set_option("bobbing",true,false)
	for frame in 60:trial.motion(1.0/60,Vector3(0,0,-4),true,0,false)
	for frame in 180:moved=trial.motion(1.0/60,Vector3.ZERO,true,0,false)
	check(moved.origin.length()<.000001,"walking bob settles while stationary")
	check(trial.extra_sever("forearm_l",.19) and not trial.extra_sever("forearm_l",.2) and not trial.extra_sever("head",0) and not trial.extra_sever("torso",0),"extra sever roll applies only to limbs at the documented threshold")
	trial.set_option("dismemberment",false,false)
	check(not trial.extra_sever("forearm_l",0),"disabled trial restores durability-only dismemberment")
	trial.settings_path="user://pistol_trial_check_%d.cfg"%OS.get_process_id()
	trial.set_option("blood",false)
	var restored=preload("res://addons/player_runtime/pistol_trial.gd").new();restored.settings_path=trial.settings_path;restored.load_settings()
	check(restored.values==trial.values,"independent preferences persist across reload")
	DirAccess.remove_absolute(trial.settings_path);trial.settings_path=""
	var baseline:=Label.new();root.add_child(baseline)
	var reticle=preload("res://addons/player_runtime/pistol_crosshair.gd").new();root.add_child(reticle);reticle.baseline=baseline
	reticle.update_state(.016,true,false,4);reticle.shot();reticle.confirmed_hit()
	check(reticle.visible and not baseline.visible and reticle.bloom>0 and reticle.hit_time>0,"crosshair owns baseline only while enabled and shows confirmed feedback")
	reticle.update_state(.016,false,false,0)
	check(not reticle.visible and baseline.visible and reticle.bloom==0 and reticle.hit_time==0,"disable restores baseline and clears transient feedback")
	reticle.update_state(.016,true,false,0)
	reticle.update_state(.016,false,false,0,false)
	check(not baseline.visible,"vehicle transition cannot restore a hidden baseline crosshair")
	var actor=preload("res://addons/characters/runtime/zombie.gd").new();root.add_child(actor);actor.set_behavior(false)
	check(actor.initialized,"actual zombie native anatomy and modifier initialized")
	var health:float=actor.health
	actor.receive_hit("torso",1,Vector3(0,1.4,0),Vector3(0,0,-2),false,"firearm",false,false)
	check(actor.health<health and not actor.hit_reaction.is_active() and actor._hit_timer==0,"both response toggles off preserve accepted damage without flinch")
	actor.receive_hit("torso",1,Vector3(.15,1.4,0),Vector3(0,0,-2),false,"firearm",true,true)
	check(actor.hit_reaction.is_active() and actor._hit_timer>0,"native spring and authored animation activate together")
	actor.receive_hit("forearm_l",1,Vector3(0,1.4,0),Vector3(0,0,-2),true,"firearm",false,false)
	check(actor.missing.get("forearm_l",false) and actor.alive,"extra limb sever uses authoritative anatomy without killing torso")
	var effects=preload("res://addons/impact_effects/impact_effects.gd").new();root.add_child(effects)
	effects.firearm_contact({"kind":"zombie","blood":false,"position":Vector3.ZERO,"normal":Vector3.UP})
	check(effects.emitted_events==0 and effects.pool.is_empty(),"disabled pistol blood allocates no particles")
	effects.firearm_contact({"kind":"zombie","blood":true,"pistol_splash":true,"position":Vector3.ZERO,"normal":Vector3.UP})
	check(effects.emitted_events==1 and effects.pool.size()==1 and effects.last_event.count==12,"pistol splash uses twelve particles in the existing bounded GPU pool")
	for index in 20:effects.firearm_contact({"kind":"zombie","position":Vector3.ZERO,"normal":Vector3.UP})
	check(effects.pool.size()<=effects.POOL_LIMIT,"blood saturation respects the existing effect cap")
	# Parse integration owners as well as exercising isolated adapters.
	check(load("res://addons/player_runtime/combat_world.gd")!=null and load("res://addons/player_runtime/player_view.gd")!=null and load("res://addons/characters/runtime/zombie_world.gd")!=null,"integration scripts compile")
	effects.free();actor.free();reticle.free();baseline.free();controls.free();menu.free()
	await process_frame
	print("PISTOL_TRIAL checks=",checks," failures=",failures);quit(1 if failures else 0)
