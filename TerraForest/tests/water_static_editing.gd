# SPDX-License-Identifier: 0BSD
extends SceneTree
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
func run():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 check_cold_pour()
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
