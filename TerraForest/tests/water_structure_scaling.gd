# SPDX-License-Identifier: 0BSD
extends "res://tests/water_structure_occupancy.gd"
func timed_edit(cell:Vector3i,word:int,label:String)->Dictionary:
 var initial:int=game.lakes.statistics().water_ml
 var sampled:int=game.lakes.statistics().sampled_nodes
 begin_costs();var start:=Time.get_ticks_usec()
 check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,word])),label+" accepted")
 check(await ready_water(),label+" publishes")
 var elapsed:float=(Time.get_ticks_usec()-start)/1000.0
 var costs:=end_costs();costs.publish_ms=elapsed;costs.label=label
 costs.cache_bytes=game.lakes.statistics().structure_contact_bytes
 check(game.lakes.statistics().sampled_nodes==sampled,label+" reuses unchanged terrain sampling")
 check(game.lakes.statistics().water_ml<=initial,label+" does not create water")
 if word!=0:check(game.lakes.depth_at(Vector3(cell)+Vector3.ONE*.5)==0,label+" solid center dry")
 return costs
func run():
 process_frame.connect(sample_costs)
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual water world ready")
 if failures:await finish();return
 game.terrain.lake_slice_profiled.connect(slice_cost)
 game.set_process(false);game.set_physics_process(false);game._clear_motion()
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var cell:=Vector3i(floori(entry.seed.x),floori(entry.level)-1,floori(entry.seed.z))
 var region:=Vector3i(floori(cell.x/4.0),floori(cell.y/4.0),floori(cell.z/4.0))*4
 cell=Vector3i(region.x,cell.y,region.z)
 game.construction_inventory.gameplay=false
 check(game.construction_inventory.place_block(game.structures.blocks,game.player_hud.inventory,cell,6),"First sphere placement")
 check(await ready_water(),"First sphere ready")
 var word:int=game.structures.blocks.get_cell(cell)
 results={"edits":[],"scope":"Eight spheres in one region and four removal/replacement cycles; short scaling probe, not sustained performance qualification."}
 for n in range(1,8):
  var target:=cell+Vector3i(n%4,0,n/4)
  check(game.lakes.depth_at(Vector3(target)+Vector3.ONE*.5)>0,"Next sphere starts in water")
  results.edits.append(await timed_edit(target,word,"sphere_%d"%(n+1)))
 var meshes:=mesh_fingerprints();var snapshot:PackedByteArray=game.lakes.capture_snapshot()
 check(game.lakes.restore_snapshot(snapshot),"Dense water snapshot restores")
 check(await ready_water(),"Dense cached water publishes")
 check(mesh_fingerprints()==meshes,"Dense incremental geometry matches full cached reload")
 # Force an independent full occupancy reconstruction, not only mesh reload.
 var quantities:=amounts(game.lakes.capture_snapshot())
 game.lakes.water.invalidate(AABB(Vector3(region),Vector3(4,4,4)),false)
 check(await ready_water(),"Full terrain and building occupancy reconstruction publishes")
 check(amounts(game.lakes.capture_snapshot())==quantities and mesh_fingerprints()==meshes,"Reused cells match full occupancy reconstruction")
 var cache:int=game.lakes.statistics().structure_contact_bytes
 for cycle in 4:
  results.edits.append(await timed_edit(cell,0,"remove_%d"%cycle))
  results.edits.append(await timed_edit(cell,word,"replace_%d"%cycle))
  check(game.lakes.statistics().structure_contact_bytes==cache,"Repeated edit retains bounded occupancy cache")
 await finish()
func finish():
 results.failures=failures
 var file:=FileAccess.open("res://reports/water_structure_scaling.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_STRUCTURE_SCALING failures=",failures);quit(failures)
