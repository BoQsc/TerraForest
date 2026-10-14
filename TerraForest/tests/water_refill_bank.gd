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
 var lake:=fixture(catalog,Vector3(42,42,42));var original:=amounts(lake)
 for target:Vector3 in [Vector3(41,41.25,41),Vector3(41,41.25,42),Vector3(42,41.25,42)]:
  check(water.restore_snapshot(lake),"Lake restores")
  var held:int=inventory.snapshot().slots[0].water_ml
  if held:inventory.exchange_water(0,true,inventory.snapshot().revision,held)
  var from:Vector3=target+Vector3.UP*2.25
  var scoop:Dictionary=water.transfer_bucket(from,target,false,inventory,0,inventory.snapshot().revision)
  check(scoop.ok,"Scoop at shoreline/corner")
  var returned:Dictionary=water.transfer_bucket(from+Vector3(.5,0,.5),target+Vector3(.5,0,.5),true,inventory,0,inventory.snapshot().revision)
  var same:bool=original==amounts(water.capture_snapshot(catalog))
  print("TARGET ",target," ",returned," RESTORED ",same)
  check(returned.ok and same,"Refill shoreline hole from nearby water")
 # Keep the first removed unit in bucket 0, collect elsewhere into bucket 1,
 # then use bucket 1 to repair the original hole. No last-scoop state may help.
 check(water.restore_snapshot(lake),"Lake restores for separate-source repair")
 for slot in [0,1]:
  if slot==1:inventory.grant(401,1,inventory.snapshot().revision)
  var held:int=inventory.snapshot().slots[slot].water_ml
  if held:inventory.exchange_water(slot,true,inventory.snapshot().revision,held)
 var hole:=Vector3(41,41.25,41)
 var removed:Dictionary=water.transfer_bucket(hole+Vector3.UP*2.25,hole,false,inventory,0,inventory.snapshot().revision)
 check(removed.ok,"Create bank hole and retain its unit separately")
 var after_hole:=amounts(water.capture_snapshot(catalog))
 var source:=Vector3(43,41.25,43)
 var collected:Dictionary=water.transfer_bucket(source+Vector3.UP*2.25,source,false,inventory,1,inventory.snapshot().revision)
 check(collected.ok,"Collect replacement water from another part")
 var repaired:Dictionary=water.transfer_bucket(hole+Vector3(.5,2.25,.5),hole+Vector3(.5,0,.5),true,inventory,1,inventory.snapshot().revision)
 var current:=amounts(water.capture_snapshot(catalog));var restored:=true
 for cell in original:
  if original[cell]>after_hole.get(cell,0):restored=restored and current.get(cell,0)==original[cell]
 check(repaired.ok and restored,"Different-source bucket repairs original hole")
 check(inventory.snapshot().slots[0].water_ml==1000000 and inventory.snapshot().slots[1].water_ml==0 and water.statistics().water_ml==8000000,"Two buckets plus world conserve all nine units")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_refill_bank.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"separate_source_repaired":restored}));file.close()
 print("WATER_REFILL_BANK failures=",failures);quit(failures)

