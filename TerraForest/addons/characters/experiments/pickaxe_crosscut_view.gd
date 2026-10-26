# SPDX-License-Identifier: 0BSD
extends "res://addons/characters/runtime/human_view.gd"
## Explicit preview only. Ordinary game entry points never instantiate this view.
const CANDIDATE=preload("res://addons/characters/runtime/assets/Human.pickaxe_crosscut.res")
var candidate_enabled:=true
func _ready()->void:
	super._ready()
	animation_player.add_animation_library("crosscut_candidate",CANDIDATE)
	for name in CANDIDATE.get_animation_list():clips[String(name)]="crosscut_candidate/"+String(name)
	equip(current)
func _motion_clip(action:String)->String:
	if current==1 and candidate_enabled and clips.has("FP_Pickaxe_Crosscut_"+action):return "FP_Pickaxe_Crosscut_"+action
	return super._motion_clip(action)
func swing_profile()->Dictionary:
	if current==1 and candidate_enabled:
		return {"clip":"FP_Pickaxe_Crosscut_Swing","contact":42.0/60,"duration":1.6}
	return super.swing_profile()
func set_candidate(enabled:bool)->void:
	cancel_swing();candidate_enabled=enabled;active_clip=""
	equip(current)
	# A/B review changes the hold immediately; incompatible grip poses must not
	# be interpolated into a temporary third pose while switching the comparison.
	animation_player.play(clips[_motion_clip("Idle")],0);animation_player.advance(0)
