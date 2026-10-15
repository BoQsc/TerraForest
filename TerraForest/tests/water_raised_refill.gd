# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures := 0
func check(ok:bool, label:String):
 print("PASS " if ok else "FAIL ", label)
 if not ok: failures += 1
func fixture():
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+27*9076);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,2);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,27)
 for i in catalog.size():bytes[32+i]=catalog[i]
 var total:=0;var region_index:=0
 for rx in range(9,12):
  for ry in range(9,12):
   for rz in range(9,12):
    var base:int=32+catalog.size()+region_index*9076;region_index+=1
    bytes.encode_u64(base,(rx<<24)|(ry<<12)|rz);bytes.encode_u32(base+8,1);bytes.encode_u32(base+12,1);base+=16
    for i in 512:
     var x:int=i%8;var y:int=(i/8)%8;var z:int=i/64
     bytes.encode_u16(base+i*12,0);bytes.encode_u16(base+i*12+2,500)
     var wet:bool=ry==10 and (y<2 or (rx==10 and rz==10 and ((x>=3 and x<=4 and y<6) or (x==2 and y==5)) and z>=3 and z<=4))
     if wet:bytes.encode_u64(base+i*12+4,125000);total+=125000
    for i in 729:bytes.encode_float(base+6144+i*4,1.0)
 bytes.encode_u64(16,total)
 var water=ClassDB.instantiate("NativeRegionalWater")
 check(water.restore_snapshot(bytes),"Lake with raised column and overhang loads")
 return water
func amounts(water)->Array:
 var bytes:PackedByteArray=water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))
 var result:Array=[]
 for r in bytes.decode_u32(12):
  var base:int=32+bytes.decode_u32(8)+r*9076+16
  for i in 512:result.append(bytes.decode_u64(base+i*12+4)&0x7fffffffffffffff)
 return result
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
 for target in [Vector3(41.75,42.75,41.75),Vector3(41.75,42.25,41.75),Vector3(41.75,41.75,41.75)]:
  var water=fixture();var inventory=ClassDB.instantiate("NativePlayerInventory")
  for item in range(401,412):inventory.register_item(item,1)
  inventory.grant(401,1,0)
  var before:=amounts(water);var total:int=water.statistics().water_ml
  var from:Vector3=target+Vector3(-1.5,0,0)
  var scoop:Dictionary=water.transfer_bucket(from,target,false,inventory,0,inventory.snapshot().revision)
  print("SCOOP ",target," ",scoop)
  check(scoop.ok,"Side scoop of raised placement succeeds")
  if not scoop.ok:continue
  check(water.statistics().water_ml==total-1000000,"Scoop removes exactly one unit")
  var saved:PackedByteArray=water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))
  check(saved.decode_u32(4)==9,"Scoop vacancies are saved with the water")
  var reopened=ClassDB.instantiate("NativeRegionalWater")
  check(reopened.restore_snapshot(saved),"Scoop state reloads without recomputing terrain")
  check(reopened.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))==saved,"Vacancy save/reload is byte exact")
  var corrupt:=saved.duplicate()
  var vacancy_offset:int=32+saved.decode_u32(8)+27*9076+27*8
  while corrupt.decode_u32(vacancy_offset)==0:vacancy_offset+=4
  corrupt.encode_u32(vacancy_offset+8,125001)
  check(not reopened.restore_snapshot(corrupt),"Invalid vacancy quantity is rejected atomically")
  check(reopened.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))==saved,"Rejected vacancy state leaves world unchanged")
  water=reopened
  # Return from another full bucket; the original bucket is not an undo token.
  var replacement=ClassDB.instantiate("NativePlayerInventory")
  for item in range(401,412):replacement.register_item(item,1)
  replacement.grant(401,1,0)
  check(replacement.exchange_water(0,false,replacement.snapshot().revision,1000000),"Independent bucket contains a full unit")
  inventory=replacement
  var pour:Dictionary=water.transfer_bucket(from,target,true,inventory,0,inventory.snapshot().revision)
  print("POUR ",pour)
  check(pour.ok,"Return beside raised placement succeeds")
  var after:=amounts(water);var changed:Array=[]
  for i in before.size():
   if before[i]!=after[i]:changed.append({"cell":Vector3i(i%8,(i/8)%8,i/64),"before":before[i],"after":after[i]})
  print("DIFFERENCES ",changed)
  check(before==after,"Returning one unit restores every cell, not only total volume")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var report:=FileAccess.open("res://reports/water_raised_refill.json",FileAccess.WRITE)
 report.store_string(JSON.stringify({"failures":failures}));report.close()
 print("WATER_RAISED_REFILL failures=",failures)
 quit(failures)


