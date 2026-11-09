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
 check(game.combat.reload_slot>=0,"empty equipped handgun automatically starts reload without a trigger")
 await ticks(220)
 check(game.combat.state.get_rounds(9)==15 and game.combat.rounds_in_bag(9)==25,"paired reload consumes exactly fifteen matching cartridges")
 check(game.combat.fire(),"host launches handgun projectile")
 check(game.combat.state.get_rounds(9)==14 and game.combat.shots==1,"one trigger consumes exactly one handgun round")
 var first_fx:Node3D=game.tool_view.human.handgun_flash
 check(first_fx.bursts==1 and first_fx.lamp.visible,"confirmed shot emits one muzzle burst and light pulse")
 if "--vfx-capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
  first_fx.set_process(false);game.tool_view.human.set_process(false)
  await process_frame;await RenderingServer.frame_post_draw
  DirAccess.make_dir_recursive_absolute("res://reports/px9_flash")
  root.get_texture().get_image().save_png("res://reports/px9_flash/gameplay_flash.png")
  first_fx.set_process(true);game.tool_view.human.set_process(true)
 await ticks(30)
 check(not first_fx.lamp.visible and not first_fx.cards[0].visible and first_fx.bursts==1,"muzzle flash expires without repeat bursts from animation events")
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
 var held_start_shots:int=game.combat.shots
 var press:=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
 Input.parse_input_event(press);Input.flush_buffered_events()
 await ticks(90)
 var held_rounds:int=game.combat.state.get_rounds(9)
 check(held_rounds<=12 and held_rounds>0,"holding left mouse repeats shots at the existing recoil cadence")
 check(game.tool_view.human.handgun_flash.bursts==game.combat.shots-held_start_shots,"held trigger emits exactly one muzzle burst per accepted shot")
 var human:Node=game.tool_view.human
 var actions:Array=[];human.px9.action_started.connect(func(action:String):actions.append(action))
 var shot_times:Array[float]=[]
 human.px9.action_started.connect(func(action:String):
  if action in ["fire","aim_fire","fire_last","aim_fire_last"]:shot_times.append(game.combat.timer))
 var aim:=InputEventMouseButton.new();aim.button_index=MOUSE_BUTTON_RIGHT;aim.pressed=true
 Input.parse_input_event(aim);Input.flush_buffered_events();await ticks(70)
 check(actions.has("aim_fire") and human.handgun_aiming,"held fire continues in aimed recoil after aim press")
 aim=InputEventMouseButton.new();aim.button_index=MOUSE_BUTTON_RIGHT;aim.pressed=false
 Input.parse_input_event(aim);Input.flush_buffered_events();await ticks(50)
 check(actions.has("fire") and not human.handgun_aiming,"aim release returns held fire to hip recoil")
 var longest_gap:=0.0
 for i in range(1,shot_times.size()):longest_gap=maxf(longest_gap,shot_times[i]-shot_times[i-1])
 print("Aim/fire maximum shot gap: ",longest_gap)
 check(shot_times.size()>=3 and longest_gap<.55,"aim press/release keeps held-fire cadence without a full aim-animation pause")
 check(game.combat.reload(),"reload interrupts recoil while the trigger remains held")
 var reload_shots:int=game.combat.shots
 await ticks(30)
 check(game.combat.shots==reload_shots and game.combat.reload_slot>=0,"held trigger cannot interrupt active reload")
 await ticks(210)
 check(game.combat.reload_slot<0 and game.combat.shots>reload_shots,"held fire resumes after reload completes")
 held_rounds=game.combat.state.get_rounds(9)
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
 game.session_menu.set_open(false);await ticks(40)
 while game.combat.state.get_rounds(9)>1:game.combat.state.take_round(9)
 check(game.combat.fire(),"last loaded round fires")
 await ticks(40)
 check(game.combat.reload_slot>=0,"last round automatically reloads after recoil even with trigger released")
 await ticks(220)
 check(game.combat.state.get_rounds(9)>0,"automatic empty reload replenishes the magazine")
 game.session_menu.set_open(true)
 var reserve:int=game.combat.rounds_in_bag(9)
 if reserve>0:inventory.consume_items(PackedInt64Array([228,reserve]),inventory.snapshot().revision)
 while game.combat.state.get_rounds(9)>0:game.combat.state.take_round(9)
 game.session_menu.set_open(false);await ticks(40)
 var shots_before:int=game.combat.shots
 var flashes_before:int=human.handgun_flash.bursts
 press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
 Input.parse_input_event(press);Input.flush_buffered_events();await ticks(60)
 check(game.combat.shots==shots_before and game.combat.reload_slot<0 and not actions.has("dry_fire"),"empty reserve neither shoots nor loops a dry-fire/reload animation")
 check(human.handgun_flash.bursts==flashes_before and not human.handgun_flash.lamp.visible,"empty trigger never emits a muzzle flash")
 press=InputEventMouseButton.new();press.button_index=MOUSE_BUTTON_LEFT;press.pressed=false
 Input.parse_input_event(press);Input.flush_buffered_events()
 game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"temporary world shuts down safely")
 game.free();await process_frame;await process_frame
 print("PX9_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
