# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var failures:=0
 for grade in [35.0,40.0,45.0]:
  var plan:={"street_lines":PackedVector3Array([Vector3(900,grade,970),Vector3(950,grade,970)]),"segments":[],"bounds":AABB(Vector3(890,20,960),Vector3(70,40,20)),"paving_segments":0}
  var center:=Vector3(1000,40,1000)
  var accepted:bool=load("res://addons/structures/site_plan.gd").connect_regional_street(plan,center)
  var ok:bool=accepted and plan.segments.size()==4 and plan.segments[2].finish==plan.segments[3].start and plan.segments[-1].finish==center
  ok=ok and plan.segments[0].material==1 and plan.segments[0].shoulder==12 and plan.segments[0].clearance==0 and plan.segments[2].material==4 and plan.segments[2].depth==1
  for segment:Dictionary in plan.segments:
   ok=ok and plan.bounds.encloses(segment.bounds) and segment.bounds.has_point(segment.start) and segment.bounds.has_point(segment.finish)
  print("PASS " if ok else "FAIL ","regional connector meets arterial height from foundation grade ",grade)
  if not ok:failures+=1
 print("REGIONAL_ROAD_CONNECTIONS failures=",failures);quit(1 if failures else 0)
