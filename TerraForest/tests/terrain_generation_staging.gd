# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func fresh()->RefCounted:
 var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,5]));return core
func raw(core:RefCounted)->PackedByteArray:
 var response:PackedByteArray=core.execute(Codec.command(4,[3]));return response.slice(12) if Codec.reply_ok(response) else PackedByteArray()
func clear_store(path:String)->void:
 for name:String in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(name))
 DirAccess.remove_absolute(path)
func run()->void:
 check_profiles()
 var path:=ProjectSettings.globalize_path("user://generation_staging_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 var packets:Array=[]
 for i in 40:
  var p:=Vector3(64+(i%10)*32,128,64+(i/10)*32)
  packets.append(Codec.graded_bed(p,p+Vector3(4,0,0),1,1,0,1))
 var legacy:=fresh();var previous:Dictionary=legacy.bake_generated_earthworks(packets)
 check(previous.get("ok",false),"ordinary native bake establishes exact reference")
 var expected:=raw(legacy);var staged:=fresh()
 var result:Dictionary=staged.bake_generated_earthworks_staged(packets,path,16,64)
 check(result.get("ok",false) and result.get("completed")==40,"bounded native bake completes all commands")
 if not result.get("ok",false):print(result);quit(1);return
 check(result.resident_high<=16 and result.admission_retries>0 and result.checkpoints>2,"dirty pressure checkpoints and retries without raising residency")
 check(raw(staged)==expected,"staging preserves byte-exact field including sample order materials and revisions")
 var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore");check(store.open_store(path,true),"staged write lease released after bake")
 var core:=fresh()
 check(core.mount_storage_checkpoint(path,result.checkpoint,8) and raw(core)==expected,"cold checkpoint reopen reproduces complete native bake")
 check(store.verify_snapshot(result.checkpoint).get("ok",false),"all private checkpoint products verify")
 check(staged.capture_storage_snapshot().stats().dirty_pages==0,"last private checkpoint makes completed data clean")
 var p:=Vector3(68,128,64)
 check(Codec.reply_ok(staged.execute(Codec.brush(p,p,1,0,false,1))),"ordinary runtime edit follows staged bake")
 var capture=staged.capture_storage_snapshot();var next:PackedByteArray=store.publish_capture(capture,result.checkpoint)
 check(next.size()==40 and staged.commit_storage_snapshot(capture,next),"runtime capture continues exact staged lineage")
 var before:=raw(core);var denied:Dictionary=core.bake_generated_earthworks_staged(packets,path+"_protected",16,64)
 check(not denied.get("ok",false) and raw(core)==before and not DirAccess.dir_exists_absolute(path+"_protected"),"nonpristine world rejects before filesystem mutation")
 var unused:=fresh();denied=unused.bake_generated_earthworks_staged(packets,path,16,64)
 check(not denied.get("ok",false) and raw(unused)==raw(fresh()) and store.verify_snapshot(next).get("ok",false),"existing storage refuses overwrite without changing its data")
 var invalid:=packets.duplicate();var bad:PackedByteArray=packets[0].duplicate();bad.encode_float(32,9.0);invalid.append(bad)
 var broken:=fresh();denied=broken.bake_generated_earthworks_staged(invalid,path+"_rejected",16,64)
 check(not denied.get("ok",false) and raw(broken)==raw(fresh()) and not denied.has("checkpoint"),"late invalid command discards every unpublished edit and exposes no reference")
 var oversized:=fresh();denied=oversized.bake_generated_earthworks_staged([Codec.graded_bed(Vector3(128,128,128),Vector3(256,128,128),16,8,16,1)],path+"_oversized",8,64)
 check(not denied.get("ok",false) and raw(oversized)==raw(fresh()),"single edit larger than residency rejects safely")
 var cancelled:=fresh();cancelled.execute(Codec.command(12));denied=cancelled.bake_generated_earthworks_staged(packets,path+"_cancelled",16,64,0)
 check(not denied.get("ok",false) and not DirAccess.dir_exists_absolute(path+"_cancelled"),"cancellation before native entry creates no staging data")
 var report:={"failures":failures,"bake":result,"pages":staged.residency_stats(),"scope":"Forty native grading commands, 16-page bound, exact ordinary-bake bytes, cold reopen, runtime lineage, existing/pristine protection, late invalid command rollback, oversized command and pre-entry cancellation. Not world-quality or FPS proof."}
 report.bake.erase("checkpoint")
 FileAccess.open("res://reports/terrain_generation_staging.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 legacy=null;staged=null;core=null;unused=null;broken=null;oversized=null;cancelled=null;capture=null;store.close();store=null
 for suffix:String in ["","_rejected","_oversized"]:clear_store(path+suffix)
 print("TERRAIN_GENERATION_STAGING failures=",failures);quit(1 if failures else 0)

func check_profiles()->void:
 var packets:Array=[]
 for profile in [0,1,2,3,4,5,6,7,12]:
  var a:=Vector3(90+profile*12,68,100)
  var packet:=Codec.graded_bed(a,a+Vector3(8,0 if profile&1 else 1.25,6),2.5,3,4,4)
  packet.resize(52 if profile else 48);packet.encode_float(44,0 if profile==12 else 2)
  if profile:packet.encode_u32(48,profile)
  packets.append(packet)
 var coefficients:=PackedFloat64Array([0,0,0.8,68, 0,0,0.8,68.8, 0,0,0.8,69.6])
 var curve:=Codec.curved_road_bed(Vector3(140,68.8,140),Vector3(146,69.6,148),3,2,4,coefficients,1)
 curve.encode_float(44,2);packets.append(curve)
 var mineral:=Codec.brush(Vector3(144,70,141),Vector3(144,68,141),1.6,4,true,8)
 mineral.encode_u32(0,41);packets.append(mineral)
 var reference:=fresh();var before:Dictionary=reference.bake_generated_earthworks(packets)
 check(before.get("ok",false),"mixed graded profiles establish ordinary terrain oracle")
 if not before.get("ok",false):print(before)
 var expected:=raw(reference)
 for optimized:bool in [false,true]:
  var path:=ProjectSettings.globalize_path("user://generation_profile_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
  var candidate:=fresh();var reply:Dictionary=candidate.bake_generated_earthworks_staged(packets,path,512,2048,-1,-1,optimized)
  check(reply.get("ok",false) and raw(candidate)==expected,"exact sloped/capped/rectangular/cut/arched/curved/mineral bytes; optimized="+str(optimized))
  check((reply.get("road_columns",0)>0)==optimized,"column optimization executes only on the selected native path")
  candidate=null;clear_store(path)
