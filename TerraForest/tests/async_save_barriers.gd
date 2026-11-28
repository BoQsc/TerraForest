# SPDX-License-Identifier: 0BSD
extends "res://tests/save_queue_barrier.gd"
# A controlled gate around real native disk publication makes races repeatable.
class GatedArchive extends RefCounted:
 var raw:RefCounted
 var gate:=Semaphore.new()
 var lock:=Mutex.new()
 var armed:=false
 var entered:=false
 var active:=false
 var early_release:=false
 var publications:=0
 func arm():
  lock.lock();armed=true;entered=false;lock.unlock()
 func pending()->bool:
  lock.lock();var value:=entered;lock.unlock();return value
 func acquire(path:String)->bool:return raw.acquire(path)
 func release():
  lock.lock();early_release=early_release or active;lock.unlock();raw.release()
 func read(path:String)->PackedByteArray:return raw.read(path)
 func decode(bytes:PackedByteArray)->Dictionary:return raw.decode(bytes)
 func encode(sections:Dictionary)->PackedByteArray:return raw.encode(sections)
 func publish(path:String,bytes:PackedByteArray)->int:
  lock.lock();var wait:=armed;armed=false;active=true;entered=wait;lock.unlock()
  if wait:gate.wait()
  var error:int=raw.publish(path,bytes)
  lock.lock();active=false;publications+=1;lock.unlock();return error
func evidence_path(name:String)->String:
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--check-evidence-dir="):return arg.trim_prefix("--check-evidence-dir=").path_join(name+".trw")
 return "user://worlds/async_barrier_%d_%s.trw"%[OS.get_process_id(),name]
