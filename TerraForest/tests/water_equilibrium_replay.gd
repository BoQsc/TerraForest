# SPDX-License-Identifier: 0BSD
extends SceneTree
# Profiling replay of the actual barrel-review lake, never a gameplay substitute.
func _initialize()->void:
 var path:=""
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--water-replay="):path=argument.trim_prefix("--water-replay=")
 var water=ClassDB.instantiate("NativeRegionalWater")
 if path.is_empty() or not water.restore_snapshot(FileAccess.get_file_as_bytes(path)):
  push_error("A captured actual-game water snapshot is required");quit(1);return
 var total:int=water.statistics().water_ml
 var failures:=0
 for iteration in 3:
  water.settle_after_edit(AABB(Vector3(790,38,1280),Vector3(24,16,24)))
  var job:RefCounted=water.begin_equilibrium()
  if job==null:failures+=1;break
  job.prepare();var result:Dictionary=water.finish_equilibrium(job)
  print("REPLAY ",result)
  if not result.ok or water.statistics().water_ml!=total:failures+=1;break
 print("WATER_EQUILIBRIUM_REPLAY failures=",failures)
 quit(failures)
