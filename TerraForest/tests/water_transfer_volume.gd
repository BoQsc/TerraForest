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
 var from:=Vector3(41.5,43,41.5);var to:=Vector3(41.5,41,41.5)
 var result:Dictionary=water.transfer_bucket(from,to,false,inventory,0,inventory.snapshot().revision)
 check(result.ok and result.water_ml==1000000 and water.statistics().water_ml==0 and inventory.snapshot().slots[0].water_ml==1000000,"One scoop transfers exactly one cubic metre out of the targeted source")
 check(not water.raycast_surface(from,to).hit,"Scooped source visibly disappears")
 from=Vector3(43,43,41.5);to=Vector3(43,41.25,41.5)
 result=water.transfer_bucket(from,to,true,inventory,0,inventory.snapshot().revision)
 check(result.ok and inventory.snapshot().slots[0].water_ml==0 and water.statistics().water_ml==1000000,"One pour transfers the same cubic metre into a separate basin")
 var hit:Dictionary=water.raycast_surface(from,to)
 check(hit.hit and abs(hit.point.y-42)<0.001,"Visible basin fills to its measured one-metre height immediately")
 var captured:PackedByteArray=water.capture_snapshot(catalog);base=32+captured.decode_u32(8)
 var full:=0;var overfull:=false
 for i in 512:
  var amount:int=captured.decode_u64(base+20+i*12)&0x7fffffffffffffff
  if amount:full+=1
  overfull=overfull or amount>125000
 check(full==8 and not overfull,"Placement owns eight full half-metre cells, never one hidden overfull cell")
 var reopened=ClassDB.instantiate("NativeRegionalWater");reopened.restore_snapshot(captured)
 hit=reopened.raycast_surface(from,to)
 check(reopened.statistics().water_ml==1000000 and hit.hit and abs(hit.point.y-42)<0.001,"Cached reload preserves quantity and visible fill height")
 inventory.exchange_water(0,false,inventory.snapshot().revision,1000000)
 var before:PackedByteArray=water.capture_snapshot(catalog);var held:Dictionary=inventory.snapshot()
 result=water.transfer_bucket(from,to,true,inventory,0,held.revision)
 check(not result.ok and inventory.snapshot()==held and water.capture_snapshot(catalog)==before,"Pour into a full sealed basin fails without losing or hiding water")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_transfer_volume.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
 print("WATER_TRANSFER_VOLUME failures=",failures);quit(failures)
