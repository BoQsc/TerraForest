# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;print("FAIL ",label)
func _initialize()->void:
 var archive=ClassDB.instantiate("NativeWorldArchive")
 var sections:Dictionary={"terrain":PackedByteArray([1])}
 for i in 127:sections["section_%03d"%i]=PackedByteArray([i])
 var packed:PackedByteArray=archive.encode(sections)
 check(not packed.is_empty() and archive.decode(packed).get("ok",false),"128 archive sections roundtrip")
 sections["excess"]=PackedByteArray([1])
 check(archive.encode(sections).is_empty(),"129 sections rejected")
 var region=ClassDB.instantiate("NativeGeneratedRegion")
 check(region.validate_snapshot(PackedByteArray()),"legacy empty")
 var places:Array=[{"id":3,"title":"Hillside","detail":"Saved location","position":Vector3(900,60,400)}]
 var roads:Array=[{"a":Vector3(900,60,400),"b":Vector3(910,61,400),"width":6.0}]
 check(region.set_plan(42,17,places,roads),"valid publication")
 var events:Array=[]
 var observed:=func(revision:int):events.append([revision,region.get_place_position(3)])
 region.plan_changed.connect(observed)
 var saved:PackedByteArray=region.capture_snapshot()
 check(region.get_place_position(3)==places[0].position and region.get_place_position(4)==Vector3.INF,"indexed place reads")
 var poses:Array=[Transform3D(Basis.IDENTITY,Vector3(905,60.5,400)),Transform3D(Basis.IDENTITY,Vector3(905,60.5,406)),Transform3D(Basis.IDENTITY,Vector3(905,70,400))]
 check(region.placement_mask(poses,2.0)==PackedByteArray([1,0,0]),"road root clearance and vertical separation")
 check(region.placement_mask(poses,5.0).is_empty(),"bounded clearance margin")

 for length in saved.size():
  if length==0:continue
  check(not region.restore_snapshot(saved.slice(0,length)),"reject truncated")
 check(region.capture_snapshot()==saved,"failed restores preserve state")
 var bad:PackedByteArray=saved.duplicate();bad.encode_u32(16,257)
 check(not region.restore_snapshot(bad),"bounded places")
 bad=saved.duplicate();bad.encode_float(28,NAN)
 check(not region.restore_snapshot(bad),"finite coordinates")
 check(not region.set_plan(42,17,[places[0],places[0]],roads),"duplicate IDs")
 check(not region.set_plan(42,16,places,roads),"wrong generator")
 check(region.capture_snapshot()==saved,"failed publications preserve state")
 check(events.is_empty(),"rejected requests do not notify listeners")
 check(region.restore_snapshot(PackedByteArray()) and region.restore_snapshot(saved),"clear and restore metadata")
 check(events==[[2,Vector3.INF],[3,places[0].position]],"post-commit events expose the updated index and revision")
 region.plan_changed.disconnect(observed)
 var other=ClassDB.instantiate("NativeGeneratedRegion")
 check(other.restore_snapshot(saved) and other.capture_snapshot()==saved,"exact roundtrip")
 check(other.placement_mask(poses,2.0)==PackedByteArray([1,0,0]),"road index rebuilt on restore")
 check(other.get_plan().places[0].position==places[0].position,"decoded position")
 for generator in [18,19]:
  check(other.set_plan(42,generator,places,roads),"coast generator navigation publishes")
  var coast:PackedByteArray=other.capture_snapshot()
  check(other.restore_snapshot(coast) and other.get_plan().generator==generator,"coast navigation identity survives storage")
 # Compare the former single-place caller with the indexed API on identical metadata.
 var district_roads:=roads.duplicate()
 district_roads.resize(1024)
 district_roads.fill(roads[0])
 check(other.set_plan(42,17,places,district_roads),"large district publication")
 var start:=Time.get_ticks_usec()
 var position_sum:=Vector3.ZERO
 for i in 64:position_sum+=Vector3(other.get_plan().places[0].position)
 var full_plan_us:=Time.get_ticks_usec()-start
 start=Time.get_ticks_usec()
 var indexed_sum:=Vector3.ZERO
 for i in 64:indexed_sum+=Vector3(other.get_place_position(3))
 var indexed_us:=Time.get_ticks_usec()-start
 check(indexed_sum==position_sum,"indexed and full-plan reads agree across the district")
 print("PLACE_QUERIES roads=1024 reads=64 full_plan_us=",full_plan_us," indexed_us=",indexed_us)
 print("GENERATED_REGION failures=",failures)
 quit(0 if failures==0 else 1)
