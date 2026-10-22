# SPDX-License-Identifier: 0BSD
extends "res://tests/water_region_store.gd"
func _initialize()->void:
 var folder:=ProjectSettings.globalize_path("user://water_metadata_"+str(Time.get_ticks_usec()))
 var store=ClassDB.instantiate("NativeWaterRegionStore");check(store.open_store(folder),"isolated metadata store opens")
 var component:PackedByteArray=store.publish_water_snapshot(packet(125000))
 var description:Dictionary=store.describe_water_snapshot(component)
 check(description.ok and description.archived_regions==1 and not description.blobs_verified,"metadata identifies unloaded data without claiming blob validation")
 var base=ClassDB.instantiate("NativeRegionalWater")
 check(base.restore_snapshot(description.base) and base.statistics().regions==0,"metadata load creates no archived resident regions")
 var page:Dictionary=store.checkpoint_window(description.checkpoint,Vector3i(0,7,240),Vector3i(5,10,260),0,1)
 check(page.ok and page.complete and page.coordinates==PackedInt32Array([1,9,250]),"near window selects archived edit")
 page=store.checkpoint_window(description.checkpoint,Vector3i(50,0,0),Vector3i(60,63,499),0,256)
 check(page.ok and page.complete and page.coordinates.is_empty(),"distant window admits nothing")
 # Synthetic manifest only: no blob files. This measures metadata, not saved-world
 # correctness. The real read below must reject those unavailable records.
 var count:=6000;var bytes:=PackedByteArray();bytes.resize(12+40*count);bytes.fill(0)
 var magic:PackedByteArray=PackedByteArray([84,70,87,67,1,0,0,0])
 for i in 8:bytes[i]=magic[i]
 bytes.encode_u32(8,count)
 for n in count:bytes.encode_u64(12+n*40,((n/500)<<24)|(9<<12)|(n%500))
 var h:=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes);var id:=h.finish()
 var file:=FileAccess.open(folder.path_join(id.hex_encode()+".checkpoint"),FileAccess.WRITE);file.store_buffer(bytes);file.close()
 var expanded:PackedByteArray=component.duplicate()
 for i in 32:expanded[16+i]=id[i]
 description=store.describe_water_snapshot(expanded)
 check(description.ok and description.archived_regions==6000,"metadata supports more than resident region capacity")
 var cursor:=0;var seen:Dictionary={};var calls:=0;var inspected:=0
 while true:
  page=store.checkpoint_window(id,Vector3i(3,9,200),Vector3i(8,9,300),cursor,37)
  check(page.ok and page.inspected<=1024 and page.coordinates.size()/3<=37,"bounded metadata query")
  inspected+=page.inspected;calls+=1
  for i in range(0,page.coordinates.size(),3):
   var p:=Vector3i(page.coordinates[i],page.coordinates[i+1],page.coordinates[i+2]);check(not seen.has(p),"no duplicate selected region");seen[p]=true
  cursor=page.cursor
  if page.complete:break
  if calls>100:check(false,"query terminates");break
 check(seen.size()==606 and inspected==3000,"exact window membership and x-range skipping")
 check(not store.read_region(id,Vector3i(3,9,250)).ok,"unavailable blob never becomes empty water")
 check(not store.checkpoint_window(id,Vector3i.ZERO,Vector3i(1,1,1),6001,1).ok,"invalid continuation rejected")
 check(base.statistics().regions==0,"metadata scanning never allocates archived water")
 store.close();print("WATER_METADATA_WINDOW failures=",failures," entries=",seen.size()," calls=",calls);quit(1 if failures else 0)
