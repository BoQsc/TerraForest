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
 var lake:=fixture(catalog,Vector3(42,42,42))
 var first:=Vector3(41.25,42,41.25)
 var second:=Vector3(42.75,42,42.75)
 for submerged:bool in [false,true]:
  for offset:Vector3 in [Vector3.ZERO,Vector3(-.24,0,-.24),Vector3(.24,0,.24),Vector3(-.49,0,-.49)]:
   water.restore_snapshot(lake)
   var held:int=inventory.snapshot().slots[0].water_ml
   if held:inventory.exchange_water(0,true,inventory.snapshot().revision,held)
   var a:Dictionary=water.transfer_bucket(first+Vector3.UP,first-Vector3.UP,false,inventory,0,inventory.snapshot().revision)
   check(a.ok,"First hole scooped")
   inventory.exchange_water(0,true,inventory.snapshot().revision,1000000)
   var expected:=amounts(water.capture_snapshot(catalog))
   var b:Dictionary=water.transfer_bucket(second+Vector3.UP,second-Vector3.UP,false,inventory,0,inventory.snapshot().revision)
   check(b.ok,"Second hole scooped")
   var target:=second+offset
   var start:Vector3=Vector3(42,41.75,42) if submerged else target+Vector3.UP
   var end:Vector3=Vector3(target.x,41.75,target.z) if submerged else target-Vector3.UP
   if submerged:end=start+(end-start).normalized()*3.5 # Match the actual gameplay ray length.
   var result:Dictionary=water.transfer_bucket(start,end,true,inventory,0,inventory.snapshot().revision)
   print("MULTI_HOLE submerged=",submerged," offset=",offset," result=",result)
   check(result.ok and amounts(water.capture_snapshot(catalog))==expected,"Targeted hole restores without changing the other hole")
 print("WATER_MULTIPLE_HOLES failures=",failures);quit(failures)
