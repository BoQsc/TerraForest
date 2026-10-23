# SPDX-License-Identifier: 0BSD
extends SceneTree
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func startup(backend:RefCounted)->Dictionary:
 var deadline:=Time.get_ticks_msec()+15000
 while Time.get_ticks_msec()<deadline:
  for value:Dictionary in backend.poll():
   if value.kind=="startup":return value
  await process_frame
 return {}
func configured()->RefCounted:
 var backend:=Backend.new();backend.disk_cache.enabled=false;backend.world_generator=17;backend.world_seed=42
 backend.snapshot_validators["volumetric_water"]=ClassDB.instantiate("NativeRegionalWater")
 check(backend.configure_initial_lake_bake(),"new offline authoring configuration is admitted")
 return backend
func run()->void:
 var backend:=configured();check(backend.start(true)==OK,"native generation worker starts")
 var result:Dictionary=await startup(backend)
 check(not result.is_empty() and backend.initial_lakes_result.get("ok",false),"lake data is baked before first world publication")
 var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
 check(water.restore_snapshot(result.get("components",{}).get("volumetric_water",PackedByteArray())) and water.statistics().pending_regions==0,"published data restores with all occupancy requests completed")
 check(not backend.configure_initial_lake_bake(),"running worker cannot be reconfigured")
 backend.stop()
 var path:="user://offline_lake_protected_%d.trw"%Time.get_ticks_usec()
 FileAccess.open(path,FileAccess.WRITE).store_string("original world sentinel")
 var protected:=configured();protected.save_path=path;protected.start(true)
 result=await startup(protected)
 check(result.get("message","").begins_with("ERROR:") and not protected.write_allowed and FileAccess.get_file_as_string(path)=="original world sentinel","generation-only bake never replaces an existing world")
 protected.stop();DirAccess.remove_absolute(path)
 var cancelled:=configured();cancelled.start(true)
 var deadline:=Time.get_ticks_msec()+1000
 while cancelled._initial_lake_bake.progress().status==0 and Time.get_ticks_msec()<deadline:await process_frame
 var began:=Time.get_ticks_usec();cancelled.stop()
 check(Time.get_ticks_usec()-began<1000000 and not cancelled.initial_lakes_result.get("ok",false),"backend stop cancels authoring before joining its worker")
 print("OFFLINE_LAKES_STARTUP failures=",failures);quit(1 if failures else 0)
