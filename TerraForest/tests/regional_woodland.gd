# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,90),"prepared woodland world loads"):await done();return
 var cover=game.ground_cover
 game.session_menu.show_page("World")
 var directory=game.session_menu.pages.World.get_child(0)
 check(directory.destinations.size()==12,"saved planting exposes two trackable woodland paths")
 game.session_menu.set_open(false)
 var centers:=preload("res://addons/world_ecosystem/woodland_authoring.gd").centers(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var index:=0
 for center:Vector3 in centers:
  game.teleport(center);await wait_for(func():return not game.loading_active,60)
  game.set_physics_process(false);game._clear_motion()
  var key:=Vector2i(roundi(center.x/32),roundi(center.z/32))
  var owners:Array[Vector2i]=[key,key-Vector2i(1,0),key-Vector2i(0,1),key-Vector2i(1,1)]
  var expected:=0
  for owner in owners:expected+=cover.removed.sample_transforms(owner).size()
  check(expected>=700,"prepared location contains dense saved planting")
  var ready:=func():
   for owner in owners:
    if not cover.resident.has(owner) or cover._dirty.has(owner) or cover._pending.has(owner):return false
   return true
  check(await wait_for(ready,30),"planted owners complete support and exclusion checks")
  var published:=0;var target:=Vector3.ZERO
  for owner in owners:
   for row:Dictionary in cover.resident.get(owner,[]):
    for i in row.ids.size():
     if row.ids[i]>=4294967296:
      published+=1
      if target==Vector3.ZERO:target=Vector3(row.transforms[i*12+3],row.transforms[i*12+7],row.transforms[i*12+11])
  check(published==expected and cover.rejected_batches==0,"all saved plants render and remain pickable")
  if target!=Vector3.ZERO:
   game.camera.global_position=Vector3(center.x,target.y+1.8,center.z+6)
   game.camera.look_at(Vector3(center.x,target.y+0.3,center.z))
   for frame in 40:await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://reports/regional_woodland_%d.png"%index)
   # Use the production collection transaction against a real saved plant.
   var from:=target+Vector3.UP*2
   var to:=target-Vector3.UP*.2
   var probe:Dictionary=game.ground_interaction.collection_probe(from,to)
   check(probe.ok,"planted ground cover can be targeted")
   if probe.ok:
    var result:Dictionary=game.ground_interaction.collect(from,to,game.player_hud.inventory,true)
    check(result.ok,"planted ground cover gathers through inventory transaction")
  print("WOODLAND_LOCATION index=",index," saved=",expected," published=",published)
  index+=1
 await done()
func done()->void:
 print("REGIONAL_WOODLAND failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
