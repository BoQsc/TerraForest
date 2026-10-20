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
 var game=load("res://demo/world.tscn").instantiate()
 game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(game) or game.terrain.backend.world_generator!=17:print("WRONG_WORLD");quit(1);return
 game.set_physics_process(false);game._clear_motion()
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
 print("TERRAIN_LOT_WORLD_REVIEW failures=0 buildings=",plan.lots.size()," edits=",runner.completed)
 game.free();quit()
