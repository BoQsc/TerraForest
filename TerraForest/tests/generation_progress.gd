# SPDX-License-Identifier: 0BSD
extends SceneTree
const Progress=preload("res://addons/world_runtime/generation_progress.gd")
var failures:=0
func check(ok:bool,message:String)->void:
 if not ok:failures+=1;push_error(message)
func accounted(data:Dictionary)->int:
 var total:=int(data.stage_microseconds)+int(data.timings_dropped_microseconds)
 for row:Dictionary in data.timings:total+=int(row.microseconds)
 return total
func _initialize()->void:
 var path:="user://generation_progress_"+Crypto.new().generate_random_bytes(16).hex_encode()+".json"
 for index in 180:
  check(Progress.write(path,"Initializing generated terrain data",index,180,{"activity":"Loading game resources %d / 180"%index}),"resource progress writes")
 check(Progress.write(path,"Building roads and foundations"),"bake transition writes")
 check(Progress.write(path,"Saving generated world"),"save transition writes")
 check(Progress.write(path,"Building roads and foundations"),"repeated stage writes")
 check(Progress.write(path,"World generation complete"),"completion writes")
 var data:=Progress.read(path)
 check(data.timings.size()==3,"resource counters cannot displace bake/save timings")
 check(data.timings[1].stage=="Building roads and foundations" and data.timings[1].visits==2,"revisited stage accumulates instead of consuming another row")
 check(accounted(data)==int(data.elapsed_microseconds),"all elapsed time is attributed exactly once")
 check(data.timings_dropped_transitions==0,"ordinary generation retains all stage records")
 for index in 90:check(Progress.write(path,"Extra stage %d"%index),"bounded overflow writes")
 data=Progress.read(path)
 check(not data.is_empty() and data.timings.size()==64,"bounded timing report remains readable")
 check(data.timings_dropped_transitions>0,"overflow is explicit")
 check(accounted(data)==int(data.elapsed_microseconds),"overflow still accounts for all elapsed time")
 check(not Progress.write(path,"Invalid",2,1),"invalid work counts rejected")
 Progress.observations.erase(path)
 check(DirAccess.remove_absolute(path)==OK,"owned test report removed")
 print("GENERATION_PROGRESS failures=",failures)
 quit(1 if failures else 0)
