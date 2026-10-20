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
 var saved:PackedByteArray=region.capture_snapshot()
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
 var other=ClassDB.instantiate("NativeGeneratedRegion")
 check(other.restore_snapshot(saved) and other.capture_snapshot()==saved,"exact roundtrip")
 check(other.placement_mask(poses,2.0)==PackedByteArray([1,0,0]),"road index rebuilt on restore")
 check(other.get_plan().places[0].position==places[0].position,"decoded position")
 print("GENERATED_REGION failures=",failures)
 quit(0 if failures==0 else 1)
