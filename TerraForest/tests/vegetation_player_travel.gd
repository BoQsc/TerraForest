# SPDX-License-Identifier: 0BSD
extends "res://tests/southern_vegetation.gd"
func run()->void:
 DirAccess.make_dir_recursive_absolute("res://reports/vegetation_player_travel")
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.max_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"world ready"):await done();return
 game.teleport(Vector3(1024,62,1792))
 if not check(await wait_for(func():return not game.loading_active,45),"arrival ready"):await done();return
 if not check(await wait_for(settled,25),"initial cover ready"):await done();return
 game.player_hud.set_open(false);game.fly=false;game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var c=game.ground_cover;var original:PackedByteArray=c.removed.capture_storage_snapshot()
 var start:Vector3=game.player.position;var target:=start+Vector3(66,0,0)
 var owners:Dictionary={};var frames:Array=[];var peak_pending:=0;var peak_resident:=0;var grounded:=0;var total:=0
 var deadline:=Time.get_ticks_msec()+20000;var previous:=Time.get_ticks_usec()
 root.get_texture().get_image().save_png("res://reports/vegetation_player_travel/start.png")
 previous=Time.get_ticks_usec()
 while Time.get_ticks_msec()<deadline:
  var offset:Vector3=target-game.player.position;offset.y=0
  if offset.length()<1:break
  game.yaw=atan2(-offset.x,-offset.z);game.player.rotation.y=game.yaw;game.pitch=-0.12;game.camera.rotation=Vector3(-0.12,0,0);game.app_focused=true
  game.controls.set_key(KEY_W,true,Time.get_ticks_usec());game.controls.set_key(KEY_SHIFT,true,Time.get_ticks_usec())
  await process_frame
  var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
  owners[Vector2i(floori(game.player.position.x/32),floori(game.player.position.z/32))]=true
  peak_resident=maxi(peak_resident,c.resident.size());peak_pending=maxi(peak_pending,c._requests.size());total+=1
  if game.player.is_on_floor():grounded+=1
 game.controls.clear(Time.get_ticks_usec())
 var distance:Vector3=target-game.player.position;distance.y=0
 check(distance.length()<1,"66m route reached with normal walking controls")
 check(owners.size()>=3,"player crosses two 32m streaming boundaries")
 check(await wait_for(settled,25),"new cover settles after arrival")
 check(c.removed.capture_storage_snapshot()==original,"travel leaves gathered and authored records unchanged")
 check(c.rejected_batches==0 and peak_resident<=81 and peak_pending<=4,"streaming stays within owner/request bounds")
 var render:Array=[]
 for batch in c.batches:
  var stats:Dictionary=batch.render_stats();render.append(stats)
  check(stats.budget_deferred==0 and stats.resident_transform_bytes<=stats.byte_limit,"arrival pages fit resident budget")
 frames.sort()
 root.get_texture().get_image().save_png("res://reports/vegetation_player_travel/end.png")
 FileAccess.open("res://reports/vegetation_player_travel/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"start":str(start),"end":str(game.player.position),"remaining":distance.length(),"owners":owners.size(),"grounded_frames":grounded,"frames":total,"peak_requests":peak_pending,"peak_resident":peak_resident,"p95_ms":frames[int(frames.size()*.95)],"worst_ms":frames.back(),"render":render,"scope":"66m actual player sprint, saved southern world, no long-run qualification"},"  "))
 await done()
