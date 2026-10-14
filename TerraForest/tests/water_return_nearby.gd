# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var cases:Array=[]
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func amounts(bytes:PackedByteArray)->Dictionary:
 var result:Dictionary={}
 var base:int=32+bytes.decode_u32(8)
 for region in bytes.decode_u32(12):
  var start:int=base+region*(9076 if bytes.decode_u32(4)>=2 else 6160)
  var key:int=bytes.decode_u64(start)
  for cell in 512:
   var ml:int=bytes.decode_u64(start+20+cell*12)
   if ml:result[[key,cell]]=ml
 return result
func fixture(catalog:PackedByteArray,center:Vector3)->PackedByteArray:
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+4*6160);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,1);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,4);bytes.encode_u64(16,9000000)
 for i in catalog.size():bytes[32+i]=catalog[i]
 var region:=0
 for rx in [10,11]:
  for rz in [10,11]:
   var base:int=32+catalog.size()+region*6160;region+=1
   bytes.encode_u64(base,(rx<<24)|(10<<12)|rz);bytes.encode_u32(base+8,1)
   for z in 8:
    for y in 8:
     for x in 8:
      var cell:int=x+8*y+64*z
      var wx:int=rx*8+x;var wz:int=rz*8+z
      var inside:bool=wx>=int(center.x*2)-3 and wx<int(center.x*2)+3 and wz>=int(center.z*2)-3 and wz<int(center.z*2)+3 and y>=2
      bytes.encode_u16(base+16+cell*12,0 if inside else 500)
      bytes.encode_u16(base+18+cell*12,500)
      if inside and y<4:bytes.encode_u64(base+20+cell*12,125000)
 return bytes
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var water=ClassDB.instantiate("NativeRegionalWater")
 var inventory=ClassDB.instantiate("NativePlayerInventory")
 for id in range(401,412):inventory.register_item(id,1)
 inventory.grant(401,1,0)
 # Interior, region face, and four-region corner: same lake translated in X/Z.
 for center:Vector3 in [Vector3(42,42,42),Vector3(44,42,42),Vector3(44,42,44)]:
  var lake:=fixture(catalog,center)
  var original:=amounts(lake)
  for offset:Vector3 in [Vector3.ZERO,Vector3(.5,0,0),Vector3(-.5,0,0),Vector3(0,0,.5),Vector3(0,0,-.5),Vector3(.5,0,.5)]:
   check(water.restore_snapshot(lake),"Prepared lake restores")
   var held:int=inventory.snapshot().slots[0].water_ml
   if held:inventory.exchange_water(0,true,inventory.snapshot().revision,held)
   var from:Vector3=center+Vector3.UP*1.5;var to:Vector3=center-Vector3.UP*.75
   var scoop:Dictionary=water.transfer_bucket(from,to,false,inventory,0,inventory.snapshot().revision)
   check(scoop.ok and inventory.snapshot().slots[0].water_ml==1000000,"Scoop one full unit")
   var returned:Dictionary=water.transfer_bucket(from+offset,to+offset,true,inventory,0,inventory.snapshot().revision)
   var same:bool=original==amounts(water.capture_snapshot(catalog))
   check(returned.ok and same and inventory.snapshot().slots[0].water_ml==0,"Changed-aim return restores every cell across region boundaries")
   cases.append({"center":center,"offset":offset,"exact_restore":same,"return":returned})
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_return_nearby.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures,"cases":cases},"  "));file.close()
 print("WATER_RETURN_NEARBY failures=",failures);quit(failures)
