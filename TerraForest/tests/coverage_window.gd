# SPDX-License-Identifier: 0BSD
extends SceneTree
const Coverage=preload("res://addons/world_runtime/coverage_window.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
func _initialize()->void:
 var owners:Dictionary={}
 for z in 32:
  for x in 32:owners[Vector2i(x,z)]=true
 var position:=Vector3(1024,0,1024)
 var full:=Coverage.inspect(position,640,owners,[])
 check(full.ready and full.total<1024,"local readiness is bounded")
 owners.erase(Vector2i(16,16))
 check(not Coverage.inspect(position,640,owners,[]).ready,"missing nearby owner blocks entry")
 owners[Vector2i(16,16)]=true;owners.erase(Vector2i.ZERO)
 check(Coverage.inspect(position,640,owners,[{Vector2i.ZERO:true}]).ready,"distant pending owner does not block local entry")
 check(not Coverage.inspect(position,640,owners,[{Vector2i(16,16):true}]).ready,"nearby invalidation blocks entry")
 check(not Coverage.inspect(Vector3(9000,0,9000),640,owners,[]).ready,"outside-world empty window cannot pass")
 check(Coverage.required(Vector3(9000,0,9000),640,Vector2i.ZERO),"outside-grid fallback still admits whole-world work")
 check(Coverage.inspect(Vector3(2688,0,1024),640,owners,[]).total>0,"tangent window includes boundary owners")
 check(not Coverage.required(position,640,Vector2i.ZERO),"distant startup owner stays deferred")
 check(Coverage.required(position,640,Vector2i(16,16)),"near startup owner is admitted")
 var forest=preload("res://addons/world_ecosystem/world_ecosystem.gd").new()
 forest.world_coverage=true;forest.resident=owners.duplicate()
 check(forest.surface_owner_ready(Vector2i(16,16)),"boulder can follow a ready forest owner")
 forest._resample[Vector2i(16,16)]=true
 check(not forest.surface_owner_ready(Vector2i(16,16)),"boulder waits for invalidated forest owner")
 check(not forest.local_coverage_status(position).ready,"local adapter retains pending invalidation")
 forest._resample.clear()
 check(forest.local_coverage_status(position).ready and not forest.coverage_status().ready,"local readiness does not require distant owner")
 check(not forest.local_coverage_status(Vector3(9000,0,9000)).ready,"outside grid retains whole-world fallback")
 forest.free()
 print("COVERAGE_WINDOW failures=",failures);quit(0 if failures==0 else 1)
