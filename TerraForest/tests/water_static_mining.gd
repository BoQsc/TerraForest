# SPDX-License-Identifier: 0BSD
extends SceneTree
var game
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func amounts(bytes:PackedByteArray)->Dictionary:
 var result:Dictionary={};var at:int=32+bytes.decode_u32(8)
 for region in bytes.decode_u32(12):
  var key:int=bytes.decode_u64(at)
  for i in 512:
   var ml:int=bytes.decode_u64(at+20+i*12)&0x7fffffffffffffff
   if ml:result[str(key)+":"+str(i)]=ml
  at+=9076
 return result
func ready_water()->bool:
 var deadline:=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:
  if not game.terrain.pending_edit and game.lakes.statistics().render_ready:return true
  await process_frame
 return false
func run():
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 if not game.has_meta("water_bucket_review_ready"):
  check(false,"Review world prepared");await finish();return
 game.set_process(false);game.set_physics_process(false);game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var above:=Vector3(entry.seed.x+3,entry.level+3,entry.seed.z)
 var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(above,above-Vector3.UP*20,1))
 check(not ground.is_empty(),"Actual lake floor found")
 if ground.is_empty():await finish();return
 var before:=amounts(game.lakes.capture_snapshot())
 var point:Vector3=ground.position-Vector3.UP*0.4
 check(game.terrain.sculpt_sphere(point,1.5),"Ordinary terrain mining beneath lake accepted")
 check(await ready_water(),"Edited terrain and water geometry finish publishing")
 var saved:PackedByteArray=game.lakes.capture_snapshot()
 check(amounts(saved)==before,"Mining does not move water quantities between cells")
 var stats:Dictionary=game.lakes.statistics()
 check(stats.active_cells==0 and stats.cell_steps==0 and stats.pending_vertical==0,"Mining creates no flow or settling work")
 game.camera.global_position=above+Vector3(0,1,3);game.camera.look_at(point,Vector3.UP)
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/water_static_mining.png")
 check(game.lakes.restore_snapshot(saved),"Mined lake cached water snapshot reloads")
 check(await ready_water(),"Reloaded water geometry publishes")
 stats=game.lakes.statistics()
 check(amounts(game.lakes.capture_snapshot())==before and stats.cache_hits>0 and stats.sampled_nodes==0,"Cached reload preserves every water cell without terrain resampling")
 var file:=FileAccess.open("res://reports/water_static_mining.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"statistics":stats,"scope":"Actual terrain edit and water-only cached reload; visual inspection separate, not full compound-save acceptance."},"  "));file.close()
 await finish()
func finish():
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_STATIC_MINING failures=",failures);quit(failures)
