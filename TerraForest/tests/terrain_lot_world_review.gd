# SPDX-License-Identifier: 0BSD
extends "res://tests/village_shop_review.gd"
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func wait_until(condition:Callable,seconds:float)->bool:
 var deadline:int=Time.get_ticks_msec()+int(seconds*1000)
 while not condition.call() and Time.get_ticks_msec()<deadline:await process_frame
 return condition.call()
func run()->void:
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[42,17]))
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(42,16)
 var plan:Dictionary=Planner.locate(core,layout.sites[3].position)
 if not plan.ok:quit(1);return
 var works:Dictionary=Planner.earthworks(plan)
 var connection:Dictionary={}
 if "--regional-connection" in OS.get_cmdline_user_args():
  connection=preload("res://addons/structures/regional_route_planner.gd").central_connection(core,plan,layout)
  if not connection.ok:print("REGIONAL_CONNECTION_FAILED ",connection);quit(1);return
  # Prepare the arterial first; local streets restore their shared junction grade.
  works.segments=connection.segments+works.segments
  works.bounds=works.bounds.merge(connection.bounds)

 var game=load("res://demo/world.tscn").instantiate()
 var bake:bool="--save-terrain-lots" in OS.get_cmdline_user_args()
 var reopen:bool="--reopen-terrain-lots" in OS.get_cmdline_user_args()
 if bake:
  var slot:=""
  for arg:String in OS.get_cmdline_user_args():
   if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
  if slot.is_empty() or FileAccess.file_exists("user://worlds/"+slot+".trw"):
   print("REFUSING_EXISTING_OR_UNNAMED_BAKE");game.free();quit(1);return
 game.temporary_world=not bake;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(game) or game.terrain.backend.world_generator!=17:print("WRONG_WORLD");quit(1);return
 game.set_physics_process(false);game._clear_motion()
 if reopen:
  var expected=FileAccess.get_file_as_bytes("res://reports/terrain_lot_region_expected.bin")
  if expected.is_empty() or game.generated_region.store.capture_snapshot()!=expected or game.generated_region.describe(42,17).is_empty():
   print("REGION_REOPEN_FAILED");game.free();quit(1);return
  game.world_map.refresh_world()
  if not connection.is_empty():
   var middle:int=connection.points.size()/2
   game.teleport(connection.points[middle])
   if not await ready_world(game):quit(1);return
   game.set_physics_process(false);game._clear_motion()
   game.camera.global_position=connection.points[middle]+Vector3.UP*1.7
   game.camera.look_at(connection.points[middle+1]+Vector3.UP*1.7)
   for i in 150:await process_frame
   var roots:Array=[]
   for row:Dictionary in game.vegetation.renderer.roots.values():roots.append(row.t)
   var blocked:PackedByteArray=game.generated_region.store.placement_mask(roots,2.0)
   var count:=0
   for value in blocked:count+=value
   print("ROAD_TREE_OVERLAPS ",count," resident=",roots.size())
   if count!=0:game.free();quit(1);return
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://reports/terrain_lot_regional_ground.png")
  print("TERRAIN_LOT_REOPEN failures=0 places=",game.world_map.places.size()," roads=",game.world_map.roads.size())
  game.free();quit();return
 var runner=preload("res://addons/structures/site_preparation.gd").new()
 if not runner.begin(works,game.terrain,func(_bounds:AABB)->String:return ""):quit(1);return
 var deadline:int=Time.get_ticks_msec()+90000
 while runner.status=="running" and Time.get_ticks_msec()<deadline:
  runner.tick(game.terrain,func(_bounds:AABB)->String:return "")
  await process_frame
 if runner.status!="complete":print("PREPARATION_FAILED ",runner.status," ",runner.reason);quit(1);return
 game.structure_mode=true;game.structure_rotation=0
 for lot:Dictionary in plan.lots:
  var index:int=game.structure_prefabs.find(lot.asset)
  if index<0:
   game._accept_composed_prefab({"ok":true,"asset":lot.asset});index=game.structure_prefab_index
  game.structure_prefab_index=index;game.structure_rotation=lot.rotation
  var doors:int=game.doors.collection.get_ids().size()
  game._begin_frontage_placement(lot.asset,lot.origin,true)
  if not await wait_until(func():return game._foundation_placement.is_empty(),20) or game.doors.collection.get_ids().size()!=doors+1:
   print("BUILDING_FAILED ",lot.label," ",game.foundation_check.status);quit(1);return
 var poses:Array=Planner.paving(plan)
 var collection=game.structures.model(preload("res://addons/structures/paving_catalog.gd").KEY)
 for pose:Transform3D in poses:
  var records:PackedFloat32Array=preload("res://addons/structures/paving_catalog.gd").records([pose])
  if collection.insert_instance(records,AABB())<=0:print("PAVING_FAILED");quit(1);return
 var saved_paving:PackedByteArray=collection.capture_snapshot()
 if not collection.remove_instances(collection.get_ids()) or not collection.restore_snapshot(saved_paving) or collection.capture_snapshot()!=saved_paving:
  print("PAVING_ROUNDTRIP_FAILED");quit(1);return
 if not game.generated_region.publish_neighborhood(42,plan):print("REGION_PUBLICATION_FAILED");quit(1);return
 if not connection.is_empty():
  var metadata:Dictionary=game.generated_region.store.get_plan()
  for i in range(1,connection.points.size()):metadata.roads.append({"a":connection.points[i-1],"b":connection.points[i],"width":8.0})
  metadata.places.append({"id":0,"title":"Central road arrival","detail":"Road end at the planned central site; settlement construction is unfinished.","position":connection.points[-1]})
  if not game.generated_region.store.set_plan(42,17,metadata.places,metadata.roads):print("CONNECTION_MAP_FAILED");quit(1);return
 game.ecosystem._structures_changed()
 game.ground_cover._exclusion_changed(works.bounds)
 game.terrain.changed_since_save=true
 game.world_map.refresh_world()
 if game.world_map.places.size()!=(1 if connection.is_empty() else 2) or game.world_map.roads.is_empty():print("BAKED_MAP_FAILED");quit(1);return
 game.construction_palette.survey_dialog.hide()
 var center:Vector3=plan.center
 center.y=plan.lots[5].origin.y
 game.teleport(center+Vector3(70,0,70))
 if not await ready_world(game):quit(1);return
 game.set_physics_process(false);game._clear_motion()
 game.camera.global_position=center+Vector3(95,65,95);game.camera.look_at(center+Vector3(0,3,0))
 for i in 150:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/terrain_lot_world_overview.png")
 var road:Dictionary=plan.roads[4]
 game.camera.global_position=road.start+Vector3.UP*1.7;game.camera.look_at(road.finish+Vector3.UP*1.7)
 for i in 90:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/terrain_lot_world_street.png")
 if not connection.is_empty():
  var midpoint:Vector3=connection.points[connection.points.size()/2]
  game.teleport(midpoint)
  if not await ready_world(game):quit(1);return
  game.set_physics_process(false);game._clear_motion()
  game.camera.global_position=midpoint+Vector3(55,40,30);game.camera.look_at(midpoint)
  for i in 120:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/terrain_lot_regional_road.png")
  game.teleport(road.start)
  if not await ready_world(game):quit(1);return
  game.set_physics_process(false);game._clear_motion()
 # Short actual-player traversal along a sloping walkway; no jumping or flying.
 var direction:Vector3=(road.finish-road.start).normalized()
 var across:Vector3=Vector3.UP.cross(direction).normalized()
 var start:Vector3=road.start+direction*0.8+across*3.75
 var target:Vector3=road.finish-direction*0.8+across*3.75
 game.fly=false;game.needs_floor_spawn=false;game.player.position=start+Vector3.UP*0.08
 game.player.velocity=Vector3.ZERO;game.controls.clear(Time.get_ticks_usec())
 game.camera.position=Vector3(0,1.65,0);game.camera.rotation=Vector3.ZERO
 var arrived:=false
 for tick in 240:
  var offset:Vector3=target-game.player.position;offset.y=0
  if offset.length()<0.25 and game.player.is_on_floor():arrived=true;break
  game.yaw=atan2(-offset.x,-offset.z);game.player.rotation.y=game.yaw
  game.controls.set_key(KEY_W,offset.length()>0.15,Time.get_ticks_usec())
  await physics_frame;game.app_focused=true;game._physics_process(1.0/60)
 game.controls.clear(Time.get_ticks_usec())
 print("PAVEMENT_WALK arrived=",arrived," start=",start," target=",target," actual=",game.player.position)
 if not arrived:game.free();quit(1);return
 if bake:
  var file=FileAccess.open("res://reports/terrain_lot_region_expected.bin",FileAccess.WRITE)
  file.store_buffer(game.generated_region.store.capture_snapshot());file.close()
  game.shutdown_requested=true
  if not await game.terrain.shutdown_after_edits():print("BAKE_SAVE_FAILED");game.free();quit(1);return
 print("TERRAIN_LOT_WORLD_REVIEW failures=0 buildings=",plan.lots.size()," edits=",runner.completed)
 game.free();quit()
