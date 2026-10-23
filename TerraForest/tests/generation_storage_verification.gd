# SPDX-License-Identifier: 0BSD
extends SceneTree
const Verifier=preload("res://addons/world_runtime/verify_generated_world.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
 var failures:=0
 for path:String in ["res://addons/world_runtime/generate_world.gd","res://addons/world_runtime/prepare_terrain_world.gd","res://addons/world_runtime/generation_job.gd"]:
  var script=load(path)
  if script==null or not script.can_instantiate():failures+=1;print("FAIL generation script loads ",path)
 var source:="regional_storage_1703_20261023"
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--review-world="):source=arg.trim_prefix("--review-world=")
 var path:=ProjectSettings.globalize_path("user://worlds/"+source+".trw")
 var result:Dictionary=Verifier.verify(path,1703,19)
 if not result.get("ok",false):failures+=1
 print("GENERATION_NATIVE_VERIFICATION ",JSON.stringify(result))
 var wrong:Dictionary=Verifier.verify(path,42,19)
 if wrong.get("ok",false):failures+=1;print("FAIL mismatched generation identity accepted")
 # Corrupt inner native sections while keeping a valid outer root checksum.
 # Only the uniquely owned, hidden staging clone is modified.
 var raw:RefCounted=ClassDB.instantiate("NativeWorldArchive")
 var source_digest:=FileAccess.get_sha256(path)
 var destination:="combined_stage_"+Crypto.new().generate_random_bytes(16).hex_encode()
 var cloned:Dictionary=raw.clone_world(ProjectSettings.globalize_path("user://worlds"),source,destination)
 if not cloned.get("ok",false):failures+=1;print("FAIL verification fixture clone")
 else:
  var target:=ProjectSettings.globalize_path("user://worlds/"+destination+".trw")
  var original:PackedByteArray=raw.read(target)
  var sections:Dictionary=raw.decode(original).sections
  for name:String in ["terrain","structures","volumetric_water"]:
   var damaged:Dictionary=sections.duplicate()
   var bytes:PackedByteArray=sections[name].duplicate();bytes[0]^=1;damaged[name]=bytes
   var invalid:PackedByteArray=raw.encode(damaged)
   var file:=FileAccess.open(target,FileAccess.WRITE);file.store_buffer(invalid);file.close()
   var rejected:Dictionary=Verifier.verify(target,1703,19)
   if rejected.get("ok",false):failures+=1;print("FAIL damaged inner section accepted ",name)
   var lease:RefCounted=ClassDB.instantiate("NativeWorldArchive")
   if not lease.acquire(target):failures+=1;print("FAIL failed verification retained lease ",name)
   lease.release()
  var file:=FileAccess.open(target,FileAccess.WRITE);file.store_buffer(original);file.close()
  if not Verifier.verify(target,1703,19).get("ok",false):failures+=1;print("FAIL restored fixture cannot verify")
  if FileAccess.get_sha256(path)!=source_digest:failures+=1;print("FAIL source changed during verification")
 FileAccess.open("res://reports/generation_storage_verification.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("GENERATION_STORAGE_VERIFICATION failures=",failures);quit(1 if failures else 0)
