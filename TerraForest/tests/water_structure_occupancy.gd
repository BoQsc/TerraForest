# SPDX-License-Identifier: 0BSD
extends "res://tests/water_static_mining.gd"
var results:Dictionary={}
# Sample only edit-to-publication windows, excluding snapshot serialization and captures.
var profiling:=false
var last_frame_us:=0
var frame_us:Array[int]=[]
var peaks:Dictionary={}
func sample_costs(record_frame:bool=true):
 if not profiling:return
 var now:=Time.get_ticks_usec()
 if record_frame and last_frame_us:frame_us.append(now-last_frame_us)
 last_frame_us=now
 var stats:Dictionary=game.lakes.statistics()
 for key in ["mesh_us","mesh_publish_us","mesh_commit_us","step_us","exclusion_notify_us","accept_patch_us","hull_snapshot_us"]:
  peaks[key]=maxi(int(peaks.get(key,0)),int(stats.get(key,0)))
func begin_costs():
 frame_us.clear();peaks.clear();last_frame_us=Time.get_ticks_usec();profiling=true
 for key in ["_mesh_publish_us","_mesh_commit_us","_exclusion_notify_us","_accept_patch_us","_hull_snapshot_us"]:game.lakes.set(key,0)
func end_costs()->Dictionary:
 sample_costs(false);profiling=false
 frame_us.sort()
 return {"frame_samples":frame_us.size(),"frame_max_ms":frame_us.back()/1000.0 if not frame_us.is_empty() else 0.0,"frame_median_ms":frame_us[frame_us.size()/2]/1000.0 if not frame_us.is_empty() else 0.0,"water_peak_us":peaks.duplicate()}

func mesh_volume(shape:int)->float:
 var mesh:Mesh=game.structures.blocks.preview_mesh(shape,0)
 var arrays:Array=mesh.surface_get_arrays(0)
 var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
 var volume:=0.0
 for i in range(0,indices.size(),3):
  volume+=vertices[indices[i]].dot(vertices[indices[i+1]].cross(vertices[indices[i+2]]))/6.0
 return absf(volume)*1000000.0
