# SPDX-License-Identifier: 0BSD
extends SceneTree
# The native sampler runs below. Holding its callback lets the regression prove
# which decisions were made at input and completion without advancing any frame.
class CommandTerrain extends Node3D:
 signal message_changed(message:String)
 var epoch:=0
 var pending_edit:=false
 var world_ready:=true
 var changed_since_save:=false
 var water_preparation_revision:=0
 var submitted:RefCounted
 var token:=0
 func water_sampling_revision()->int:return 0
 func request_lake_slice(builder:RefCounted,id:int)->bool:
  submitted=builder;token=id
  return true

var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func check_cold_pour():
 var cold=ClassDB.instantiate("NativeRegionalWater")
 cold.update_ocean_residency(Vector3(4,40,1000),1)
 var point:=Vector3(1000.1,200.1,1000.1)
 var pour:Dictionary=cold.place_water(point,250000)
 var bricks:Array=pour.get("occupancy_regions",[])
 check(pour.pending and bricks.size()==8,"A first pour at a brick corner identifies all eight local dependencies at once")
 if bricks.size()!=8:return
 var background:Vector3i=cold.next_request().coordinate
 check(background not in bricks and cold.statistics().water_ml==0,"Waiting for the local footprint leaves ocean work queued and transfers no water")
 var core=ClassDB.instantiate("TerrainCore")
 core.execute(preload("res://addons/volumetric_terrain/mesh_codec.gd").command(6,[42,19]))
 for coordinate:Vector3i in bricks:
  var patch=ClassDB.instantiate("NativeWaterTerrainPatch")
  patch.configure(coordinate)
  var result:=0
  for step in 200:
   result=patch.sample_terrain(core,256,0,0)
   if result!=0:break
  check(result==1 and cold.accept_patch(patch),"The requested local occupancy brick prepares independently")
 pour=cold.place_water(point,250000)
 check(pour.ok and cold.statistics().water_ml==250000 and cold.next_request().coordinate==background,"One quarter cubic metre commits with the unrelated ocean request still pending")
func check_command_completion(core:RefCounted,cancel:bool)->void:
 var scheduler=preload("res://addons/volumetric_water/lake_world.gd").new()
 var terrain:=CommandTerrain.new()
 scheduler.terrain=terrain
 scheduler.water=ClassDB.instantiate("NativeRegionalWater")
 scheduler.set_process(false)
 scheduler._epoch=terrain.epoch
 var point:=Vector3(1000.1,200.1,1000.1)
 var initial:Dictionary=scheduler.dev_brush(point,false,2,250000)
 check(initial.pending and terrain.submitted!=null and scheduler._busy,"Input dispatches the local occupancy worker before any frame advances")
 if terrain.submitted!=null:
  if cancel:scheduler.dev_brush(point,true,2)
  var status:=0
  for i in 200:
   status=terrain.submitted.sample_terrain(core,2048,0,terrain.epoch)
   if status!=0:break
  check(status==1,"The command worker samples the pinned field")
  scheduler._slice_ready(terrain.token,status,terrain.epoch,0)
  var expected:=0 if cancel else 250000
  check(scheduler._pending_dev.is_empty() and scheduler.water.total_water_ml()==expected,
   "Cancelled pour stays cancelled when the earlier worker returns" if cancel else "The occupancy callback commits the exact pour before another frame")
  scheduler._slice_ready(terrain.token,status,terrain.epoch,0)
  check(scheduler.water.total_water_ml()==expected,"A repeated completion preserves the committed quantity")
 scheduler.free()
 terrain.free()

func run():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 check_cold_pour()
 var command_field:RefCounted=ClassDB.instantiate("TerrainCore")
 command_field.execute(preload("res://addons/volumetric_terrain/mesh_codec.gd").command(6,[42,19]))
 check_command_completion(command_field,false)
 check_command_completion(command_field,true)
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var data:=PackedByteArray();data.resize(32+catalog.size()+6160);data.fill(0)
 data.encode_u32(0,0x31575256);data.encode_u32(4,1);data.encode_u32(8,catalog.size());data.encode_u32(12,1);data.encode_u64(16,125000)
 for i in catalog.size():data[32+i]=catalog[i]
 var at:=32+catalog.size();data.encode_u64(at,(10<<24)|(10<<12)|10);data.encode_u32(at+8,1)
 for i in 512:data.encode_u16(at+18+i*12,500)
 # Suspended water in air, marked awake by an old save. Gravity must not run.
 var index:=4+8*4+64*4;data.encode_u64(at+20+index*12,125000);data[at+27+index*12]|=128
 var water=ClassDB.instantiate("NativeRegionalWater")
 check(water.restore_snapshot(data),"Legacy awake water restores without enabling simulation")
 var before:PackedByteArray=water.capture_snapshot(catalog)
 for i in 600:water.advance(2048,1.0/60.0)
 check(water.capture_snapshot(catalog)==before,"Ten simulated seconds leave suspended water byte-identical")
 var stats:Dictionary=water.statistics()
 check(stats.cell_steps==0 and stats.active_cells==0,"Static water has no active-cell simulation work")
 var p:=Vector3(42.25,42.25,42.25)
 check(water.brush(p,0.0,-25000)==25000,"Explicit local removal still works")
 check(water.brush(p,0.0,25000)==25000,"Explicit local placement still works")
 var edited:PackedByteArray=water.capture_snapshot(catalog)
 for i in 600:water.advance(2048,1.0/60.0)
 check(water.capture_snapshot(catalog)==edited,"Explicit edits do not start flow or spillage")
 var restored=ClassDB.instantiate("NativeRegionalWater")
 check(restored.restore_snapshot(edited),"Edited static water reloads")
 var loaded:PackedByteArray=restored.capture_snapshot(catalog)
 for i in 60:restored.advance(2048,1.0/60.0)
 check(restored.capture_snapshot(catalog)==loaded and restored.statistics().water_ml==125000,"Reload retains quantity and remains stationary")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var f:=FileAccess.open("res://reports/water_static_editing.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures,"scope":"No autonomous water movement; explicit edits and snapshot retention. Not visual or bucket-volume acceptance."},"  "));f.close()
 print("WATER_STATIC_EDITING failures=",failures);quit(failures)
