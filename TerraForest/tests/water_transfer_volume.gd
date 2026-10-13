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
 # A larger source must lose a compact bucket-sized cavity, not BFS arms.
 var lake:=bytes.duplicate();lake.encode_u64(16,18000000)
 for j in 512:
  lake.encode_u16(base+16+j*12,500);lake.encode_u64(base+20+j*12,0)
 for z in range(1,7):
  for y in range(2,6):
   for x in range(1,7):
    var j:int=x+8*y+64*z
    lake.encode_u16(base+16+j*12,0);lake.encode_u64(base+20+j*12,125000)
 var large=ClassDB.instantiate("NativeRegionalWater");assert(large.restore_snapshot(lake))
 inventory.exchange_water(0,true,inventory.snapshot().revision,1000000)
 result=large.transfer_bucket(Vector3(42,44.5,42),Vector3(42,42.25,42),false,inventory,0,inventory.snapshot().revision)
 var after:PackedByteArray=large.capture_snapshot(catalog)
 var removed:=0;var lo:=Vector3i(99,99,99);var hi:=Vector3i(-99,-99,-99)
 for j in 512:
  if lake.decode_u64(base+20+j*12)>after.decode_u64(base+20+j*12):
   removed+=1
   var pos:=Vector3i(j%8,(j/8)%8,j/64)
   lo=lo.min(pos);hi=hi.max(pos)
 check(result.ok and result.water_ml==1000000 and large.statistics().water_ml==17000000,"Large lake scoop conserves one cubic metre")
 check(removed==8 and hi-lo==Vector3i.ONE,"Large lake scoop removes one compact 2 by 2 by 2 group of cells")
 # Editing beside existing water must preserve neighbours, not just the total.
 var neighbours=ClassDB.instantiate("NativeRegionalWater");assert(neighbours.restore_snapshot(lake))
 inventory.exchange_water(0,true,inventory.snapshot().revision,1000000)
 for target:Vector3 in [Vector3(41.5,40.75,41.5),Vector3(42,40.75,42),Vector3(42.5,40.75,42.5),Vector3(40.65,40.75,41.5),Vector3(40.65,40.75,40.65)]:
  assert(neighbours.restore_snapshot(lake))
  var carried:int=inventory.snapshot().slots[0].water_ml
  if carried:inventory.exchange_water(0,true,inventory.snapshot().revision,carried)
  var start:Vector3=target+Vector3.UP*3.75
  var baseline:PackedByteArray=neighbours.capture_snapshot(catalog)
  var scoop:Dictionary=neighbours.transfer_bucket(start,target,false,inventory,0,inventory.snapshot().revision)
  var returned:Dictionary=neighbours.transfer_bucket(start,target,true,inventory,0,inventory.snapshot().revision)
  var restored_cells:PackedByteArray=neighbours.capture_snapshot(catalog)
  var identical:=true
  for j in 512:
   identical=identical and baseline.decode_u64(base+20+j*12)==restored_cells.decode_u64(base+20+j*12)
  print("NEIGHBOUR ",target," scoop=",scoop," pour=",returned," same=",identical)
  check(scoop.ok and returned.ok and identical and inventory.snapshot().slots[0].water_ml==0,"Same-aim scoop and replacement preserve every neighbouring cell at "+str(target))
 # A partial bucket must not be consumed into a body with no render samples.
 var tiny=ClassDB.instantiate("NativeRegionalWater");assert(tiny.restore_snapshot(bytes))
 inventory.exchange_water(0,true,inventory.snapshot().revision,1000000)
 inventory.exchange_water(0,false,inventory.snapshot().revision,1000)
 var before_tiny:PackedByteArray=tiny.capture_snapshot(catalog)
 var before_bucket:Dictionary=inventory.snapshot()
 result=tiny.transfer_bucket(Vector3(43,43,41.5),Vector3(43,41.25,41.5),true,inventory,0,before_bucket.revision)
 check(not result.ok and not result.pending and inventory.snapshot()==before_bucket and tiny.capture_snapshot(catalog)==before_tiny,"Legacy partial pour is rejected without changing bucket or world")
 result=tiny.transfer_bucket(Vector3(41.5,43,41.5),Vector3(41.5,41,41.5),false,inventory,0,inventory.snapshot().revision)
 check(result.ok and inventory.snapshot().slots[0].water_ml==1000000 and tiny.statistics().water_ml==1000,"Legacy partial bucket refills without discarding or creating water")
 var dev=ClassDB.instantiate("NativeRegionalWater");assert(dev.restore_snapshot(bytes))
 check(dev.brush(Vector3(43,41.25,41.5),0.0,1000000)==1000000,"Developer placement accepts one cubic metre")
 var dev_saved:PackedByteArray=dev.capture_snapshot(catalog);var dev_full:=0;var dev_overfull:=false
 for j in 512:
  var ml:int=dev_saved.decode_u64(base+20+j*12)
  if ml==125000:dev_full+=1
  dev_overfull=dev_overfull or ml>125000
 check(dev_full==16 and not dev_overfull,"Developer placement shares bucket capacity rules, without hidden overfilled cells")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_transfer_volume.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
 print("WATER_TRANSFER_VOLUME failures=",failures);quit(failures)
