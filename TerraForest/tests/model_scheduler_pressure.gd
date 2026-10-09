# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var scheduler: RefCounted
var timings: Array[int]=[]
var phases: Dictionary={}
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func transfer(batches: Array[Node3D],packets: Array[PackedByteArray],retire: bool) -> void:
    for i in 2:check(scheduler.request("pressure/%d"%i,Vector3i.ZERO,packets[i].slice(packets[i].size()-32),retire,0,0)>0,"dense job accepted")
    var start:=Time.get_ticks_msec();var end:=start+15000;var results: Array=[];var records:=0;var bytes:=0;var valid:=true;var ticks:=0
    while results.size()<2 and Time.get_ticks_msec()<end:
        var state: Dictionary=scheduler.tick(256,65536,500,8)
        timings.append(state.step_usec);ticks+=1;records+=state.step_records;bytes+=state.step_hash_bytes
        valid=valid and state.step_records<=256 and state.step_hash_bytes<=65536 and state.step_operations<=8 and state.reserved_bytes<=2*5600232
        results.append_array(scheduler.poll(8));await process_frame
    for result in results:valid=valid and result.result=="complete"
    check(valid and results.size()==2,"two dense collections finish with one aggregate budget")
    for batch in batches:check(batch.region_stats().resident_instances==(0 if retire else 100000),"dense logical residency agrees with operation")
    phases["retire" if retire else "admit"]={"ticks":ticks,"elapsed_ms":Time.get_ticks_msec()-start,"records":records,"hash_bytes":bytes}
func run() -> void:
    GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
    GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
    Engine.max_fps=1000;DirAccess.make_dir_recursive_absolute("res://reports")
    var batches: Array[Node3D]=[];var packets: Array[PackedByteArray]=[];var models: Dictionary={}
    var assets:=PackedStringArray(["pressure/0","pressure/1"])
    for i in 2:
        var batch: Node3D=ClassDB.instantiate("NativeStaticBatch");batch.configure_collision_only();batch.configure_asset(assets[i],BoxMesh.new())
        var ids:=PackedInt64Array();var values:=PackedFloat32Array();ids.resize(100000);values.resize(1200000)
        for n in 100000:
            ids[n]=n+1;values[n*12]=1;values[n*12+3]=(n%100)*0.1;values[n*12+5]=1;values[n*12+7]=1;values[n*12+10]=1;values[n*12+11]=1
        check(batch.upsert_instances(ids,values),"100000-record collection prepared outside measured ticks")
        batches.append(batch);packets.append(batch.capture_region(Vector3i.ZERO));models[assets[i]]=batch.capture_snapshot()
    var codec: RefCounted=ClassDB.instantiate("NativeStructuresSnapshot");codec.configure_assets(assets)
    var raw: RefCounted=ClassDB.instantiate("NativeWorldArchive");var archive: RefCounted=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,codec,true)
    var world: Node3D=ClassDB.instantiate("NativeBlockWorld")
    var path:=ProjectSettings.globalize_path("res://reports/model_pressure_%d_%d.trw"%[OS.get_process_id(),Time.get_ticks_usec()])
    check(archive.acquire(path) and archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":codec.encode(world.capture_snapshot(),models)}))==OK and archive.start_region_reads(2,2*(5600232+96)),"dense data persisted and shared reader started outside measured ticks")
    var root: Dictionary=codec.decode_reference(raw.decode(archive.read(path)).sections.structures)
    var history: RefCounted=ClassDB.instantiate("NativeStaticHistory");history.configure(batches,1048576,256)
    scheduler=ClassDB.instantiate("NativeModelTransferScheduler");scheduler.configure(archive,history,2,2*5600232)
    for i in 2:
        var reference: PackedByteArray=root.models[assets[i]];var size:=reference.decode_u32(8)
        check(scheduler.register_collection(assets[i],batches[i],reference.slice(12+size,44+size)),"dense collection registered")
    await transfer(batches,packets,true);await transfer(batches,packets,false)
    for i in 2:check(batches[i].capture_region(Vector3i.ZERO)==packets[i],"100000-record region restored byte-exactly")
    scheduler.stop();scheduler=null
    for batch in batches:batch.free()
    world.free();archive.release()
    var samples:=timings.duplicate();samples.sort();var maximum: int=samples.back() if not samples.is_empty() else 0
    var report:={"checks":checks,"failures":failures,"records_per_collection":100000,"collections":2,"ticks":samples.size(),"max_usec":maximum,"p95_usec":samples[int(samples.size()*0.95)],"p99_usec":samples[int(samples.size()*0.99)],"timing_limit_usec":2000,"timing_passed":maximum<=2000,"phases":phases,"scope":"Headless shared transfer stress; fixture creation/save excluded, no renderer, frame pacing, power or thermal qualification."}
    var file:=FileAccess.open("res://reports/model_scheduler_pressure.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
    print(JSON.stringify(report));quit(1 if failures else (0 if maximum<=2000 else 2))
