# SPDX-License-Identifier: 0BSD
extends SceneTree
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func startup(backend:RefCounted)->Dictionary:
 var deadline:=Time.get_ticks_msec()+10000
 while Time.get_ticks_msec()<deadline:
  for value:Dictionary in backend.poll():
   if value.kind=="startup":return value
  await process_frame
 return {}
func run()->void:
 var packet:=Codec.graded_bed(Vector3(1000,70,1000),Vector3(1016,70,1000),3,2,4,4)
 var backend:=Backend.new();backend.disk_cache.enabled=false
 var packets:Array=[packet]
 check(not backend.configure_initial_earthworks(packets,"") and backend.configure_initial_earthworks(packets,"a".repeat(64)),"offline startup requires valid bounded plan identity")
 packets.clear();packet.encode_float(28,1000)
 check(backend.start(true)==OK,"offline startup worker starts")
 var result:Dictionary=await startup(backend)
 check(not result.is_empty() and backend.initial_earthworks_result.get("ok",false) and backend.initial_earthworks_result.completed==1,"startup freezes configuration and applies native earthworks before first world publication")
 check(backend.snapshot_id.ends_with("_plan_"+"a".repeat(64)),"derived identity includes the applied generation plan")
 check(not backend.configure_initial_earthworks([packet],"b".repeat(64)),"running worker rejects generation reconfiguration")
 backend.stop()
 var path:="user://generation_protected_%d.trw"%Time.get_ticks_usec()
 FileAccess.open(path,FileAccess.WRITE).store_string("original world sentinel")
 var protected:=Backend.new();protected.disk_cache.enabled=false;protected.save_path=path
 packet=Codec.graded_bed(Vector3(1000,70,1000),Vector3(1016,70,1000),3,2,4,4)
 protected.configure_initial_earthworks([packet],"b".repeat(64));protected.start(true)
 result=await startup(protected)
 check(result.get("message","").begins_with("ERROR:") and not protected.write_allowed and FileAccess.get_file_as_string(path)=="original world sentinel","offline initialization never replaces an existing world")
 protected.stop();DirAccess.remove_absolute(path)
 print("GENERATION_EARTHWORKS_STARTUP failures=",failures);quit(1 if failures else 0)
