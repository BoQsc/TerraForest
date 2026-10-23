# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var core:RefCounted=ClassDB.instantiate("TerrainCore")
 core.execute(Codec.command(6,[1703,19]))
 var prepared:Dictionary=preload("res://addons/world_runtime/world_generation_plan.gd").build(1703,19,true,true)
 check(prepared.get("ok",false),"existing production plan builds")
 var packets:Array=preload("res://addons/world_runtime/generation_earthworks.gd").packets(prepared.works.segments)
 check(core.bake_generated_earthworks(packets).get("ok",false),"production earthworks use the existing native field")
 var field_before:PackedByteArray=core.execute(Codec.command(4))
 var definitions:Dictionary=preload("res://addons/volumetric_terrain/generated_lakes.gd").describe(core,19)
 var catalog:RefCounted=ClassDB.instantiate("NativeLakeCatalog")
 var bytes:PackedByteArray=catalog.encode(definitions.records,5)
 var revision:int=core.execute(Codec.command(0)).decode_u32(12)
 var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
 var baker:RefCounted=ClassDB.instantiate("NativeGeneratedLakeBake")
 var baked:Dictionary=baker.run(core,bytes,revision,epoch)
 check(baked.get("ok",false) and not baked.get("snapshot",PackedByteArray()).is_empty(),"detached native job produces a complete snapshot")
 if not baked.get("ok",false):print("BAKE_FAILED ",baked);quit(1);return
 check(core.execute(Codec.command(4))==field_before,"authoring is read-only to terrain")
 var source:="regional_storage_1703_20261023"
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--review-world="):source=arg.trim_prefix("--review-world=")
 var path:=ProjectSettings.globalize_path("user://worlds/"+source+".trw")
 var before:=FileAccess.get_sha256(path)
 var archive:RefCounted=ClassDB.instantiate("NativeWorldArchive")
 var root_data:Dictionary=archive.decode(archive.read(path))
 var store:RefCounted=ClassDB.instantiate("NativeWaterRegionStore")
 check(root_data.get("ok",false) and store.open_store(path+".water"),"existing generated water checkpoint opens read-only")
 var expected:PackedByteArray=store.expand_water_snapshot(root_data.sections.volumetric_water);store.close()
 check(expected==baked.snapshot,"new offline job exactly matches the prior complete generated water bytes")
 check(FileAccess.get_sha256(path)==before,"baseline canonical root is unchanged")
 var installed:RefCounted=ClassDB.instantiate("NativeRegionalWater")
 check(installed.restore_snapshot(baked.snapshot) and installed.snapshot_catalog(baked.snapshot)==bytes,"ordinary runtime restores exact quantities, contacts and catalog cursor")
 check(not baker.run(core,bytes,revision,epoch).get("ok",false),"one-shot job rejects accidental reuse")
 var stale:RefCounted=ClassDB.instantiate("NativeGeneratedLakeBake")
 check(stale.run(core,bytes,revision+1,epoch).get("status")==-4,"stale terrain revision rejects before any output")
 var invalid:RefCounted=ClassDB.instantiate("NativeGeneratedLakeBake")
 check(not invalid.run(core,PackedByteArray(),revision,epoch).get("ok",false),"malformed definitions reject")
 var expired:RefCounted=ClassDB.instantiate("NativeGeneratedLakeBake")
 var timeout:Dictionary=expired.run(core,bytes,revision,epoch,1)
 check(timeout.get("status")==-3 and not timeout.has("snapshot"),"time-budget rejection exposes no partial snapshot")
 var cancelled:RefCounted=ClassDB.instantiate("NativeGeneratedLakeBake")
 var worker:=Thread.new();check(worker.start(cancelled.run.bind(core,bytes,revision,epoch))==OK,"offline cancellation worker starts")
 var deadline:=Time.get_ticks_msec()+1000
 while cancelled.progress().status==0 and worker.is_alive() and Time.get_ticks_msec()<deadline:await process_frame
 var cancel_begin:=Time.get_ticks_usec();cancelled.cancel()
 var stopped:Dictionary=worker.wait_to_finish()
 var cancel_us:=Time.get_ticks_usec()-cancel_begin
 check(stopped.get("status")==-4 and not stopped.has("snapshot") and cancel_us<1000000,"in-flight cancellation promptly discards the detached output")
 check(core.execute(Codec.command(4))==field_before,"failure, timeout and cancellation preserve the authoritative field")
 var profile:Dictionary=baked.duplicate();profile.erase("snapshot")
 profile["snapshot_sha256"]=preload("res://addons/world_runtime/survey_cache.gd").digest(baked.snapshot).hex_encode();profile["failures"]=failures;profile["cancel_microseconds"]=cancel_us
 FileAccess.open("res://reports/offline_generated_lakes.json",FileAccess.WRITE).store_string(JSON.stringify(profile,"  "))
 print("OFFLINE_GENERATED_LAKES_CHECK failures=",failures," ",JSON.stringify(profile));quit(1 if failures else 0)
