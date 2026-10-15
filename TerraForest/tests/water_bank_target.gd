# SPDX-License-Identifier: 0BSD
extends "res://tests/water_return_nearby.gd"
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var water=ClassDB.instantiate("NativeRegionalWater")
 var inventory=ClassDB.instantiate("NativePlayerInventory")
 for id in range(401,412):inventory.register_item(id,1)
 inventory.grant(401,1,0)
 var center:=Vector3(42,42,42)
 var lake:=fixture(catalog,center)
 # Prepare the air above the bank too: placement can reach the next region.
 var old_size:=lake.size();lake.resize(old_size+4*6160)
 lake.encode_u32(12,8)
 var region:=0
 for rx in [10,11]:
  for rz in [10,11]:
   var base:int=old_size+region*6160;region+=1
   for byte in 6160:lake[base+byte]=0
   lake.encode_u64(base,(rx<<24)|(11<<12)|rz);lake.encode_u32(base+8,1)
   for cell in 512:lake.encode_u16(base+18+cell*12,500)
 var records:Array=[]
 var base_start:int=32+catalog.size()
 for i in 8:records.append(lake.slice(base_start+i*6160,base_start+(i+1)*6160))
 records.sort_custom(func(a,b):return a.decode_u64(0)<b.decode_u64(0))
 for i in 8:
  for byte in 6160:lake[base_start+i*6160+byte]=records[i][byte]
 check(water.restore_snapshot(lake),"Prepared bank fixture restores")
 var original:=amounts(lake)
 var scoop:Dictionary=water.transfer_bucket(center+Vector3.UP,center-Vector3.UP,false,inventory,0,inventory.snapshot().revision)
 check(scoop.ok,"Scoop one unit")
 var hole:=amounts(water.capture_snapshot(catalog))
 # A terrain-clipped ray ending above the lake, beside the hole. Neither
 # visible water nor the removed space lies on this aiming segment.
 var target:=Vector3(43.25,42.6,42)
 var start:=target+Vector3(0,.5,1)
 check(not water.raycast_surface(start,target).hit and not water.raycast_vacancy(start,target).hit,"Aim bypasses the lake and vacancy")
 var result:Dictionary=water.transfer_bucket(start,target,true,inventory,0,inventory.snapshot().revision)
 var after:=amounts(water.capture_snapshot(catalog));var unchanged:=true
 for cell in original:
  if original[cell]>hole.get(cell,0):unchanged=unchanged and after.get(cell,0)==hole.get(cell,0)
 print("BANK_TARGET ",result)
 check(result.ok and inventory.snapshot().slots[0].water_ml==0,"Targeted placement uses the bucket")
 check(unchanged,"Aiming beside and above water leaves the scooped hole untouched")
 print("WATER_BANK_TARGET failures=",failures);quit(failures)
