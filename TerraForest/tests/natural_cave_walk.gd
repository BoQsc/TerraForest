# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var paths:Array=[]
var failures:=0
func wait_for(predicate:Callable,seconds:int=35)->bool:
 var deadline:=Time.get_ticks_msec()+seconds*1000
 while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
 return predicate.call()
func walk_to(target:Vector3)->bool:
 var rows:Array=[];var deadline:=Time.get_ticks_msec()+10000;var ticks:=0
 while Time.get_ticks_msec()<deadline:
  var delta:Vector3=target-game.player.position;delta.y=0
  if delta.length()<0.3:break
  game.yaw=atan2(-delta.x,-delta.z);game.player.rotation.y=game.yaw;game.camera.rotation=Vector3(-0.12,0,0)
  game.app_focused=true;game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
  await physics_frame;ticks+=1
  if ticks%15==0:rows.append({"position":game.player.position,"floor":game.player.is_on_floor(),"loading":game.loading_active})
 game.controls.clear(Time.get_ticks_usec())
 var distance:Vector3=target-game.player.position;distance.y=0
 paths.append({"target":target,"finish":game.player.position,"remaining":distance.length(),"rows":rows})
 return distance.length()<0.4 and game.player.is_on_floor()
func _initialize()->void:run.call_deferred()
func run()->void:
 var profile:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/natural_cave_access/profile.json"))
 var route:Dictionary=profile.routes[0]
 var start:Array=route.samples[0].floor
 var inward:Array=route.samples[32].floor
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await wait_for(func():return not game.loading_active):print("FAIL initial world load");failures+=1;await finish();return
 game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false;game.fly=false
 game.player.position=Vector3(start[0],start[1]+0.1,start[2]);game.terrain.focus=game.player.position
 game._begin_loading("Preparing cave entrance")
 if not await wait_for(func():return not game.loading_active):print("FAIL cave collision arrival");failures+=1;await finish();return
 game.set_physics_process(true);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;game.headlamp.visible=true
 for frame in 5:await physics_frame
 var into:bool=await walk_to(Vector3(inward[0],inward[1],inward[2]))
 print("PASS " if into else "FAIL ","walk from surface through generated entrance")
 if not into:failures+=1
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/natural_cave_access/inside.png")
 var out:bool=await walk_to(Vector3(start[0],start[1],start[2]))
 print("PASS " if out else "FAIL ","walk back to surface without jumping or edits")
 if not out:failures+=1
 await finish()
func finish()->void:
 game.controls.clear(Time.get_ticks_usec())
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/natural_cave_access/return.png")
 var file:=FileAccess.open("res://reports/natural_cave_access/walk.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures,"paths":paths,"scope":"Actual main-world player and streamed collision. Fixture relocates to exterior start; remaining travel uses walking without jumps or edits. Generator2 seed1703 cave0; no settlement-to-cave discovery claim."},"  "));file.close()
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("NATURAL_CAVE_WALK failures=",failures);quit(1 if failures else 0)