func shutdown_case(mode:String)->void:
 inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(101,999);inventory.grant(101,1,0)
 var backend=Backend.new();backend.world_generator=3;backend.disk_cache.enabled=false
 var codec:=GatedArchive.new();codec.raw=ClassDB.instantiate("NativeWorldArchive")
 backend.snapshot_codec=codec;backend.snapshot_capture=capture;backend.snapshot_validators={"player_loadout":inventory}
 var path:=evidence_path("shutdown_"+mode);backend.save_path=path
 check(backend.start(false)==OK,"shutdown "+mode+" worker starts")
 check(backend.submit({"kind":"save"}),"shutdown "+mode+" initial save admitted")
 var saved:=false;var deadline:=Time.get_ticks_msec()+10000
 while not saved and Time.get_ticks_msec()<deadline:
  for r:Dictionary in backend.poll():saved=saved or (r.get("operation")=="save" and r.get("success",false))
  await process_frame
 check(saved,"shutdown "+mode+" initial root durable")
 var before:PackedByteArray=codec.raw.read(ProjectSettings.globalize_path(path))
 if mode=="component":inventory.grant(101,1,inventory.snapshot().revision)
 if mode=="terrain":check(backend.submit(edit_job(),true),"shutdown preserves accepted terrain edit")
 if mode=="invalid":backend.snapshot_capture=func():return {"epoch":0,"sections":{"player_loadout":PackedByteArray([0])}}
 backend.stop()
 var after:PackedByteArray=codec.raw.read(ProjectSettings.globalize_path(path));var decoded:Dictionary=codec.raw.decode(after)
 check(decoded.ok,"shutdown "+mode+" root validates")
 check(codec.publications==(1 if mode in ["unchanged","invalid"] else 2),"shutdown "+mode+" publishes exactly when dirty and valid")
 if mode in ["unchanged","invalid"]:check(before==after,"shutdown "+mode+" preserves exact root")
 check(backend._last_save_success==(mode!="invalid"),"shutdown "+mode+" reports durable status")
 if mode=="component":check(decoded.sections.player_loadout==inventory.capture_storage_snapshot(),"shutdown captures component change without terrain edit")
 if mode=="terrain":
  var core=ClassDB.instantiate("TerrainCore");var packet:=Codec.command(5)
  packet.append_array(preload("res://tests/terrain_storage_support.gd").expand(path,decoded.sections.terrain))
  check(Codec.reply_ok(core.execute(packet)) and core.execute(Codec.command(0)).decode_u32(12)>0,"shutdown saved accepted terrain revision")
 preload("res://tests/terrain_storage_support.gd").cleanup(path)
 for suffix in ["",".bak",".lock"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
func run()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
 GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 for mode:String in ["unchanged","component","terrain","invalid"]:await shutdown_case(mode)
 inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(101,999);inventory.grant(101,1,0)
 var backend=Backend.new();backend.native=ClassDB.instantiate("TerrainCore");backend.world_generator=3
 var codec:=GatedArchive.new();codec.raw=ClassDB.instantiate("NativeWorldArchive")
 backend.snapshot_codec=codec;backend.snapshot_capture=capture;backend.snapshot_validators={"player_loadout":inventory};backend.disk_cache.enabled=false
 var path:=evidence_path("async_barrier")
 DirAccess.make_dir_recursive_absolute("user://worlds");backend.save_path=path
 check(backend.start(false)==OK,"worker starts")
 var deadline:=Time.get_ticks_msec()+10000;var started:=false
 while not started and Time.get_ticks_msec()<deadline:
  for r:Dictionary in backend.poll():started=started or r.get("kind")=="startup"
  await process_frame
 check(started,"world startup completes")
 codec.arm();check(backend.submit({"kind":"save"}),"first save admitted")
 deadline=Time.get_ticks_msec()+10000
 while not codec.pending() and Time.get_ticks_msec()<deadline:await process_frame
 check(codec.pending() and backend.publication_pending(),"publication held at controlled gate")
 check(not backend.submit({"kind":"save"}),"second save gets bounded backpressure")
 inventory.grant(101,1,inventory.snapshot().revision)
 check(backend.submit(edit_job(),true) and backend.submit({"kind":"height","point":Vector3(800,8,1310),"token":90}),"edit and query admitted during disk publication")
 var edited:=false;var queried:=false;deadline=Time.get_ticks_msec()+10000
 while not (edited and queried) and Time.get_ticks_msec()<deadline:
  for r:Dictionary in backend.poll():
   edited=edited or r.get("kind")=="edit_done";queried=queried or r.get("kind")=="height"
  await process_frame
 check(edited and queried and backend.publication_pending(),"native edit and query finish before publication is released")
 codec.gate.post();var saved:=false;deadline=Time.get_ticks_msec()+10000
 while not saved and Time.get_ticks_msec()<deadline:
  for r:Dictionary in backend.poll():saved=saved or (r.get("operation")=="save" and r.get("success",false))
  await process_frame
 check(saved and not backend.cache_valid,"old save completion cannot relabel edited terrain cache")
 codec.arm();check(backend.submit({"kind":"save"}),"next save admitted after completion")
 deadline=Time.get_ticks_msec()+10000
 while not codec.pending() and Time.get_ticks_msec()<deadline:await process_frame
 check(backend.submit({"kind":"load","epoch":1},true),"reload queued behind pending publication")
 for frame in 5:await process_frame
 var premature:=false
 for r:Dictionary in backend.poll():premature=premature or r.get("kind")=="reload"
 check(not premature,"reload cannot cross publication barrier")
 codec.gate.post();var reloaded:=false;deadline=Time.get_ticks_msec()+10000
 while not reloaded and Time.get_ticks_msec()<deadline:
  for r:Dictionary in backend.poll():reloaded=reloaded or r.get("kind")=="reload"
  await process_frame
 check(reloaded,"reload resumes after durable save")
 codec.arm();check(backend.submit({"kind":"save"}),"save before shutdown admitted")
 deadline=Time.get_ticks_msec()+10000
 while not codec.pending() and Time.get_ticks_msec()<deadline:await process_frame
 var release_thread:=Thread.new()
 release_thread.start(func():OS.delay_msec(50);codec.gate.post())
 backend.stop();release_thread.wait_to_finish()
 check(not codec.early_release,"shutdown joins publisher before releasing archive lease")
 check(codec.raw.decode(codec.raw.read(ProjectSettings.globalize_path(path))).ok,"shutdown leaves verified canonical archive")
 preload("res://tests/terrain_storage_support.gd").cleanup(path)
 for suffix in ["",".bak",".lock"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 print("ASYNC_SAVE_BARRIERS checks=",checks," failures=",failures);quit(1 if failures else 0)
