# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
 var raster=ClassDB.instantiate("NativeSurfaceMapRaster");raster.configure(512)
 var boxes:Array=[AABB(Vector3(0,10,0),Vector3(50,4,50))]
 var cursor:=Vector2i.ZERO;var points:=PackedVector3Array();var calls:=0
 while calls<10:
  var result:Dictionary=raster.project_bounds(boxes,Transform3D(Basis.IDENTITY,Vector3(100,0,100)),cursor)
  check(result.ok and result.points.size()<=256,"projection batch bounded")
  points.append_array(result.points);cursor=result.cursor;calls+=1
  if result.complete:break
 check(calls>1 and points.size()>256 and cursor.x==1,"large footprint continues across calls")
 var unique:Dictionary={}
 for point in points:unique[point]=true
 check(unique.size()==points.size(),"continuation emits each subcell once")
 check(points[0].x>99 and points[0].y==14 and points[-1].z<152,"world transform and model top respected")
 var tiny:Dictionary=raster.project_bounds([AABB(Vector3.ZERO,Vector3.ONE)],Transform3D.IDENTITY,Vector2i.ZERO)
 check(tiny.ok and tiny.complete and tiny.points.is_empty(),"small prop omitted from regional building coverage")
 var clipped:Dictionary=raster.project_bounds([AABB(Vector3(-10,10,-10),Vector3(20,2,20))],Transform3D.IDENTITY,Vector2i.ZERO)
 check(clipped.ok and not clipped.points.is_empty() and clipped.points[0].x>=0 and clipped.points[0].z>=0,"map boundary clips instead of rejecting whole object")
 check(not raster.project_bounds(boxes,Transform3D.IDENTITY,Vector2i(-1,0)).ok,"invalid continuation rejected")
 print("MODEL_MAP_PROJECTION failures=",failures);quit(1 if failures else 0)
