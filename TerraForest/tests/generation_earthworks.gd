# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
const Earthworks=preload("res://addons/world_runtime/generation_earthworks.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var rows:Array=[]
 for seed_value in [0,42,1703]:
  var plan:Dictionary=Plan.build(seed_value,19)
  check(plan.get("ok",false),"plan admitted "+str(seed_value))
  if not plan.get("ok",false):continue
  var packets:=Earthworks.packets(plan.works.segments)
  var serial=ClassDB.instantiate("TerrainCore");serial.execute(Codec.command(6,[seed_value,19]))
  var began:=Time.get_ticks_usec();var accepted:=true
  for packet:PackedByteArray in packets:accepted=Codec.reply_ok(serial.execute(packet)) and accepted
  var serial_ms:=(Time.get_ticks_usec()-began)/1000.0
  var expected:PackedByteArray=serial.execute(Codec.command(4))
  var batch=ClassDB.instantiate("TerrainCore");batch.execute(Codec.command(6,[seed_value,19]))
  var result:Dictionary=batch.bake_generated_earthworks(packets)
  var actual:PackedByteArray=batch.execute(Codec.command(4))
  check(accepted and result.get("ok",false) and expected==actual,"entire native terrain archive exactly matches ordered ordinary edits "+str(seed_value))
  check(not batch.bake_generated_earthworks(packets).ok and batch.execute(Codec.command(4))==actual,"cannot rebake or mutate an edited world")
  var path:=ProjectSettings.globalize_path("user://planned_generation_stage_%d_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec(),seed_value])
  var staged=ClassDB.instantiate("TerrainCore");staged.execute(Codec.command(6,[seed_value,19]))
  var staged_result:Dictionary=staged.bake_generated_earthworks_staged(packets,path,512,32)
  check(staged_result.get("ok",false) and staged.execute(Codec.command(4))==expected and staged.residency_stats().resident_high<=512,"paged staged bake exactly matches entire actual coastal plan "+str(seed_value))
  staged_result.erase("checkpoint")
  rows.append({"seed":seed_value,"segments":packets.size(),"serial_native_ms":serial_ms,"batch_native_ms":result.get("worker_ms",-1),"staged":staged_result,"bytes":actual.size(),"sha256":preload("res://addons/world_runtime/survey_cache.gd").digest(actual).hex_encode()})
  staged=null
  for name:String in DirAccess.get_files_at(path):DirAccess.remove_absolute(path.path_join(name))
  DirAccess.remove_absolute(path)
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[42,19]))
 var before:PackedByteArray=core.execute(Codec.command(4))
 var good:=Codec.graded_bed(Vector3(1000,70,1000),Vector3(1016,70,1000),3,2,4,4)
 var invalid:=good.duplicate();invalid.encode_float(28,1000)
 check(not core.bake_generated_earthworks([good,invalid]).ok and core.execute(Codec.command(4))==before,"late validation failure discards every unpublished edit")
 check(not core.bake_generated_earthworks([Codec.command(6,[1,1])]).ok and core.execute(Codec.command(4))==before,"offline API rejects other command kinds without mutation")
 FileAccess.open("res://reports/generation_earthworks.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"cases":rows,"scope":"Exact full native terrain serialization parity, offline transaction only; no rendered generation-time claim"},"  "))
 print("GENERATION_EARTHWORKS failures=",failures);quit(1 if failures else 0)
