# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var saves:=0
var save_errors:=0
var stages:Dictionary={}
var probe_started:=0
var probe_base_saves:=0
var probe:Dictionary={}
var mining_started:=0
var mining_finished:=false
func sampled(point:Vector3,height:float,token:int)->void:
 if token!=9001:return
 probe.query_ms=(Time.get_ticks_usec()-probe_started)/1000.0
 probe.query_before_save=saves==probe_base_saves
 probe.publication_pending=game.terrain.backend.publication_pending()
 mining_started=Time.get_ticks_usec()
 probe.mining_admitted=game.terrain.sculpt_sphere(Vector3(point.x,height-0.5,point.z),1.0)

func run()->void:
 var slot:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--world-slot=travel_save_check_"):slot=arg.get_slice("=",1)
 if not check(not slot.is_empty(),"disposable travel-save slot required"):quit(1);return
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"populated world ready"):await done();return
 game.terrain.height_received.connect(sampled)
 game.terrain.save_completed.connect(func(ok:bool):save_errors+=int(not ok);saves+=1)
 game.terrain.stage_measured.connect(func(label:String,ms:float):stages[label]=maxf(stages.get(label,0.0),ms))
 game.fly=true;game.player.position.y+=12;game.pitch=0;game.camera.rotation.x=0
 game.controls.set_key(KEY_W,true,Time.get_ticks_usec());game.controls.set_key(KEY_SHIFT,true,Time.get_ticks_usec())
 var initial:Vector3=game.player.position
 var results:Array=[]
 for mode:String in ["baseline","cold_save","warm_save"]:
  probe={};mining_started=0;mining_finished=false
  var frames:Array=[];stages.clear();var requested:=false;var dispatch_us:=0;var start:=Time.get_ticks_usec();var last:=start;var count_before:=saves
  for frame in 180:
   game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
   if mode!="baseline" and frame==10:
    var begin:=Time.get_ticks_usec();game.terrain.save_world();dispatch_us=Time.get_ticks_usec()-begin;requested=true
   if "--probe-save-progress" in OS.get_cmdline_user_args() and mode!="baseline" and frame==20:
    probe_started=Time.get_ticks_usec();probe_base_saves=count_before
    probe.query_admitted=game.terrain.backend.submit({"kind":"height","point":game.player.position,"token":9001})
   await process_frame
   if mining_started>0 and not mining_finished and not game.terrain.pending_edit:
    mining_finished=true;probe.mining_ms=(Time.get_ticks_usec()-mining_started)/1000.0;probe.mining_before_save=saves==count_before
   var now:=Time.get_ticks_usec();frames.append((now-last)/1000.0);last=now
  if requested:check(await wait_for(func():return saves>count_before,15),"save completes during travel")
  frames.sort();results.append({"mode":mode,"dispatch_us":dispatch_us,"capture":game.persistence.last_capture.duplicate(true),"worker":game.terrain.backend.save_profile(),"frame_p95_ms":frames[170],"frame_max_ms":frames.back(),"stages":stages.duplicate(),"distance":game.player.position.distance_to(initial),"progress_probe":probe.duplicate()})
 if "--probe-save-progress" in OS.get_cmdline_user_args():
  for result:Dictionary in results:
   if result.mode=="baseline":continue
   check(result.progress_probe.get("query_before_save",false) and result.progress_probe.get("publication_pending",false),"terrain query completes while publication is pending")
   check(result.progress_probe.get("mining_admitted",false) and result.progress_probe.get("mining_before_save",false),"mining publishes while save is pending")
 check(save_errors==0,"actual world saves succeed")
 check(game.player.position.distance_to(initial)>20,"native flight actually travels through world")
 FileAccess.open("res://reports/world_travel_save.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"samples":results},"  "))
 await done()
func done()->void:
 game._clear_motion();game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 print("WORLD_TRAVEL_SAVE failures=",failures);quit(1 if failures else 0)
