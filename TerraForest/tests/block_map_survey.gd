# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func collect(source:Callable)->PackedVector3Array:
 var at:=0;var points:=PackedVector3Array()
 for n in 65:
  var part:Dictionary=source.call(at)
  if not part.get("ok",false) or part.points.size()>256:return PackedVector3Array()
  points.append_array(part.points);at=part.offset
  if part.complete:return points
 return PackedVector3Array()
func _initialize()->void:
 var blocks=ClassDB.instantiate("NativeBlockWorld")
 check(blocks.set_cells(PackedInt32Array([1,1,1,1,1,4,1,2,2,3,1,4,17,1,1,3,-1,2,0,1])),"author cube, slab, slope, stair and signed-coordinate samples")
 var snapshot:PackedByteArray=blocks.capture_snapshot()
 check(blocks.restore_snapshot(snapshot),"validated snapshot restores")
 var identity:String=blocks.survey_cache_identity()
 check(not identity.is_empty(),"snapshot certifies block map identity")
 var index:Dictionary=blocks.survey_index();var key:=Vector3i.ZERO
 var before:=collect(func(at:int):return blocks.survey_columns(key,at,index.revision))
 check(before==PackedVector3Array([Vector3(1.5,4.5,1.5),Vector3(2.5,3.5,1.5),Vector3(17.5,1.75,1.5)]),"survey uses highest column and shape centre height")
 var packet:PackedByteArray=blocks.capture_region(key);var digest:=packet.slice(packet.size()-32)
 var region=ClassDB.instantiate("NativeBlockMapRegion")
 check(region.load_packet(packet,digest),"checksum-bound archived region decodes")
 check(collect(region.columns)==before,"archived and resident columns match")
 check(blocks.unload_region(packet),"real region unloaded")
 check(blocks.survey_cache_identity()==identity,"block unload preserves logical identity")
 check(blocks.survey_columns(key,0,index.revision).get("stale",false),"changed storage rejects old cursor revision")
 index=blocks.survey_index()
 check(index.keys.size()==6 and index.checksums.slice(32,64)==digest,"nonresident region remains in survey index with exact checksum")
 check(blocks.survey_columns(key,0,index.revision).get("unloaded",false),"unloaded geometry is explicit, never treated as empty")
 check(collect(region.columns)==before and blocks.region_stats().unloaded_regions==1,"map decoder does not repopulate gameplay residency")
 var corrupt:=packet.duplicate();corrupt[30]^=1
 check(not region.load_packet(corrupt,digest) and region.columns(0).is_empty(),"corrupt region cannot expose old map data")
 check(not region.load_packet(packet,PackedByteArray()) and not blocks.survey_columns(key,-1,index.revision).get("ok",false),"bad checksum and cursor rejected")
 check(blocks.restore_region(packet,PackedByteArray()) and blocks.survey_cache_identity()==identity,"exact block admission preserves identity")
 check(blocks.set_cells(PackedInt32Array([1,1,1,0])) and blocks.survey_cache_identity().is_empty(),"authored block edit clears identity")
 check(blocks.restore_storage_state(snapshot,PackedInt32Array(),PackedByteArray()) and not blocks.survey_cache_identity().is_empty(),"validated storage state certifies map identity")
 blocks.free();print("BLOCK_MAP_SURVEY failures=",failures);quit(1 if failures else 0)
