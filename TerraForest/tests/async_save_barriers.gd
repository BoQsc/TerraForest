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
  lock.lock();active=false;lock.unlock();return error
func run()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
 GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(101,999);inventory.grant(101,1,0)
 var backend=Backend.new();backend.native=ClassDB.instantiate("TerrainCore");backend.world_generator=3
 var codec:=GatedArchive.new();codec.raw=ClassDB.instantiate("NativeWorldArchive")
 backend.snapshot_codec=codec;backend.snapshot_capture=capture;backend.snapshot_validators={"player_loadout":inventory};backend.disk_cache.enabled=false
 var path:="user://worlds/async_barrier_%d_%d.trw"%[OS.get_process_id(),Time.get_ticks_usec()]
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
 for suffix in ["",".bak",".lock"]:DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
 print("ASYNC_SAVE_BARRIERS checks=",checks," failures=",failures);quit(1 if failures else 0)
