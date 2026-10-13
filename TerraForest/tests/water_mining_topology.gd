# SPDX-License-Identifier: 0BSD
extends "res://tests/water_pool_gameplay.gd"
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual lake ready")
 if failures:await finish();return
 game.set_process(false);game.set_physics_process(false);game._clear_motion()
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var center:=Vector3(entry.seed.x,entry.level,entry.seed.z)
 var before:=amounts(game.lakes.capture_snapshot())
 results.stages=[]
 game.camera.global_position=center+Vector3(0,-1.3,4)
 game.camera.look_at(center+Vector3(0,-2,-4),Vector3.UP)
 game.water_camera.update()
 var first:=pool_topology(center,INF);results.stages.append(first)
 check(first.triangles>0 and first.unpaired_edges==0 and first.components==1,"Initial complete lake mesh is closed and connected")
 for offset:Vector3 in [Vector3(3,0,0),Vector3(4,0,0),Vector3(0,0,5)]:
  var above:=center+offset+Vector3.UP*4
  var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(above,above-Vector3.UP*20,1))
  check(not hit.is_empty(),"Terrain target found")
  if hit.is_empty():await finish();return
  check(game.terrain.sculpt_sphere(hit.position-Vector3.UP*0.4,1.5),"Terrain mining admitted")
  deadline=Time.get_ticks_msec()+10000
  while Time.get_ticks_msec()<deadline:
   await process_frame
   if not game.terrain.pending_edit and game.lakes.statistics().render_ready:break
  check(not game.terrain.pending_edit and game.lakes.statistics().render_ready,"Edited terrain and water publish")
  check(amounts(game.lakes.capture_snapshot())==before,"Mining preserves every water-cell quantity")
  var topology:=pool_topology(center,INF);results.stages.append(topology)
  check(topology.triangles>0 and topology.unpaired_edges==0 and topology.components==1,"Dig leaves one closed lake surface without detached fragments")
  for frame in 3:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/water_mining_stage_%d.png"%results.stages.size())
  if failures:await finish();return
 await finish()
func finish():
 results.failures=failures
 var file:=FileAccess.open("res://reports/water_mining_topology.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 if failures and is_instance_valid(game):
  var snapshot:=FileAccess.open("res://reports/water_mining_topology_failure.bin",FileAccess.WRITE);snapshot.store_buffer(game.lakes.capture_snapshot());snapshot.close()
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_MINING_TOPOLOGY failures=",failures);quit(failures)
