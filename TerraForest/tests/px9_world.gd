# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func ticks(count:int)->void:
 for i in count:
  await physics_frame
  game.app_focused=true
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
 game.terrain.backend.disk_cache.enabled=false;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+90000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 check(not game.loading_active,"temporary gameplay world ready")
 if game.loading_active:game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();quit(1);return
 game.combat.action_input_owned=func()->bool:return true
 game.player_view.entry.finish();game._clear_motion();game.app_focused=true
 if game.session_menu.developer:game.session_menu.toggle_developer()
 game.session_menu.set_open(false);game.zombies.population_enabled=false;game.zombies.clear()
 var inventory:RefCounted=game.player_hud.inventory
 check(inventory.grant_items(PackedInt64Array([9,1,228,40]),inventory.snapshot().revision).ok,"native bag receives handgun and cartridges")
 check(game.player_hud.equip_item(9),"gameplay belt equips PX9")
 await ticks(80)
 check(game.tool_view.human.current==9 and game.combat.state.get_rounds(9)==0,"new handgun starts empty")
 check(game.combat.reload(),"host accepts empty reload")
 await ticks(220)
 check(game.combat.state.get_rounds(9)==15 and game.combat.rounds_in_bag(9)==25,"paired reload consumes exactly fifteen matching cartridges")
 check(game.combat.fire(),"host launches handgun projectile")
 check(game.combat.state.get_rounds(9)==14 and game.combat.shots==1,"one trigger consumes exactly one handgun round")
 await ticks(30)
 check(game.combat.state.get_rounds(9)==14,"released trigger does not repeat fire")
 var saved:PackedByteArray=game.combat.capture()
 check(game.combat.state.take_round(9) and game.combat.restore(saved) and game.combat.state.get_rounds(9)==14,"host combat save component restores pistol magazine")
 game.session_menu.set_open(true)
 check(not game.combat.fire() and not game.combat.reload(),"menus block handgun actions")
 game.session_menu.set_open(false);await ticks(30)
 check(game.combat.reload(),"partial reload starts")
 game.player_hud.equip_item(1);await ticks(110)
 check(game.combat.state.get_rounds(9)==14 and game.combat.rounds_in_bag(9)==25,"switching tools cancels reload without consuming cartridges")
 check(game.player_hud.equip_item(9),"PX9 re-equips for held-trigger test")
 await ticks(80)
 var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
 Input.parse_input_event(press);Input.flush_buffered_events()
 await ticks(90)
 var held_rounds:int=game.combat.state.get_rounds(9)
 check(held_rounds<=12 and held_rounds>0,"holding left mouse repeats shots at the existing recoil cadence")
 press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=false
 Input.parse_input_event(press);Input.flush_buffered_events()
 await ticks(40)
 check(game.combat.state.get_rounds(9)==held_rounds,"releasing left mouse immediately stops repeated fire")
 game.session_menu.set_open(true)
 press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
 Input.parse_input_event(press);Input.flush_buffered_events();await ticks(40)
 check(game.combat.state.get_rounds(9)==held_rounds,"menu blocks held-trigger repetition")
 press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=false
 Input.parse_input_event(press);Input.flush_buffered_events()
 game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"temporary world shuts down safely")
 game.free();await process_frame;await process_frame
 print("PX9_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
