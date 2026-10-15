# SPDX-License-Identifier: 0BSD
extends "res://tests/water_raised_refill.gd"
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
 var water=fixture(false)
 var inventory=ClassDB.instantiate("NativePlayerInventory")
 for item in range(401,412):inventory.register_item(item,1)
 inventory.grant(401,1,0)
 var baseline:=amounts(water)
 # A two-cubic-metre column above the lake must be removable with two scoops,
 # even when the player aims at its side rather than flying above its top.
 for cycle in 2:
  var target:=Vector3(41.75,41.75,41.75)
  var result:Dictionary=water.transfer_bucket(target+Vector3(-1.5,0,0),target,false,inventory,0,inventory.snapshot().revision)
  check(result.ok,"Side scoop %d fills bucket"%cycle)
  if not result.ok:print(result);break
  check(inventory.exchange_water(0,true,inventory.snapshot().revision,1000000),"Move collected unit out of the local test area")
 var after:=amounts(water);var raised:=0;var lake_changed:=0
 for i in baseline.size():
  var r:int=i/512;var local:int=i%512;var ry:int=9+(r/3)%3
  var y:int=ry*8+(local/8)%8
  if y>=82:raised+=after[i]
  elif after[i]!=baseline[i]:lake_changed+=1
 print("LOWERING raised_ml=",raised," lake_changed_cells=",lake_changed)
 check(raised==0,"Two scoops remove the whole two-unit raised column")
 check(lake_changed==0,"Lowering the column does not dig a new hole in the lake")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var report:=FileAccess.open("res://reports/water_lowering.json",FileAccess.WRITE)
 report.store_string(JSON.stringify({"failures":failures,"raised_ml":raised,"lake_changed_cells":lake_changed}));report.close()
 print("WATER_LOWERING failures=",failures);quit(failures)
