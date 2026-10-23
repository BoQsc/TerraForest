# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
const Support=preload("res://tests/terrain_storage_support.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var backend:=Backend.new();backend.native=ClassDB.instantiate("TerrainCore")
 backend.native.execute(Codec.command(6,[1703,19]));backend.disk_cache.enabled=false
 var edit_times:Array=[]
 for count in range(2048):
  var location:=count*127%2304;var point:=Vector3(88+(location%48)*38,0,88+(location/48)*38)
  point.y=backend.native.execute(Codec.point_command(point)).decode_float(12)-0.6
  var began:=Time.get_ticks_usec();var reply:PackedByteArray=backend.native.execute(Codec.brush(point,point,2.5,0,false,1));edit_times.append((Time.get_ticks_usec()-began)/1000.0)
  if not Codec.reply_ok(reply):check(false,"distributed excavation %d"%count);quit(1);return
 var began:=Time.get_ticks_usec();var original:PackedByteArray=backend.native.execute(Codec.command(4,[3])).slice(12);var capture_ms:=(Time.get_ticks_usec()-began)/1000.0
 var folder:=ProjectSettings.globalize_path("user://terrain_history_store_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
 DirAccess.make_dir_recursive_absolute(folder);var path:=folder.path_join("world.trw")
 var archive=ClassDB.instantiate("NativeWorldArchive");check(archive.acquire(path),"history fixture owns compound archive lease")
 backend.save_path=path;backend.snapshot_codec=archive
 var first:Dictionary=backend._publish_frozen({"terrain":original},original,path,archive)
 check(first.success,"actual publisher saves 2048 distributed excavations")
 var canonical:PackedByteArray=archive.read(path);var selected:Dictionary=archive.decode(canonical)
 check(selected.ok and canonical.size()<1024 and selected.sections.terrain.size()==40,"large edit history has bounded small compound root")
 check(Support.expand(path,selected.sections.terrain)==original,"all distant edits reconstruct exactly from selected regions")
 var serial=ClassDB.instantiate("NativeTerrainRegionStore")
 check(not serial.configure_worker_limit(0) and serial.configure_worker_limit(1) and serial.open_store(folder.path_join("serial.trw.terrain"),true),"serial storage comparison uses an explicit bounded worker configuration")
 began=Time.get_ticks_usec();var serial_reference:PackedByteArray=serial.publish_snapshot(original);var serial_publish_ms:=(Time.get_ticks_usec()-began)/1000.0
 check(serial_reference==selected.sections.terrain and serial.stats().workers==1,"parallel and serial encoding produce identical checkpoint bytes")
 check(first.stages.terrain_regions.workers<=mini(4,maxi(1,OS.get_processor_count()/2)) and not serial.configure_worker_limit(4),"worker count respects hardware cap and cannot change during publication ownership")
 serial.close();Support.cleanup(folder.path_join("serial.trw"))
 var repeated:Dictionary=backend._publish_frozen({"terrain":original},original,path,archive)
 check(repeated.success and repeated.stages.terrain_regions.written_bytes==0,"unchanged history save publishes no terrain pack or index bytes")
 var point:=Vector3(999,0,999);point.y=backend.native.execute(Codec.point_command(point)).decode_float(12)-0.6
 check(Codec.reply_ok(backend.native.execute(Codec.brush(point,point,2.5,0,false,1))),"local excavation after large history remains admissible")
 began=Time.get_ticks_usec();var later:PackedByteArray=backend.native.execute(Codec.command(4,[3])).slice(12);var later_capture_ms:=(Time.get_ticks_usec()-began)/1000.0
 var changed:Dictionary=backend._publish_frozen({"terrain":later},later,path,archive)
 check(changed.success and changed.stages.terrain_regions.written_files<=2 and changed.stages.terrain_regions.written_bytes<original.size()/100,"one later excavation publishes only a small changed pack and checkpoint index")
 began=Time.get_ticks_usec();var loaded:String=backend._load();var reopen_ms:=(Time.get_ticks_usec()-began)/1000.0
 check(loaded=="World loaded" and backend.native.execute(Codec.command(4,[3])).slice(12)==later,"production reopen preserves every old and new edited page")
 var backup:Dictionary=archive.decode(archive.read(path+".bak"))
 check(backup.ok and Support.expand(path,backup.sections.terrain)==original,"prior checkpoint remains available through exact canonical backup")
 var total_bytes:=0
 for file:String in DirAccess.get_files_at(path+".terrain"):total_bytes+=FileAccess.get_file_as_bytes(path+".terrain/"+file).size()
 edit_times.sort()
 var report:={"failures":failures,"excavations":2048,"pages":original.decode_u32(12),"raw_bytes":original.size(),"capture_ms":capture_ms,"serial_first_publish_ms":serial_publish_ms,"later_capture_ms":later_capture_ms,"native_edit_median_ms":edit_times[1024],"native_edit_p95_ms":edit_times[int(2048*.95)],"first_save":first,"unchanged_save":repeated,"local_edit_save":changed,"reopen_ms":reopen_ms,"canonical_bytes":canonical.size(),"sidecar_bytes_including_backup":total_bytes,"scope":"Real compound publication and loader with native distributed edit history. No rendered terrain, scene streaming, full game addon population, thermal or endurance qualification. Resident page cap and full capture remain unchanged."}
 FileAccess.open("res://reports/terrain_history_storage.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 archive.release();Support.cleanup(path)
 for file:String in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(file))
 DirAccess.remove_absolute(folder)
 print("TERRAIN_HISTORY_STORAGE failures=",failures);quit(1 if failures else 0)
