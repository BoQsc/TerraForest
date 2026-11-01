# SPDX-License-Identifier: 0BSD
extends SceneTree

class Terrain extends Node:
	signal region_changed(bounds:AABB,revision:int)
	signal edit_resolved(outcome:Dictionary)
	signal message_changed(message:String)
	var epoch:=1
	var last_edit_outcome:Dictionary={}
	var changed_since_save:=false
	var edit_admission:Callable
	var require_published_shutdown:=false
	var latest_error:=""

var checks:=0
var failures:=0

class Enemy extends Node3D:
	var health:=25.0
	var alive:=true
	var PARTS:={"torso":{"health":100}}
	var limb_health:={"torso":100.0}
	var missing:={}

class Combat extends RefCounted:
	func apply_hit(target:Dictionary,damage:float,_direction:Vector3,_impact:String)->bool:
		if not target.zombie.alive:return false
		target.zombie.health=maxf(0,target.zombie.health-damage)
		target.zombie.alive=target.zombie.health>0
		return true

class Game extends Node3D:
	var player_hud:Node
	var camera:=Camera3D.new()
	var equipped_tool:=1
	var zombies:=Combat.new()
	var terrain:Node
	func _show_lake_notice(_message:String)->void:pass

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()

func run()->void:
	var hud=preload("res://addons/player_runtime/player_hud.gd").new();root.add_child(hud)
	var terrain:=Terrain.new();root.add_child(terrain)
	var mining=preload("res://addons/player_runtime/mining_rewards.gd").new();check(mining.attach(terrain,hud),"actual mining award adapter attaches")
	var dirty:=[0];hud.progression_changed.connect(func():dirty[0]+=1)
	hud.inventory.grant(201,20,hud.inventory.snapshot().revision);hud.refresh()
	check(hud.progression.snapshot().xp==0,"inventory grants and resource notification do not create XP")
	hud.set_open(true);hud.craft_recipe(0)
	check(hud.progression.snapshot().xp==6 and dirty[0]==1,"ordinary successful crafting awards XP and marks progression dirty")
	hud.craft_recipe(2)
	check(hud.progression.snapshot().xp==6,"failed recipe gives no experience")
	hud.developer_belt=true;hud.craft_recipe(0);hud.developer_belt=false
	check(hud.progression.snapshot().xp==6,"developer crafting does not train character")
	var removed:=PackedInt64Array();removed.resize(16);removed[1]=3;removed[8]=2
	terrain.last_edit_outcome={"status":"published","epoch":1,"ticket":1,"revision":1,"removed_samples":removed}
	mining.published(AABB(),1)
	check(hud.progression.snapshot().xp==11 and terrain.changed_since_save,"actual accepted mining accounting awards only published removed samples")
	mining.published(AABB(),1)
	check(hud.progression.snapshot().xp==11,"duplicate terrain publication cannot replay experience")
	terrain.last_edit_outcome.ticket=2;terrain.last_edit_outcome.removed_samples=PackedInt64Array();terrain.last_edit_outcome.removed_samples.resize(16)
	mining.published(AABB(),2)
	check(hud.progression.snapshot().xp==11,"placement and unchanged sample sets grant no mining XP")
	terrain.last_edit_outcome.status="rejected";mining.published(AABB(),2)
	check(hud.progression.snapshot().xp==11,"rejected edits cannot award XP")
	hud.award_experience(239);hud.show_side("Skills")
	check(hud.skills_panel.visible and not hud.character_panel.visible and not hud.crafting_content.visible and hud.progression.snapshot().level==2,"Skills panel is reachable beside existing inventory panels")
	hud.skills_panel.buttons[0].pressed.emit()
	check(hud.progression.snapshot().skills[1]==1 and hud.skill_damage(1,30)==32 and hud.progression.snapshot().points==0,"actual skill button spends point and changes native mining damage")
	hud.skills_panel.spend(2)
	check(hud.progression.snapshot().skills[2]==0,"click without points cannot overspend")
	var experience_rows:=0;var accumulated:=0
	for row:Dictionary in hud.resource_feed.active:
		if row.item==-1:experience_rows+=1;accumulated=row.count
	check(experience_rows==1 and accumulated==244,"XP notifications accumulate in the existing bounded resource feed")
	check(hud.resource_feed.pool.size()==5 and hud.slots.size()==22 and hud.belt.size()==10,"bounded feed and backpack/toolbelt separation preserved")
	var game:=Game.new();game.player_hud=hud;game.terrain=terrain;root.add_child(game);game.add_child(game.camera)
	var enemy:=Enemy.new();game.add_child(enemy)
	var attack=preload("res://addons/player_runtime/world_attack.gd").new();attack.game=game
	var target:Dictionary={"kind":"zombie","zombie":enemy,"part":"torso"}
	hud.equip_item(1);var combat_xp:int=hud.progression.snapshot().xp
	check(attack.apply_target(target) and enemy.health==10 and hud.progression.snapshot().xp==combat_xp+15,"real combat reward adapter pays only accepted health damage")
	check(attack.apply_target(target) and not enemy.alive and hud.progression.snapshot().xp==combat_xp+50,"finishing combat reward clamps overkill and adds its bonus once")
	check(not attack.apply_target(target) and hud.progression.snapshot().xp==combat_xp+50,"corpse hits cannot replay kill experience")
	game.free()
	hud.set_open(false);var before:PackedByteArray=hud.progression.capture_storage_snapshot();hud.skills_panel.spend(2)
	check(hud.progression.capture_storage_snapshot()==before,"hidden skill controls cannot spend")
	hud.resource_feed.clear();check(not hud.resource_feed.is_processing(),"XP UI does no idle processing")
	hud.free();terrain.free()
	print("PLAYER_PROGRESSION_GAMEPLAY ",JSON.stringify({"checks":checks,"failures":failures,"scope":"Real HUD/native progression, crafting, mining award adapter; synthetic publication, not world excavation"}))
	quit(1 if failures else 0)
