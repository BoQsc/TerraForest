# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var saves:=0
var save_errors:=0
var stages:Dictionary={}
func run()->void:
 var slot:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--world-slot=travel_save_check_"):slot=arg.get_slice("=",1)
 if not check(not slot.is_empty(),"disposable travel-save slot required"):quit(1);return
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"populated world ready"):await done();return
 game.terrain.save_completed.connect(func(ok:bool):save_errors+=int(not ok);saves+=1)
 game.terrain.stage_measured.connect(func(label:String,ms:float):stages[label]=maxf(stages.get(label,0.0),ms))
 game.fly=true;game.player.position.y+=12;game.pitch=0;game.camera.rotation.x=0
 game.controls.set_key(KEY_W,true,Time.get_ticks_usec());game.controls.set_key(KEY_SHIFT,true,Time.get_ticks_usec())
 var initial:Vector3=game.player.position
 var results:Array=[]
 for mode:String in ["baseline","cold_save","warm_save"]:
  var frames:Array=[];stages.clear();var requested:=false;var dispatch_us:=0;var start:=Time.get_ticks_usec();var last:=start;var count_before:=saves
  for frame in 180:
   game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
   if mode!="baseline" and frame==10:
    var begin:=Time.get_ticks_usec();game.terrain.save_world();dispatch_us=Time.get_ticks_usec()-begin;requested=true
   await process_frame
   var now:=Time.get_ticks_usec();frames.append((now-last)/1000.0);last=now
  if requested:check(await wait_for(func():return saves>count_before,15),"save completes during travel")
  frames.sort();results.append({"mode":mode,"dispatch_us":dispatch_us,"capture":game.persistence.last_capture.duplicate(true),"worker":game.terrain.backend.save_profile(),"frame_p95_ms":frames[170],"frame_max_ms":frames.back(),"stages":stages.duplicate(),"distance":game.player.position.distance_to(initial)})
 check(save_errors==0,"actual world saves succeed")
 check(game.player.position.distance_to(initial)>20,"native flight actually travels through world")
 FileAccess.open("res://reports/world_travel_save.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"samples":results},"  "))
 await done()
func done()->void:
 game._clear_motion();game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 print("WORLD_TRAVEL_SAVE failures=",failures);quit(1 if failures else 0)
