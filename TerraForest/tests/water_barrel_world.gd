# SPDX-License-Identifier: 0BSD
extends "res://tests/water_static_mining.gd"
var evidence:=""
var frames:Array[int]=[]
var measured:=false
var previous_frame:=0
func frame_cost()->void:
 if not measured:return
 var now:=Time.get_ticks_usec()
 if previous_frame:frames.append(now-previous_frame)
 previous_frame=now
func idle_water()->bool:
 var deadline:=Time.get_ticks_msec()+60000
 var next_report:=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:
  var stats:Dictionary=game.lakes.statistics()
  if not game.terrain.pending_edit and stats.render_ready and stats.settling_regions==0:return true
  if Time.get_ticks_msec()>=next_report:
   print("WATER_BARREL_PROGRESS ",JSON.stringify({"terrain_pending":game.terrain.pending_edit,"settling_regions":stats.settling_regions,"settling_steps":stats.settling_steps,"pending_regions":stats.pending_regions,"dirty_meshes":stats.dirty_meshes,"surface_failure":stats.surface_failure,"occupancy_failure":stats.occupancy_failure}))
   next_report+=10000
  await process_frame
 return false
func moment(values:Dictionary)->float:
 var result:=0.0
 for key:String in values:
  var parts:=key.split(":");var region:=int(parts[0]);var index:=int(parts[1])
  result+=float(((region>>12)&4095)*8+(index/8)%8)*float(values[key])
 return result
func capture(label:String,center:Vector3,level:float,underwater:bool=false)->void:
 game.camera.global_position=center+Vector3(-3,level-center.y-1 if underwater else level-center.y+2,4 if underwater else 6)
 game.camera.look_at(center+Vector3(0,level-center.y-1 if underwater else level-center.y-1.5,0),Vector3.UP)
 game.water_camera.update()
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(evidence.path_join(label+".png"))
func run():
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--check-evidence-dir="):evidence=argument.trim_prefix("--check-evidence-dir=")
 if evidence.is_empty():push_error("Run through the admitted check launcher");quit(2);return
 process_frame.connect(frame_cost)
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+120000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual lake review world prepares")
 if failures:await finish();return
 game.set_process(false);game.set_physics_process(false);game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 game.tool_view.visible=false
 game.combat.blast_water_settling=true
 # Fixed-player rendering check: exercise the real committed-edit callback and
 # water scheduler without depending on which desktop window currently has focus.
 game.lakes.settling_active=func()->bool:return true
 check(await idle_water(),"Initial water publication reaches idle")
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var above:Vector3=entry.seed+Vector3(3,0,0);above.y=entry.level+4
 await physics_frame
 var ground:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(above,above-Vector3.UP*20,1))
 check(not ground.is_empty(),"Actual terrain beneath lake is available")
 if ground.is_empty():await finish();return
 var base:Vector3=ground.position
 var id:int=game.combat.barrels.insert_instance(PackedFloat32Array([1,0,0,base.x,0,1,0,base.y,0,0,1,base.z]),AABB())
 check(id>0,"Explosive barrel enters the actual model store")
 var before:=amounts(game.lakes.capture_snapshot());var total:int=game.lakes.statistics().water_ml
 await capture("barrel_before",base,entry.level)
 measured=true;previous_frame=0;var started:=Time.get_ticks_usec()
 check(game.combat.damage_barrel(id,50) and game.combat.detonate(id),"Actual damaged barrel admits terrain excavation")
 game.combat.detonations.erase(id)
 check(await idle_water(),"Barrel crater water settles and publishes within the bound")
 var elapsed:=Time.get_ticks_usec()-started;measured=false
 var after:=amounts(game.lakes.capture_snapshot());var stats:Dictionary=game.lakes.statistics()
 var checkpoint:=FileAccess.open(evidence.path_join("post_blast_statistics.json"),FileAccess.WRITE);checkpoint.store_string(JSON.stringify(stats,"  "));checkpoint.close()
 check(stats.water_ml==total,"Barrel excavation conserves every owned millilitre")
 check(after!=before and moment(after)<moment(before),"Water redistributes downward into the actual barrel crater")
 check(game.combat.barrels.get_instance(id).is_empty(),"Detonated barrel is removed exactly once")
 check(not stats.surface_budget_failed and stats.surface_failure.is_empty(),"Water publication reports no geometry budget failure")
 await capture("barrel_after",base,entry.level)
 await capture("barrel_after_underwater",base,entry.level,true)
 var snapshot:PackedByteArray=game.lakes.capture_snapshot()
 check(game.lakes.restore_snapshot(snapshot),"Post-blast water snapshot restores")
 check(await idle_water() and amounts(game.lakes.capture_snapshot())==after,"Reload preserves settled quantities")
 frames.sort()
 var report:Dictionary={"failures":failures,"water_ml":total,"barrel_base":base,"settle_publish_ms":elapsed/1000.0,"statistics":stats,"frame_samples":frames.size(),"scope":"Actual barrel, terrain and water path with stationary player; focus-independent water advancement. Not a moving-combat FPS acceptance."}
 if not frames.is_empty():report.frame_p95_ms=frames[int((frames.size()-1)*.95)]/1000.0;report.frame_max_ms=frames.back()/1000.0
 var file:=FileAccess.open(evidence.path_join("water_barrel_world.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 await finish()
func finish():
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_BARREL_WORLD failures=",failures);quit(failures)
