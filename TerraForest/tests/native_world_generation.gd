# SPDX-License-Identifier: 0BSD
extends SceneTree
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:
 var failures:=0
 var folder:="user://test_generation_plan_%d"%Time.get_ticks_usec()
 var first:=Plan.build(42,19,true,true,folder)
 if not first.get("ok",false):print("PLAN_FAILED ",first);quit(1);return
 var second:=Plan.build(42,19,true,true,folder)
 if not second.get("cache_hit",false) or first.plan_digest!=second.get("plan_digest") or first.works!=second.get("works"):failures+=1
 if first.plan.lots.size()!=12 or first.market.lots.size()!=8:failures+=1
 for site:String in ["plan","market"]:
  for i in first[site].lots.size():
   var a:Dictionary=first[site].lots[i];var b:Dictionary=second[site].lots[i]
   if a.origin!=b.origin or a.bounds!=b.bounds or a.survey!=b.survey or a.asset.foundation_samples(a.origin,a.rotation,0)!=b.asset.foundation_samples(b.origin,b.rotation,0):failures+=1
 var path:=Plan.path_for(42,19,true,true,folder)
 var file:=FileAccess.open(path,FileAccess.READ_WRITE);file.seek(33);file.store_8(255);file.close()
 if not Plan.read_plan(path,42,19,true,true).is_empty():failures+=1
 var recovered:=Plan.build(42,19,true,true,folder)
 if not recovered.get("cache_persisted",false) or recovered.get("cache_hit",true) or recovered.get("plan_digest")!=first.plan_digest:failures+=1
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[42,19]))
 if core.plan_regional_route(Vector3(NAN,0,0),Vector3.ZERO,[]).ok:failures+=1
 if core.plan_streets([],PackedVector3Array()).ok:failures+=1
 if core.plan_lots(Vector3.ZERO,[],[],true).ok:failures+=1
 var preview:=Plan.preview(42,19)
 if not preview.get("ok",false) or preview.get("building_count",0)!=20 or preview.get("pixels",PackedByteArray()).size()!=256*256*4 or preview.get("plan_digest")!=first.plan_digest:failures+=1
 # Bound disposable cache growth without touching unrelated user files.
 var unrelated:=FileAccess.open(folder.path_join("keep.txt"),FileAccess.WRITE);unrelated.store_string("keep");unrelated.close()
 for i in 35:
  var entry:=FileAccess.open(folder.path_join("plan_1_%d_19_1_1.bin"%i),FileAccess.WRITE);entry.store_buffer(PackedByteArray([1]));entry.close()
 Plan.trim_cache(folder,path)
 var count:=0
 for name:String in DirAccess.get_files_at(folder):
  if name.ends_with(".bin"):count+=1
 if count>Plan.CACHE_ENTRIES or not FileAccess.file_exists(folder.path_join("keep.txt")):failures+=1
 for name:String in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(name))
 print("GENERATION_PLAN cold_ms=",first.worker_ms," warm_ms=",second.worker_ms," buildings=20 segments=",first.works.segments.size()," digest=",first.plan_digest," failures=",failures)
 DirAccess.remove_absolute(folder)
 quit(1 if failures else 0)