func run():
 process_frame.connect(sample_costs)
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual water world ready")
 if failures:await finish();return
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var cell:=Vector3i(floori(entry.seed.x),floori(entry.level)-1,floori(entry.seed.z))
 var bounds:=AABB(Vector3(cell),Vector3.ONE)
 check(game.lakes.water.overlaps_occupied(bounds),"Construction target contains water")
 check(game.structures.blocks.get_cell(cell)==0,"Construction target has no existing block")
 var before:Dictionary=amounts(game.lakes.capture_snapshot())
 game.construction_inventory.gameplay=false
 var placed:bool=game.construction_inventory.place_block(game.structures.blocks,game.player_hud.inventory,cell,1)
 check(placed,"Construction placement succeeds")
 check(await ready_water(),"Building occupancy and water publish")
 results={"target":cell,"placed":placed,"block":game.structures.blocks.get_cell(cell),"water_overlap":game.lakes.water.overlaps_occupied(bounds),"water_unchanged":before==amounts(game.lakes.capture_snapshot())}
 check(placed and not results.water_overlap,"Solid construction must not coexist with occupied water")
 check(before!=amounts(game.lakes.capture_snapshot()),"Constructed solid actually deletes replaced quantity")
 var saved:PackedByteArray=game.lakes.capture_snapshot()
 var after:Dictionary=amounts(saved)
 check(game.lakes.restore_snapshot(saved),"Building occupancy cache reloads")
 check(await ready_water(),"Reloaded water publishes")
 check(amounts(game.lakes.capture_snapshot())==after and game.lakes.water.depth_at(Vector3(cell)+Vector3.ONE*.5)==0,"Reload preserves replaced volume and excludes solid")
 check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,0])),"Remove constructed cube")
 check(await ready_water(),"Removed construction publishes")
 check(amounts(game.lakes.capture_snapshot())==after,"Removing construction does not resurrect deleted water")
 results.shapes=[]
 var fixtures:Array=[
  [2,Vector3(.5,.25,.5),Vector3(.5,.75,.5)],
  [3,Vector3(.5,.8,.9),Vector3(.5,.8,.1)],
  [4,Vector3(.5,.2,.8),Vector3(.5,.8,.2)],
  [5,Vector3(.5,.5,.5),Vector3(.1,.5,.5)],
  [6,Vector3(.5,.5,.5),Vector3(.9,.9,.9)]]
 var offsets:Array=[2,4,6,-2,-4]
 for n in fixtures.size():
  var shape:int=fixtures[n][0]
  var target:=cell+Vector3i(offsets[n],0,0)
  var inside:Vector3=Vector3(target)+fixtures[n][1]
  var outside:Vector3=Vector3(target)+fixtures[n][2]
  check(game.lakes.depth_at(inside)>0 and game.lakes.depth_at(outside)>0,"Shape %d starts with water inside and beside solid"%shape)
  var unchanged:Dictionary=amounts(game.lakes.capture_snapshot())
  var initial:int=game.lakes.statistics().water_ml
  begin_costs()
  var started:=Time.get_ticks_usec()
  check(game.construction_inventory.place_block(game.structures.blocks,game.player_hud.inventory,target,shape),"Place actual construction shape %d"%shape)
  var dispatch_us:=Time.get_ticks_usec()-started
  check(await ready_water(),"Shape %d water publishes"%shape)
  var elapsed_ms:float=(Time.get_ticks_usec()-started)/1000.0
  var costs:=end_costs();costs.dispatch_us=dispatch_us
  var removed:int=initial-game.lakes.statistics().water_ml
  var updated:Dictionary=amounts(game.lakes.capture_snapshot())
  var local_only:=true
  for key in unchanged:
   var parts:PackedStringArray=key.split(":");var region:int=int(parts[0]);var index:int=int(parts[1])
   var position:=Vector3i((region>>24)&4095,(region>>12)&4095,region&4095)*8+Vector3i(index%8,(index/8)%8,index/64)
   if not AABB(Vector3(target),Vector3.ONE).has_point(Vector3(position)*.5+Vector3.ONE*.25):local_only=local_only and unchanged[key]==updated.get(key,0)
  check(local_only,"Shape %d leaves every other water cell unchanged"%shape)
  check(absf(removed-mesh_volume(shape))<=8,"Shape %d deleted volume agrees with its rendered mesh"%shape)
  check(removed>0 and game.lakes.depth_at(inside)==0,"Shape %d deletes its occupied water"%shape)
  check(game.lakes.depth_at(outside)>0,"Shape %d preserves water in its empty space"%shape)
  var snapshot:PackedByteArray=game.lakes.capture_snapshot()
  var quantities:Dictionary=amounts(snapshot)
  if shape==6:
   var diagnostic:=FileAccess.open("res://reports/water_building_shape_6.bin",FileAccess.WRITE);diagnostic.store_buffer(snapshot);diagnostic.close()
  check(game.lakes.restore_snapshot(snapshot),"Shape %d cached occupancy reloads"%shape)
  check(await ready_water(),"Shape %d reloaded water publishes"%shape)
  check(amounts(game.lakes.capture_snapshot())==quantities and game.lakes.depth_at(inside)==0 and game.lakes.depth_at(outside)>0,"Shape %d reload preserves geometry and quantities"%shape)
  results.shapes.append({"shape":shape,"removed_ml":removed,"cache_bytes":game.lakes.statistics().structure_contact_bytes,"publish_ms":elapsed_ms,"costs":costs})
  if shape in [3,6]:
   game.set_process(false);game.set_physics_process(false);game._clear_motion()
   game.camera.global_position=Vector3(target)+Vector3(2,1.6,2)
   game.camera.look_at(Vector3(target)+Vector3(.5,.5,.5),Vector3.UP)
   for frame in 3:await process_frame
   game.water_camera.update()
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://reports/water_building_shape_%d.png"%shape)
 await finish()
func finish():
 results.failures=failures
 var file:=FileAccess.open("res://reports/water_structure_occupancy.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_STRUCTURE_OCCUPANCY failures=",failures);quit(failures)
