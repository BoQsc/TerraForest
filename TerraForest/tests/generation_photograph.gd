extends SceneTree
const Generation=preload("res://addons/world_runtime/generate_world_task.gd")
var failures:=0
var checks:=0
func check(value:bool,message:String)->void:
 checks+=1
 if not value:failures+=1
 print("PASS " if value else "FAIL ",message)
func _initialize()->void:
 check(Generation.road_photograph_view(PackedVector3Array()).is_empty(),"empty road has no photograph")
 check(Generation.road_photograph_view(PackedVector3Array([Vector3.ZERO])).is_empty(),"single waypoint has no photograph")
 var points:=PackedVector3Array([Vector3(10,20,30),Vector3(40,22,32)])
 var view:=Generation.road_photograph_view(points)
 check(view.anchor==points[0] and view.target==points[1]+Vector3.UP*1.7,"two-point route uses its only valid segment")
 points.append(Vector3(80,24,40))
 view=Generation.road_photograph_view(points)
 check(view.anchor==points[1] and view.target==points[2]+Vector3.UP*1.7,"three-point route retains middle view")
 points.append(Vector3(120,26,40));points.append(Vector3(160,28,40))
 view=Generation.road_photograph_view(points)
 check(view.anchor==points[2] and view.target==points[3]+Vector3.UP*1.7,"long route retains middle view")
 print("GENERATION_PHOTOGRAPH checks=%d failures=%d"%[checks,failures])
 quit(1 if failures else 0)
