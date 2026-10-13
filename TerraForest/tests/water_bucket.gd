# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func fixture(amount:int,open_neighbor:bool=false):
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+9076);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,2);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,1);bytes.encode_u64(16,amount)
 for i in catalog.size():bytes[32+i]=catalog[i]
 var base:int=32+catalog.size();bytes.encode_u64(base,(10<<24)|(10<<12)|10);bytes.encode_u32(base+8,1);bytes.encode_u32(base+12,1);base+=16
 for i in 512:bytes.encode_u16(base+i*12,500);bytes.encode_u16(base+i*12+2,500)
 var wet:=3+8*3+64*3;bytes.encode_u16(base+wet*12,0);bytes.encode_u64(base+wet*12+4,amount)
 if open_neighbor:bytes.encode_u16(base+(wet+1)*12,0)
 for i in 729:bytes.encode_float(base+6144+i*4,1.0)
 var water=ClassDB.instantiate("NativeRegionalWater");water.restore_snapshot(bytes);return water
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
 var from:=Vector3(41.75,42.5,41.75);var to:=Vector3(41.75,41.5,41.75)
 for amount in [62500,3570,570]:
  var water=fixture(amount);var inventory=ClassDB.instantiate("NativePlayerInventory")
  for item in range(401,412):inventory.register_item(item,1)
  inventory.grant(401,1,0)
  var held:Dictionary=inventory.snapshot();var before:PackedByteArray=water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))
  var result:Dictionary=water.transfer_bucket(from,to,false,inventory,0,held.revision)
  check(not result.ok and inventory.snapshot()==held and water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))==before,"Insufficient source leaves world and bucket unchanged (%d ml)"%amount)
  check(not water.transfer_bucket(from,to,true,inventory,0,held.revision).ok and inventory.snapshot()==held,"Empty bucket cannot pour")
  check(not water.transfer_bucket(from,to,false,inventory,0,-1).ok and inventory.snapshot()==held,"Stale click changes neither inventory nor water")
  check(not water.has_method("transfer_litre"),"No alternate litre gameplay transfer API")
 var static_water=fixture(62500,true)
 var before:Dictionary=static_water.statistics();static_water.advance(2048);var after:Dictionary=static_water.statistics()
 check(after.cell_steps==before.cell_steps and after.active_cells==0 and after.water_ml==62500,"Water remains static without automatic flow")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file=FileAccess.open("res://reports/water_bucket.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
 quit(failures)
