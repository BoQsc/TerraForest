# SPDX-License-Identifier: 0BSD
extends SceneTree
var game
var failure:=""
var samples:Array=[]
func _initialize()->void:run.call_deferred()
func ready_world(seconds:float)->bool:
 var deadline:=Time.get_ticks_msec()+int(seconds*1000)
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 return not game.loading_active
func run()->void:
 game=load("res://demo/world.tscn").instantiate()
 game.temporary_world=true;game.max_fps=60;game.background_fps=60
 root.add_child(game)
 if not await ready_world(90):failure="initial loading timeout";await finish();return
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 if layout.is_empty():failure="missing regional layout";await finish();return
 var hub:Vector3=layout.sites[0].position
 var west:Vector3=layout.sites[1].position
 var direction:Vector3=(west-hub);direction.y=0;direction=direction.normalized()
 # Initial staging only. All subsequent travel uses ordinary player movement.
 game.teleport(hub+direction*100)
 if not await ready_world(60):failure="departure loading timeout";await finish();return
 game.fly=false;game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var target:Vector3=west-direction*85
 var deadline:=Time.get_ticks_msec()+100000
 var previous:=Time.get_ticks_usec()
 var next_sample:=Time.get_ticks_msec()
 var frames:Array[float]=[]
 while Time.get_ticks_msec()<deadline:
  var offset:Vector3=target-game.player.position;offset.y=0
  if offset.length()<2.0:break
  game.yaw=atan2(-offset.x,-offset.z);game.player.rotation.y=game.yaw
  game.camera.rotation=Vector3(-0.1,0,0);game.app_focused=true
  game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
  game.controls.set_key(KEY_SHIFT,true,Time.get_ticks_usec())
  await process_frame
  var now:=Time.get_ticks_usec();frames.append(float(now-previous)/1000.0);previous=now
  if Time.get_ticks_msec()>=next_sample:
   var p:Vector3=game.player.position
   samples.append({"position":[p.x,p.y,p.z],"remaining_m":offset.length(),"loading":game.loading_active,"on_floor":game.player.is_on_floor(),"collision_ready":game.terrain.player_region_ready(p)})
   next_sample=Time.get_ticks_msec()+500
 var remaining:Vector3=target-game.player.position;remaining.y=0
 if remaining.length()>2.0:failure="did not reach western approach within 100 seconds"
 frames.sort()
 var result:={"failure":failure,"remaining_m":remaining.length(),"samples":samples,"frame_p95_ms":frames[int(frames.size()*0.95)] if not frames.is_empty() else 0,"frame_max_ms":frames[-1] if not frames.is_empty() else 0,"scope":"One continuous sprint along the central-west arterial; one initial staging teleport. No vehicle or long-run thermal claim."}
 var file:=FileAccess.open("res://reports/regional_road_travel.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/regional_road_travel.png")
 await finish()
func finish()->void:
 if game!=null:
  game.controls.clear(Time.get_ticks_usec());game.shutdown_requested=true
  await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("REGIONAL_ROAD_TRAVEL failures=",0 if failure.is_empty() else 1," ",failure)
 quit(0 if failure.is_empty() else 1)
