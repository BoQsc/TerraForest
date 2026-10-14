# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+6160);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,1);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,1);bytes.encode_u64(16,1000000)
 for i in catalog.size():bytes[32+i]=catalog[i]
 var base:int=32+catalog.size();bytes.encode_u64(base,(10<<24)|(10<<12)|10);bytes.encode_u32(base+8,1)
 for i in 512:bytes.encode_u16(base+16+i*12,500);bytes.encode_u16(base+18+i*12,500)
 for x in [2,3,5,6]:
  for y in [2,3]:
   for z in [2,3]:
    var i:int=x+8*y+64*z;bytes.encode_u16(base+16+i*12,0)
    if x<4:bytes.encode_u64(base+20+i*12,125000)
 var water=ClassDB.instantiate("NativeRegionalWater");water.restore_snapshot(bytes)
 var inventory=ClassDB.instantiate("NativePlayerInventory")
 for id in range(401,412):inventory.register_item(id,1)
 inventory.grant(401,1,0)

 var lake:=bytes.duplicate();lake.encode_u64(16,9000000)
 for j in 512:
  lake.encode_u16(base+16+j*12,500);lake.encode_u64(base+20+j*12,0)
 for z in range(1,7):
  for y in range(2,8):
   for x in range(1,7):
    var j:int=x+8*y+64*z
    lake.encode_u16(base+16+j*12,0)
    if y<4:lake.encode_u64(base+20+j*12,125000)
 for offset:Vector3 in [Vector3.ZERO,Vector3(.5,0,0),Vector3(-.5,0,0),Vector3(0,0,.5),Vector3(0,0,-.5),Vector3(.5,0,.5)]:
  assert(water.restore_snapshot(lake))
  var held:int=inventory.snapshot().slots[0].water_ml
  if held:inventory.exchange_water(0,true,inventory.snapshot().revision,held)
  var scoop:Dictionary=water.transfer_bucket(Vector3(42,43.5,42),Vector3(42,41.25,42),false,inventory,0,inventory.snapshot().revision)
  check(scoop.ok,"Scoop one unit")
  var returned:Dictionary=water.transfer_bucket(Vector3(42,43.5,42)+offset,Vector3(42,41.25,42)+offset,true,inventory,0,inventory.snapshot().revision)
  var restored:PackedByteArray=water.capture_snapshot(catalog)
  var same:=true
  for j in 512:same=same and lake.decode_u64(base+20+j*12)==restored.decode_u64(base+20+j*12)
  print("RETURN ",offset," result=",returned," exact_restore=",same)
  check(returned.ok and same,"Return from a nearby angle refills the missing volume instead of building a pillar")
 print("WATER_RETURN_NEARBY failures=",failures);quit(failures)
