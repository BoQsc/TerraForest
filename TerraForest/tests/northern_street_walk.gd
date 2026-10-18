# SPDX-License-Identifier: 0BSD
extends "res://tests/regional_road_travel.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(60):failure="initial loading timeout";await finish();return
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var center:Vector3=layout.sites[3].position
 var streets:Array=[]
 for street:Dictionary in game.road_palette.prepared_streets:
  var a:Vector3=street.ends[0];var b:Vector3=street.ends[1]
  if a.distance_to(center)<150 and b.distance_to(center)<150 and absf(a.z-b.z)<0.1 and absf(a.x-b.x)>40:streets.append([a,b] if a.x<b.x else [b,a])
 var fitted:bool="--fitted-lots" in OS.get_cmdline_user_args()
 if streets.size()!=(3 if fitted else 2):failure="unexpected saved northern street count";await finish();return
 streets.sort_custom(func(a:Array,b:Array):return a[0].z<b[0].z)
 var left:Vector3=streets[0][0];var right:Vector3=streets[0][1]
 var corner:=Vector3(center.x,right.y,right.z)
 var route:Array[Vector3]=[corner,right,left,streets[1][0],streets[1][1],right,corner,center]
 if fitted:
  # Use the arterial between parallel streets, never cut across building lots.
  route=[corner,streets[0][0],streets[0][1],corner,center,streets[1][0],streets[1][1],center,Vector3(center.x,center.y,streets[2][0].z),streets[2][0],streets[2][1]]
 if "--loop-roads" in OS.get_cmdline_user_args():
  var side_count:=0
  for street:Dictionary in game.road_palette.prepared_streets:
   var a:Vector3=street.ends[0];var b:Vector3=street.ends[1]
   if a.distance_to(center)<100 and b.distance_to(center)<100 and absf(a.x-b.x)<0.1 and absf(a.z-b.z)>100:side_count+=1
  if side_count!=2:failure="expected two saved neighborhood side streets";await finish();return
  route=[corner,left,right,streets[2][1],streets[2][0],left,streets[1][0],streets[1][1],center]
 if "--sidewalks" in OS.get_cmdline_user_args():
  route=[]
  for offset:Vector3 in [Vector3(0,0,-47),Vector3(-37,0,-47),Vector3(-37,0,47),Vector3(37,0,47),Vector3(37,0,-47),Vector3(0,0,-47),Vector3.ZERO]:route.append(center+offset)
 game.teleport(center)
 if not await ready_world(45):failure="north arrival timeout";await finish();return
 game.fly=false;game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var frames:Array=[];var previous:=Time.get_ticks_usec();var reached:=0
 for target:Vector3 in route:
  var deadline:=Time.get_ticks_msec()+18000
  while Time.get_ticks_msec()<deadline:
   var offset:Vector3=target-game.player.position;offset.y=0
   if offset.length()<1.0:break
   game.yaw=atan2(-offset.x,-offset.z);game.player.rotation.y=game.yaw;game.camera.rotation=Vector3(-0.1,0,0);game.app_focused=true
   game.controls.set_key(KEY_W,true,Time.get_ticks_usec());game.controls.set_key(KEY_SHIFT,true,Time.get_ticks_usec())
   await process_frame
   var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
  var offset:Vector3=target-game.player.position;offset.y=0
  samples.append({"target":target,"position":game.player.position,"remaining":offset.length(),"on_floor":game.player.is_on_floor(),"loading":game.loading_active})
  if offset.length()>1.0 or not game.player.is_on_floor() or game.loading_active:failure="street waypoint not reached on foot";break
  reached+=1
 game.controls.clear(Time.get_ticks_usec());frames.sort()
 var file:=FileAccess.open("res://reports/northern_street_walk.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failure":failure,"reached":reached,"samples":samples,"p95_ms":frames[int(frames.size()*.95)] if not frames.is_empty() else 0,"max_ms":frames[-1] if not frames.is_empty() else 0},"  "));file.close()
 await finish()
