# SPDX-License-Identifier: 0BSD
extends "res://tests/northern_tower_walk.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"routed world loads"):await done();return
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
 var points:PackedVector3Array=layout.roads[2].points
 var start:Vector3=points[11]
 game.teleport(start+Vector3.UP*0.05)
 if not check(await wait_for(func():return not game.loading_active,45),"road bend collision loads"):await done();return
 game.set_physics_process(false);game._clear_motion();aim(start+Vector3.UP*0.05,points[12]+Vector3.UP)
 for k in range(12,15):
  for t in [0.5,1.0]:
   if not check(await go(Transform3D.IDENTITY,points[k-1].lerp(points[k],t)),"walk curved road station "+str(k)+" fraction "+str(t)):await done();return
 await done()
func done()->void:
 var file:=FileAccess.open("res://reports/routed_road_walk.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"trace":trace},"  "));file.close()
 print("ROUTED_ROAD_WALK failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
