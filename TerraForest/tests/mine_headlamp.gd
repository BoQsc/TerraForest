# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,90),"saved world loads"):await done();return
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[game.terrain.backend.world_seed,game.terrain.backend.world_generator]))
 var data:PackedByteArray=core.execute(Codec.command(25))
 var at:=24+2*28
 var chamber:=Vector3(data.decode_float(at),data.decode_float(at+4),data.decode_float(at+8))
 game.teleport(chamber)
 if not check(await wait_for(func():return not game.loading_active,60),"chamber region loads"):await done();return
 game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false;game.fly=false
 game.player.position=chamber+Vector3.UP*.01;game.camera.position=Vector3(0,1.65,0)
 game.camera.look_at(chamber+Vector3(-18,3,0));game.headlamp.visible=true
 game.terrain.focus=game.player.position
 # Allow background terrain and cover publication to settle before comparing.
 for frame in 300:await process_frame
 var production_range:float=game.headlamp.spot_range
 var timings:Array=[]
 for value in [14.0,production_range,32.0,14.0]:
  game.headlamp.spot_range=value
  for frame in 45:await process_frame
  var times:Array[float]=[];var previous:=Time.get_ticks_usec()
  for frame in 120:
   await process_frame
   var now:=Time.get_ticks_usec();times.append(float(now-previous)/1000.0);previous=now
  times.sort()
  timings.append({"range":value,"median_ms":times[60],"p95_ms":times[114],"max_ms":times[-1]})
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/mine_headlamp_%d.png"%int(value))
 var file:=FileAccess.open("res://reports/mine_headlamp_timings.json",FileAccess.WRITE);file.store_string(JSON.stringify(timings,"  "));file.close()
 check(production_range>18 and game.headlamp.shadow_enabled,"existing single lamp reaches chamber walls with shadows retained")
 await done()
func done()->void:
 print("MINE_HEADLAMP failures=",failures)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(1 if failures else 0)
