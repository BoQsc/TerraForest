# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var failures:=0
 for seed_value in [0,1,42,50,141,1703,9999]:
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,13)
  var center:Vector3=layout.sites[2].position
  var catalog=preload("res://addons/structures/mine_catalog.gd")
  var plan:Dictionary=catalog.parking(center)
  var road:Dictionary=catalog.access_plan(layout.underground[0].entrance,center)
  var chassis:AABB=plan.pose*AABB(Vector3(-1.1,-0.9,-2.2),Vector3(2.2,1.8,4.4))
  var ok:bool=plan.bounds.encloses(chassis)
  for segment:Dictionary in road.segments:
   # Include pedestrian clearance as well as the full authored road width.
   var a:Vector3=segment.start;var b:Vector3=segment.finish;var w:float=segment.half_width+0.5
   var corridor:=AABB(a.min(b)-Vector3(w,1,w),a.max(b)-a.min(b)+Vector3(2*w,5,2*w))
   ok=ok and not chassis.intersects(corridor)
  if not ok:failures+=1
  print("PASS " if ok else "FAIL ","mine parked chassis leaves access corridor clear seed=",seed_value)
 print("MINE_PARKING_CLEARANCE failures=",failures);quit(1 if failures else 0)
