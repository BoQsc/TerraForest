# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"saved world loads"):await finish();return
 if "--expect-empty-groves" in OS.get_cmdline_user_args():
  var empty=ClassDB.instantiate("NativeVegetationScatter")
  check(game.ecosystem._scatter().capture_storage_snapshot()==empty.capture_storage_snapshot(),"older save defaults to no authored groves")
  await finish();return
 var center:Vector3=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).sites[3].position
 var expected=ClassDB.instantiate("NativeVegetationScatter")
 var regions:=PackedVector3Array()
 for x in [-60,60]:
  for z in [-26,26]:regions.append(Vector3(center.x+x,16,center.z+z))
 expected.configure_groves(regions)
 check(game.ecosystem._scatter().capture_storage_snapshot()==expected.capture_storage_snapshot(),"four exact grove regions restored from disk")
 var bed_counts:=[0,0]
 for i in 2:
  var bed:Vector3=center+Vector3(-12 if i==0 else 12,0,26)
  var key:=Vector2i(floori(bed.x/32),floori(bed.z/32))
  for dz in [-1,0,1]:
   for dx in [-1,0,1]:
    for row:Dictionary in game.ground_cover.removed.query(key+Vector2i(dx,dz)):
     for n in row.ids.size():
      var at:=Vector3(row.transforms[n*12+3],row.transforms[n*12+7],row.transforms[n*12+11])
      if absf(at.x-bed.x)<4 and absf(at.z-bed.z)<4:bed_counts[i]+=1
 check(bed_counts.all(func(n):return n>=150 and n<=256),"dense planting beds restored: "+str(bed_counts))
 game.teleport(center)
 if not check(await wait_for(func():return not game.loading_active,45),"neighborhood collision loads"):await finish();return
 game.set_physics_process(false);game._clear_motion()
 check(await wait_for(func():return game.ecosystem.resident.size()==game.ecosystem._wanted.size() and game.ecosystem._requests.is_empty() and game.ecosystem._reconcile.is_empty(),15),"native tree owners settle")
 var ids:=PackedInt64Array();var counts:=[0,0,0,0]
 for id:int in game.ecosystem.vegetation.renderer.roots:
  var at:Vector3=game.ecosystem.vegetation.renderer.roots[id].t.origin
  for i in regions.size():
   if Vector2(at.x-regions[i].x,at.z-regions[i].z).length()<regions[i].y:
    ids.append(id);counts[i]+=1
 check(counts.all(func(n):return n>0),"each planted grove has live trees: "+str(counts))
 var views:Array=[{"from":Vector3(80,55,-110),"to":Vector3(0,5,0)}, {"from":Vector3(12,2,33),"to":Vector3(12,0,26)}, {"from":Vector3(42,2,-45),"to":Vector3(60,8,-26)}]
 for i in views.size():
  game.camera.global_position=center+views[i].from;game.camera.look_at(center+views[i].to)
  for frame in 60:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/planted_neighborhood_%d.png"%i)
 if not ids.is_empty():
  var id:int=ids[0];var before:int=amount(102)
  var result:Dictionary=game.ecosystem.harvest_root(id,game.player_hud.inventory)
  check(result.ok and amount(102)==before+4 and not game.ecosystem.vegetation.renderer.roots.has(id),"live grove tree harvest grants four wood and removes tree: "+str(result))
  game.ecosystem.reset()
  check(await wait_for(func():return game.ecosystem.resident.size()==game.ecosystem._wanted.size() and not game.ecosystem.resident.is_empty() and game.ecosystem._requests.is_empty(),15),"owners republish after unload")
  check(not game.ecosystem.vegetation.renderer.roots.has(id) and game.ecosystem.harvest_state.contains(id),"harvested grove tree stays removed after streaming reset")
  check(not game.ecosystem.harvest_root(id,game.player_hud.inventory).ok and amount(102)==before+4,"repeated harvest cannot duplicate wood")
 var f:=FileAccess.open("res://reports/planted_neighborhood.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures,"grove_counts":counts,"bed_counts":bed_counts,"ids":ids},"  "));f.close()
 await finish()
func finish()->void:
 print("PLANTED_NEIGHBORHOOD failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
