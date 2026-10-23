# SPDX-License-Identifier: 0BSD
extends "res://tests/terrain_generation_staging.gd"
func files(path:String)->Dictionary:
 var result:Dictionary={}
 for name:String in DirAccess.get_files_at(path):result[name]=FileAccess.get_sha256(path.path_join(name))
 return result
func run()->void:
 var path:=ProjectSettings.globalize_path("user://bake_failure_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 var packets:Array=[]
 for i in 80:
  var p:=Vector3(64+(i%20)*32,128,64+(i/20)*32);packets.append(Codec.graded_bed(p,p+Vector3(4,0,0),1,1,0,1))
 var core:=fresh();var rejected:Dictionary=core.bake_generated_earthworks_staged(packets,path,256,16,0,3)
 var state:Dictionary=core.generation_bake_progress()
 check(not rejected.get("ok",false) and not rejected.has("checkpoint") and rejected.completed==48 and rejected.checkpoints==3,"injected product publication interruption occurs after earlier private checkpoints")
 check(state.state==3 and state.completed==48 and raw(core)==raw(fresh()),"failed progress is explicit and every unpublished edit is discarded")
 var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore");check(store.open_store(path,false),"failed job releases its write lease")
 var verified:=0;var highest_revision:=0
 for name:String in DirAccess.get_files_at(path):
  if not name.ends_with(".tindex"):continue
  var reference:PackedByteArray="TFTR".to_utf8_buffer();reference.resize(40);reference.encode_u32(4,1)
  var digest:PackedByteArray=name.trim_suffix(".tindex").hex_decode()
  for i in 32:reference[8+i]=digest[i]
  var info:Dictionary=store.verify_snapshot(reference)
  check(info.get("ok",false),"earlier private checkpoint remains fully verifiable")
  highest_revision=maxi(highest_revision,int(info.get("revision",0)));verified+=1
 check(verified==3 and highest_revision==32,"failed publication never selects the interrupted third batch")
 var before:=files(path);var retry:=fresh();var result:Dictionary=retry.bake_generated_earthworks_staged(packets,path+"_retry",256,16)
 var ordinary:=fresh();ordinary.bake_generated_earthworks(packets)
 check(result.get("ok",false) and raw(retry)==raw(ordinary) and files(path)==before,"regeneration in a new staging owner restores exact intended data without modifying failed products")
 result.erase("checkpoint")
 FileAccess.open("res://reports/generation_bake_failure.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"rejected":rejected,"progress":state,"verified_checkpoints":verified,"regenerated":result,"scope":"Deterministic interruption in the existing native product publisher before an intermediate index is published; retained-prefix integrity, full discard and exact fresh-owner regeneration. Not physical power-loss evidence."},"  "))
 core=null;retry=null;ordinary=null;store.close();store=null;clear_store(path);clear_store(path+"_retry")
 print("GENERATION_BAKE_FAILURE failures=",failures);quit(1 if failures else 0)
