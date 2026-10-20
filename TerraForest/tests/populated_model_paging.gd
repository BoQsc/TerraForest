# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
var samples:Array=[]
const OUT="res://reports/populated_model_paging/"
func run()->void:
 DirAccess.make_dir_recursive_absolute(OUT)
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"populated world ready"):await done();return
 game.set_physics_process(false);game._clear_motion()
 if not game.model_region_paging:
  var records:Array=[]
  for asset:String in game.structures._models:
   var batch=game.structures.model(asset)
   for id:int in batch.get_ids():
    var pose:PackedFloat32Array=batch.get_instance(id)
    records.append({"asset":asset,"id":id,"pose":Array(pose)})
  check(not records.is_empty(),"existing furnishings recorded")
  FileAccess.open(OUT+"manifest.json",FileAccess.WRITE).store_string(JSON.stringify(records))
 else:
  var records:Array=JSON.parse_string(FileAccess.get_file_as_string(OUT+"manifest.json"))
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
  for site in ([0] if "--diagnose-first" in OS.get_cmdline_user_args() else [0,3,4,0]):
   var center:Vector3=layout.sites[site].position
   var arrival_begin:=Time.get_ticks_usec()
   game.teleport(center+Vector3(0,0,20))
   if not check(await wait_for(func():return not game.loading_active,45),"destination terrain ready %d"%site):break
   game.set_physics_process(false);game._clear_motion()
   var expected:Array=records.filter(func(r):return Vector3(r.pose[3],r.pose[7],r.pose[11]).distance_to(game.player.position)<128)
   var released_ms:float=(Time.get_ticks_usec()-arrival_begin)/1000.0
   var missing_at_release:=0;var pending_at_release:=0
   for r:Dictionary in expected:
    if game.structures.model(r.asset).get_instance(int(r.id))!=PackedFloat32Array(r.pose):missing_at_release+=1
   var local_bounds:=AABB(game.player.position-Vector3(2,2,2),Vector3(4,5,4))
   var collision_at_release:bool=game.structures.is_collision_region_ready(local_bounds)
   for batch in game.structures._models.values():pending_at_release+=int(batch.render_stats().pending_batches)
   check(missing_at_release==0,"all nearby saved records ready when loading releases %d"%site)
   check(game.structures.is_model_render_region_ready(AABB(game.player.position-Vector3(128,128,128),Vector3(256,256,256))),"nearby render pages ready at release %d"%site)
   check(collision_at_release,"local collision ready when loading releases %d"%site)
   var ready:bool=await wait_for(func():
    for r:Dictionary in expected:
     if game.structures.model(r.asset).get_instance(int(r.id))!=PackedFloat32Array(r.pose):return false
    return true,15)
   if not ready:
    for r:Dictionary in expected:
     if game.structures.model(r.asset).get_instance(int(r.id))!=PackedFloat32Array(r.pose):print("MISSING_MODEL ",r.asset," id=",r.id)
   print("MODEL_STATE ",game.model_paging.last_state)
   check(not expected.is_empty() and ready,"all nearby saved furnishing transforms exact %d"%site)
   var frame_times:Array=[];var previous:=Time.get_ticks_usec()
   for frame in 120:
    await process_frame
    var now:=Time.get_ticks_usec();frame_times.append((now-previous)/1000.0);previous=now
   frame_times.sort()
   var resident:=0;var unloaded:=0
   for batch in game.structures._models.values():
    var stats:Dictionary=batch.region_stats();resident+=stats.resident_instances;unloaded+=stats.unloaded_regions
   check(unloaded>0,"distant model regions actually unload %d"%site)
   check(game.model_paging.last_state.get("failed_transfers",0)==0,"no failed transfers %d"%site)
   samples.append({"site":site,"arrival_ms":released_ms,"missing_at_release":missing_at_release,"pending_render_at_release":pending_at_release,"collision_at_release":collision_at_release,"frame_p95_ms":frame_times[113],"frame_max_ms":frame_times.back(),"expected_nearby":expected.size(),"resident_instances":resident,"unloaded_regions":unloaded,"scheduler":game.model_paging.last_state})
   if "--capture-arrival" in OS.get_cmdline_user_args():
    game.camera.global_position=center+Vector3(75,35,75);game.camera.look_at(center+Vector3.UP*5)
    for frame in 4:await RenderingServer.frame_post_draw
    root.get_texture().get_image().save_png(OUT+"arrival_%d.png"%site)
  if "--edit-check" in OS.get_cmdline_user_args():
   var asset:="architecture/metal_stairrail/v1"
   var batch=game.structures.model(asset)
   var pose:PackedFloat32Array=batch.get_instance(1)
   if check(pose.size()==12,"prefab-only stairrail available for edit"):
    pose[7]+=0.125
    check(game.model_tool.history.update(batch,1,pose,AABB()),"prefab-only model edit uses same native journal")
    var count:int=game.model_paging.successful_saves
    game.terrain.save_world()
    check(await wait_for(func():return game.model_paging.successful_saves>count and game.model_paging.operation=="",30),"paged world edit saved through normal lifecycle")
    for r:Dictionary in records:
     if r.asset==asset and int(r.id)==1:r.pose=Array(pose)
    FileAccess.open(OUT+"manifest.json",FileAccess.WRITE).store_string(JSON.stringify(records))
  FileAccess.open(OUT+"result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"total_models":records.size(),"route":samples},"  "))
 await done()
func done()->void:
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 print("POPULATED_MODEL_PAGING failures=",failures);quit(1 if failures else 0)
