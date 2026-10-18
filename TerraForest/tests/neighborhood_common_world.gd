# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var common:Dictionary={}
var expected:Dictionary={}
var reopening:=false
var rows:Array=[]
var frames:Array[float]=[]
func walk_to(target:Vector3)->bool:
 var deadline:=Time.get_ticks_msec()+12000;var previous:=Time.get_ticks_usec()
 while Time.get_ticks_msec()<deadline:
  var delta:Vector3=target-game.player.position;delta.y=0
  if delta.length()<0.3:
   game.controls.clear(Time.get_ticks_usec())
   if game.player.is_on_floor() and absf(game.player.position.y-target.y)<0.2 and not game.loading_active:
    game._clear_motion();rows.append({"target":target,"actual":game.player.position,"on_floor":true});return true
   await process_frame;continue
  game.yaw=atan2(-delta.x,-delta.z);game.player.rotation.y=game.yaw;game.camera.rotation=Vector3.ZERO;game.app_focused=true
  game.controls.set_key(KEY_W,true,Time.get_ticks_usec());game.controls.set_key(KEY_SHIFT,false,Time.get_ticks_usec())
  await process_frame
  var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
 return false
func run()->void:
 var slot:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
  if arg=="--common-reopen":reopening=true
 if not slot.begins_with("common_walk_"):quit(2);return
 evidence="res://reports/common_roundtrip.bin"
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game);game.terrain.autosave_timer=-3600
 if not check(await wait_for(func():return not game.loading_active,60),"common world opens"):await done();return
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[3].position
 common=preload("res://addons/structures/neighborhood_common.gd").build(center)
 if reopening:
  expected=FileAccess.open(evidence,FileAccess.READ).get_var()
  check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"fresh process restores collected public supplies exactly")
  check(game.storage.store.capture_storage_snapshot()==expected.storage,"fresh process retains depleted chest without refill")
  check(game.player.position.distance_to(expected.position)<0.2,"fresh process restores on-foot common position")
 else:
  game.teleport(common.route[0])
  if not check(await wait_for(func():return not game.loading_active,45),"common collision loads"):await done();return
  game.fly=false;game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
  var route:PackedVector3Array=common.route.duplicate();route.append_array(PackedVector3Array([center+Vector3(-7,0,47),center+Vector3(-7,0,40.5),center+Vector3(-9,0,40.5)]))
  for point:Vector3 in route:
   if not check(await walk_to(point),"common path reaches "+str(point)):await done();return
  game.set_physics_process(false);game._clear_motion()
  for i in 2:
   game.camera.global_position=center+(Vector3(2,5,46) if i==0 else Vector3(-5,2.4,19));game.camera.look_at(center+(Vector3(-11,0.5,35) if i==0 else Vector3(-11,0.7,12.5)))
   for frame in 45:await process_frame
   await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/common_view_%d.png"%i)
  game.set_physics_process(true)
 var chest_id:=0
 for id:int in game.storage.collection.get_ids():
  var p:PackedFloat32Array=game.storage.collection.get_instance(id)
  if Vector3(p[3],p[7],p[11]).distance_to(common.supply_position)<0.1:chest_id=id
 if not check(chest_id>0,"public chest exists at common supply point"):await done();return
 aim(game.player.position,common.supply_position+Vector3.UP*0.35)
 game.set_physics_process(false);game._clear_motion()
 use()
 if not check(game.storage.opened and game.storage.identity==chest_id,"E opens public chest from path"):await done();return
 if not reopening:
  var source:Dictionary=game.storage.store.snapshot(chest_id).slots[0]
  var before:int=amount(source.item)
  game.storage.storage_list.select(0);game.storage.quantity.get_line_edit().text="1"
  check(source.count>1 and game.storage.move_selected(false) and amount(source.item)==before+1,"normal chest UI withdraws one generated supply")
  check(game.storage.store.snapshot(chest_id).slots[0].count==source.count-1,"public chest stock decreases one-for-one")
  expected={"inventory":game.player_hud.inventory.capture_storage_snapshot(),"storage":game.storage.store.capture_storage_snapshot(),"position":game.player.position}
  var f:=FileAccess.open(evidence,FileAccess.WRITE);f.store_var(expected);f.close()
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/common_chest_reopen.png" if reopening else "res://reports/common_chest.png")
 game.storage.close()
 await done()
func done()->void:
 game.controls.clear(Time.get_ticks_usec());frames.sort()
 var f:=FileAccess.open("res://reports/common_walk_reopen.json" if reopening else "res://reports/common_walk.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"failures":failures,"route":rows,"p95_ms":frames[int(frames.size()*.95)] if not frames.is_empty() else 0,"max_ms":frames.back() if not frames.is_empty() else 0},"  "));f.close()
 game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"ordinary compound save completes")
 game.free();await process_frame
 print("NEIGHBORHOOD_COMMON_WORLD failures=",failures," reopen=",reopening)
 quit(1 if failures else 0)
