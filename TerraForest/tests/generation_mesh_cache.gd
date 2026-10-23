# SPDX-License-Identifier: 0BSD
extends SceneTree
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func wait_kind(backend:RefCounted,kind:String)->Dictionary:
 var deadline:=Time.get_ticks_msec()+15000
 while Time.get_ticks_msec()<deadline:
  for data:Dictionary in backend.poll():
   if data.kind==kind:return data
  await process_frame
 return {}
func run()->void:
 GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 var hashes:Dictionary={};var rows:Array=[]
 for warm in [false,true]:
  var backend:=Backend.new();backend.world_generator=19
  backend.configure_initial_earthworks([Codec.graded_bed(Vector3(1000,70,1000),Vector3(1016,70,1000),3,2,4,4)],"c".repeat(64))
  check(backend.start(true)==OK,"native baking worker starts")
  var startup:=await wait_kind(backend,"startup")
  check(not startup.is_empty() and backend.initial_earthworks_result.get("ok",false),"prepared terrain loads")
  for key in [Vector3i(992,992,16),Vector3i(1008,992,16),Vector3i(992,1008,16),Vector3i(1008,1008,16)]:
   backend.submit({"kind":"mesh","key":key,"epoch":0,"stamp":0,"base":false})
   var result:=await wait_kind(backend,"mesh")
   if result.is_empty() or result.has("error"):check(false,"valid prepared mesh");continue
   var fingerprint:=preload("res://addons/world_runtime/survey_cache.gd").digest(var_to_bytes(result.arrays)).hex_encode()
   if warm:check(result.geometry_cached and hashes[key]==fingerprint,"separate worker reuses exact prepared geometry and lighting "+str(key))
   else:hashes[key]=fingerprint;check(result.cache_stats.writes>0,"prepared geometry persists into bounded cache")
   rows.append({"warm":warm,"key":str(key),"worker_ms":result.worker_ms,"geometry_cached":result.geometry_cached,"cache":result.cache_stats})
  backend.stop();backend=null
 FileAccess.open("res://reports/generation_mesh_cache.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rows":rows,"scope":"Two independent terrain workers, same prepared field and shared bounded cache; no gameplay FPS claim"},"  "))
 print("GENERATION_MESH_CACHE failures=",failures);quit(1 if failures else 0)
