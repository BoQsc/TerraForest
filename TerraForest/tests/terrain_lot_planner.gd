# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
func _initialize()->void:
 var failures:=0;var reports:Array=[]
 for seed_value in [0,1,42,50,141,1703,9999]:
  var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,17]))
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,16)
  var center:Vector3=layout.sites[3].position
  var plan:Dictionary=Planner.plan(core,center)
  var roads:Dictionary=Planner.streets(core,center)
  var low:=INF;var high:=-INF;var relocated:=0
  var original:Array=preload("res://addons/structures/northern_lots.gd").recipe(center)
  for lot:Dictionary in plan.lots:
   var points:PackedVector3Array=lot.asset.foundation_samples(lot.origin,lot.rotation,0)
   var raw:PackedFloat32Array=Planner.heights(core,points)
   for h in raw:
    if lot.survey.grade-h>2.0001 or h-lot.survey.grade>3.0001:failures+=1
   low=minf(low,lot.origin.y);high=maxf(high,lot.origin.y)
   for previous:Dictionary in original:
    if previous.label==lot.label and (previous.origin.x!=lot.origin.x or previous.origin.z!=lot.origin.z):relocated+=1
  if plan.ok and plan.lots.size()!=12:failures+=1
  var summary:Dictionary={"seed":seed_value,"accepted_lots":plan.lots.size(),"rejected":plan.rejected,
   "min_grade":low,"max_grade":high,"relocated":relocated,"lots_fit":plan.ok,
   "streets_fit":roads.ok,"street_reason":roads.get("reason",""),"foundations_and_streets_fit":plan.ok and roads.ok}
  var located:Dictionary=Planner.locate(core,center)
  summary["located"]=located.ok;summary["attempts"]=located.attempts
  if not located.ok:failures+=1;print("LOCATE_REJECT ",located)
  if located.ok:
   var protected:Dictionary=Planner.reservations(core,center)
   var works:Dictionary=Planner.earthworks(located)
   if not protected.ok or not works.ok:failures+=1
   else:
    var footprint:=Rect2(Vector2(works.bounds.position.x,works.bounds.position.z),Vector2(works.bounds.size.x,works.bounds.size.z))
    for area:Rect2 in protected.areas:
     if footprint.intersects(area):failures+=1;print("RESERVATION_OVERLAP ",seed_value," ",area)
     var probe:=AABB(Vector3(area.get_center().x,0,area.get_center().y)-Vector3(0.5,0,0.5),Vector3.ONE)
     if Planner.footprint_clear(probe,protected.areas):failures+=1;print("RESERVATION_NOT_ENFORCED")
    if protected.areas.size()!=10:failures+=1
    summary["protected_areas"]=protected.areas.size()
   summary["offset"]=str(located.center-center)
   summary["mean_earthwork"]=located.mean_earthwork;summary["max_cut"]=located.max_cut;summary["max_fill"]=located.max_fill;summary["ranked_candidates"]=located.ranked_candidates
   summary["entrances"]=located.lots.size()
   var flat_segments:=0
   for road:Dictionary in located.roads:
    if not is_equal_approx(road.start.y,roundf(road.start.y)) or not is_equal_approx(road.finish.y,roundf(road.finish.y)):failures+=1
    if road.start.distance_to(road.finish)>2 and is_equal_approx(road.start.y,road.finish.y):flat_segments+=1
   if flat_segments==0 or works.get("ok",false) and located.block_paving.tiles<=0:failures+=1
   for lot:Dictionary in located.lots:
    if not lot.entrance.get("ok",false):failures+=1
    var foundations:PackedVector3Array=lot.asset.foundation_samples(lot.origin,lot.rotation,0)
    var terrain:PackedFloat32Array=Planner.heights(core,foundations)
    for h in terrain:
     if lot.survey.grade-h>2.0001 or h-lot.survey.grade>3.0001:failures+=1
   # Verify the returned geometry, not just the planner's success flags.
   for road:Dictionary in located.roads:
    var span:Vector3=road.finish-road.start
    if absf(span.y)>Vector2(span.x,span.z).length()*0.12001:failures+=1
    var probes:=PackedVector3Array()
    var across:=Vector3(-span.z,0,span.x).normalized()
    for step in 13:
     for side in [-4,-3,-1,1,3,4]:probes.append(road.start.lerp(road.finish,step/12.0)+across*side)
    var terrain:PackedFloat32Array=Planner.heights(core,probes)
    for i in probes.size():
     if probes[i].y-terrain[i]>2.001 or terrain[i]-probes[i].y>3.001:failures+=1
  reports.append(summary);print("RAW_LOT_PLAN ",JSON.stringify(summary))
 var file:=FileAccess.open("res://reports/terrain_lot_planner.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(reports,"  "))
 print("TERRAIN_LOT_PLANNER failures=",failures)
 quit(1 if failures else 0)
