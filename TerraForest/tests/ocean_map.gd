# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:
 var water=ClassDB.instantiate("NativeRegionalWater");water.set_surrounding_ocean(true)
 var revision:int=water.survey_revision_id();var cursor:=0;var count:=0
 var side:=[false,false,false,false]
 while true:
  var reply:Dictionary=water.survey_ocean(cursor,revision)
  if not reply.get("ok",false):check(false,"implicit source valid");break
  check(reply.points.size()<=256,"bounded implicit source batch")
  for point:Vector3 in reply.points:
   count+=1
   if point.x<20:side[0]=true
   if point.x>1980:side[1]=true
   if point.z<20:side[2]=true
   if point.z>1980:side[3]=true
  cursor=reply.cursor
  if reply.complete:break
 check(count>60000 and side.all(func(v):return v),"whole ocean perimeter sampled")
 check(water.statistics().regions==0 and water.statistics().water_ml==0,"map source creates no live water")
 water.update_ocean_residency(Vector3(4,40,1000),1)
 check(water.survey_revision_id()==revision,"pristine admission does not invalidate map")
 var patch=ClassDB.instantiate("NativeWaterTerrainPatch");patch.configure(water.next_request().coordinate)
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,19]))
 for i in 1000:
  if patch.sample_terrain(core,256,0,0)!=0:break
 check(water.accept_patch(patch) and water.survey_revision_id()==revision,"pristine preparation does not invalidate map")
 water.update_ocean_residency(Vector3(1000,40,1000),1)
 check(water.survey_revision_id()==revision,"pristine retirement preserves logical map")
 water.update_ocean_residency(Vector3(4,40,1000),1)
 check(water.survey_revision_id()==revision,"cache restoration preserves logical map")
 water.brush(Vector3(6,31.8,1002),1.5,-1000000)
 check(water.survey_revision_id()!=revision and water.survey_ocean(0,revision).get("stale",false),"real water edits invalidate map continuations")
 var top=ClassDB.instantiate("NativeRegionalWater");top.set_surrounding_ocean(true)
 top.update_ocean_residency(Vector3(18,40,1002),3)
 for region in 3:
  var cell_patch=ClassDB.instantiate("NativeWaterTerrainPatch");cell_patch.configure(top.next_request().coordinate)
  for step in 1000:
   if cell_patch.sample_terrain(core,256,0,0)!=0:break
  check(top.accept_patch(cell_patch),"sea-column fixture prepared")
 check(top.remove_bounds(AABB(Vector3(16,36,1000),Vector3(4,4,4)))>0,"top water region removed")
 var top_cursor:=0;var refilled:=false
 while true:
  var part:Dictionary=top.survey_ocean(top_cursor,top.survey_revision_id());top_cursor=part.cursor
  for point:Vector3 in part.points:
   if point.x>=16 and point.x<20 and point.z>=1000 and point.z<1004:refilled=true
  if part.complete:break
 check(not refilled,"implicit sea never paints back removed top water")
 var lower:Dictionary=top.survey_surfaces(0,top.survey_revision_id(),4)
 check(lower.ok and not lower.points.is_empty(),"lower pristine water remains represented beneath an edited surface")
 var samples:=PackedVector3Array()
 for z in 16:
  for x in 16:samples.append(Vector3(2+x*8,40,900+z*8))
 var fast:Dictionary=core.survey_water_visibility(samples)
 check(fast.ok and fast.visible.size()>16 and fast.visible.size()<=256,"pristine sea visibility handles bounded bulk")
 var compared:=0
 for i in fast.visible.size():
  if i%16!=0:continue
  var p:Vector3=samples[i];p.y+=0.001
  var slow:Dictionary=core.survey_water_visibility(PackedVector3Array([p]))
  check(slow.ok and slow.visible[0]==fast.visible[i],"bulk sea visibility agrees with density scan")
  compared+=1
 check(compared>0,"visibility comparisons performed")
 var sea:=Vector3(20,40,1000);var roof:=sea+Vector3.UP*5
 core.execute(Codec.brush(roof,roof,4,1,true,3))
 check(core.survey_water_visibility(PackedVector3Array([sea])).visible==PackedByteArray([0]),"terrain roof disables procedural sea shortcut")
 core.execute(Codec.brush(roof,roof,4,1,false,3))
 check(core.survey_water_visibility(PackedVector3Array([sea])).visible==PackedByteArray([1]),"excavation restores visible sea through live density scan")
 print("OCEAN_MAP failures=",failures," points=",count);quit(failures)
