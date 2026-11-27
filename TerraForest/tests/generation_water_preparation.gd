# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const FOCUS=Vector3(4,40,1000)
const EDIT=AABB(Vector3(4,28,1000),Vector3(4,12,4))
var failures:=0
var core:RefCounted
var revision:=0
var epoch:=0
var catalog:PackedByteArray
var building_hulls:Array=[]

func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1

func sample_requests(water:RefCounted)->bool:
 for iteration in 1024:
  var request:Dictionary=water.next_request()
  if request.is_empty():return true
  var patch:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
  if not patch.configure(request.coordinate) or not patch.set_structure_hulls(building_hulls):return false
  var status:=0
  for step in 16:
   status=patch.sample_terrain(core,1024,revision,epoch)
   if status!=0:break
  if status!=1 or not water.accept_patch(patch):return false
 return false

func admit(water:RefCounted,budget:int)->bool:
 for iteration in 1024:
  var state:Dictionary=water.update_ocean_residency(FOCUS,budget)
  if not state.get("ok",false) or not sample_requests(water):return false
  if state.admitted==0:return true
 return false

func capture(budget:int,early_edit:bool,restore_pending:bool=false,solid:bool=false)->PackedByteArray:
 var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
 water.set_surrounding_ocean(true)
 building_hulls=[]
 var hull:=[PackedFloat64Array([-1,0,0,-4,1,0,0,8,0,-1,0,-28,0,1,0,40,0,0,-1,-1000,0,0,1,1004])]
 if solid and early_edit:building_hulls=hull
 if early_edit:
  water.update_ocean_residency(FOCUS,1)
  water.invalidate_buildings(EDIT)
  if restore_pending:
   var pending:PackedByteArray=water.capture_streaming_snapshot(catalog)
   water=ClassDB.instantiate("NativeRegionalWater")
   check(water.restore_snapshot(pending),"unseeded edited ocean snapshot restores")
   water.set_surrounding_ocean(true)
 check(admit(water,budget),"initial ocean sampling completes with budget "+str(budget))
 # Apply the same final edit footprint in both schedules; the early notification
 # is the only difference. This also checks that initial seeding happens once.
 if solid:building_hulls=hull
 water.invalidate_buildings(EDIT)
 check(sample_requests(water),"building occupancy refresh completes")
 return water.capture_streaming_snapshot(catalog)

func check_pending_restore(saved:PackedByteArray)->void:
 var pending:=saved.duplicate()
 var offset:=32+pending.decode_u32(8)
 var found:=false
 for region in pending.decode_u32(12):
  if (pending.decode_u32(offset+12)&12)==8:
   # A persisted pending region can already own water. Missing occupancy
   # must not grant it a second initial fill on restore.
   pending.encode_u32(offset+8,0)
   pending.encode_u32(offset+12,pending.decode_u32(offset+12)&~1)
   found=true;break
  offset+=9076
 var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
 check(found and water.restore_snapshot(pending),"pending edited ocean snapshot restores")
 water.set_surrounding_ocean(true)
 check(sample_requests(water) and water.capture_streaming_snapshot(catalog)==saved,"restored owned water is never seeded a second time")

func _initialize()->void:
 core=ClassDB.instantiate("TerrainCore")
 core.execute(Codec.command(6,[42,19]))
 revision=core.execute(Codec.command(0)).decode_u32(12)
 epoch=core.execute(Codec.command(13)).decode_u32(12)
 catalog=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var early:=capture(16,true)
 var early_serial:=capture(1,true)
 var early_wider:=capture(32,true)
 var resumed:=capture(16,true,true)
 var serial:=capture(1,false)
 var batched:=capture(16,false)
 var wider:=capture(32,false)
 check(not serial.is_empty() and serial.decode_u64(16)>0,"prepared shoreline retains its initial sea quantity")
 check(early==serial and early_serial==serial and early_wider==serial and resumed==serial,"construction before first ocean sampling preserves every saved byte and seeds water exactly once across admission schedules and restore")
 check(serial==batched and serial==wider,"waiting for initial water preparation preserves every saved byte across three admission schedules")
 check_pending_restore(serial)
 var early_solid:=capture(16,true,false,true)
 var late_solid:=capture(16,false,false,true)
 check(early_solid==late_solid,"building hulls arriving before the first sample preserve the complete terrain-seeded water state")
 print("HULL_SEED early_ml=",early_solid.decode_u64(16)," late_ml=",late_solid.decode_u64(16))
 print("GENERATION_WATER_PREPARATION failures=",failures," early_ml=",early.decode_u64(16)," prepared_ml=",serial.decode_u64(16))
 quit(1 if failures else 0)
