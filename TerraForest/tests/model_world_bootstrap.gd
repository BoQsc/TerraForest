# SPDX-License-Identifier: 0BSD
extends SceneTree
const WORLD=preload("res://addons/structures/structures_world.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func pose(x: float) -> PackedFloat32Array:return PackedFloat32Array([1,0,0,x,0,1,0,1,0,0,1,1])
func run() -> void:
    GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
    GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
    Engine.max_fps=1000;DirAccess.make_dir_recursive_absolute("res://reports")
    var assets:=PackedStringArray(["test/bootstrap_a","test/bootstrap_b"])
    var source: Node3D=WORLD.new();root.add_child(source)
    for i in 2:
        var batch: Node3D=source.register_model(assets[i],BoxMesh.new())
        var ids:=PackedInt64Array();var transforms:=PackedFloat32Array()
        for n in 6000:ids.append(n+1);transforms.append_array(pose((n%6)*32+1))
        batch.upsert_instances(ids,transforms)
    source.blocks.set_cells(PackedInt32Array([0,0,0,1,128,0,0,2]))
    var original: PackedByteArray=source.capture_snapshot()
    var packet: PackedByteArray=source.model(assets[0]).capture_region(Vector3i.ZERO)
    var raw: RefCounted=ClassDB.instantiate("NativeWorldArchive")
    var codec: RefCounted=source.snapshot_validator()
    var invalid: RefCounted=ClassDB.instantiate("NativeRegionWorldArchive")
    check(not invalid.configure(raw,codec,false,true),"model metadata option requires block metadata startup")
    var archive: RefCounted=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,codec,true,true)
    var path:=ProjectSettings.globalize_path("res://reports/model_bootstrap_%d_%d.trw"%[OS.get_process_id(),Time.get_ticks_usec()])
    check(archive.acquire(path) and archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":original}))==OK,"fixture saves compact checkpoint-root world")
    var bytes: PackedByteArray=archive.read(path)
    var cold: Dictionary=archive.decode(bytes)
    check(cold.get("ok",false) and cold.model_bootstrap.assets==2 and cold.model_bootstrap.regions_read==12 and cold.model_bootstrap.cache_hits==0,"cold world decode builds model manifests from individual regions")
    var warm: Dictionary=archive.decode(bytes)
    check(warm.ok and warm.model_bootstrap.regions_read==0 and warm.model_bootstrap.cache_hits==2,"cached world decode reads no model region payloads")
    var startup: PackedByteArray=warm.sections.structures
    check(startup.size()<original.size()/4 and codec.validate_bootstrap(startup) and archive.validate_snapshot(startup),"startup envelope is compact and accepted by opted-in load validator")
    check(not codec.validate_snapshot(startup) and not codec.validate_storage_snapshot(startup) and not codec.decode_storage(startup).ok,"startup metadata cannot masquerade as resident or partial save state")
    var inline_root: PackedByteArray=raw.encode({"terrain":PackedByteArray([1]),"structures":original})
    check(archive.decode(inline_root).sections.structures==original,"legacy resident world remains readable with model metadata option enabled")
    var startup_decoded: Dictionary=codec.decode_bootstrap(startup)
    var inline_reference: PackedByteArray=codec.encode_reference(startup_decoded.checkpoint,codec.decode(original).models)
    var inline_result: Dictionary=archive.decode(raw.encode({"terrain":PackedByteArray([1]),"structures":inline_reference}))
    check(inline_result.ok and codec.decode_storage(inline_result.sections.structures).models==codec.decode(original).models,"legacy checkpoint root with inline models falls back to compatible resident model decode")
    var swapped: Dictionary=startup_decoded.models.duplicate();swapped[assets[1]]=swapped[assets[0]]
    check(codec.encode_bootstrap(startup_decoded.checkpoint,startup_decoded.unavailable_keys,startup_decoded.unavailable_checksums,swapped).is_empty(),"bootstrap encoder rejects metadata belonging to another registered asset")
    var before: PackedByteArray=archive.read(path)
    check(archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":startup}))==ERR_INVALID_DATA and archive.read(path)==before,"publishing raw startup envelope rejects before changing canonical root")
    var live: Node3D=WORLD.new();root.add_child(live)
    var mesh_b:=BoxMesh.new()
    var a: Node3D=live.register_model(assets[0],BoxMesh.new());var b: Node3D=live.register_model(assets[1],mesh_b)
    var added: Node3D=live.register_model("test/new_asset",BoxMesh.new())
    a.upsert_instances(PackedInt64Array([99999]),pose(1));b.upsert_instances(PackedInt64Array([99999]),pose(1));added.upsert_instances(PackedInt64Array([1]),pose(1))
    live.blocks.set_cells(PackedInt32Array([0,0,0,3]))
    var old: PackedByteArray=live.capture_snapshot()
    var bad:=startup.duplicate();bad[20]^=1
    check(not live.restore_storage_snapshot(bad) and live.capture_snapshot()==old,"corrupt startup cannot partially replace scene")
    mesh_b.size=Vector3(INF,1,1)
    check(not live.restore_storage_snapshot(startup) and live.capture_snapshot()==old,"late collection prototype failure leaves blocks and every earlier collection intact")
    mesh_b.size=Vector3.ONE
    var observations: Dictionary={"calls":0,"complete":true,"reentrant":true}
    var observer:=func():
        observations.calls+=1
        observations.complete=observations.complete and a.region_stats().resident_instances==0 and a.region_stats().reserved_ids==6000 and b.region_stats().reserved_ids==6000 and live.blocks.region_stats().resident_chunks==0 and added.get_ids().is_empty() and live._model_checkpoints.size()==2
        observations.reentrant=observations.reentrant and not live.restore_storage_snapshot(startup)
    live.blocks.changed.connect(observer);a.changed.connect(observer);b.changed.connect(observer)
    check(live.restore_storage_snapshot(startup),"scene coordinator installs block/model metadata in one validated native transaction")
    live.blocks.changed.disconnect(observer);a.changed.disconnect(observer);b.changed.disconnect(observer);observer=Callable()
    check(observations.calls==3 and observations.complete and observations.reentrant,"observers see all collections installed and reject recursive bootstrap")
    check(a.region_stats().resident_instances==0 and b.region_stats().resident_instances==0 and a.region_stats().unloaded_regions==6 and b.region_stats().unloaded_regions==6,"12000 model transforms remain unloaded after world startup")
    check(added.get_ids().is_empty() and live._model_checkpoints.size()==2,"newly registered asset absent from older save restores empty")
    var storage: PackedByteArray=live.capture_storage_snapshot()
    check(codec.validate_storage_snapshot(storage)==false and live.snapshot_validator().validate_storage_snapshot(storage),"captured partial save is validated against full current asset schema")
    # Archive with old schema correctly rejects newly introduced asset. Use a
    # matching schema adapter for subsequent save/load interoperability.
    archive.release()
    archive=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,live.snapshot_validator(),true,true);archive.acquire(path)
    check(archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":storage}))==OK,"metadata-only scene saves through ordinary partial-model storage envelope")
    var decoded: Dictionary=archive.decode(archive.read(path))
    check(decoded.ok and live.restore_storage_snapshot(decoded.sections.structures),"saved partial scene reloads into metadata without restoring all transforms")
    var history: RefCounted=ClassDB.instantiate("NativeStaticHistory");history.configure([a,b,added],1048576,256)
    var scheduler: RefCounted=ClassDB.instantiate("NativeModelTransferScheduler");scheduler.configure(archive,history,4,32000000)
    check(archive.start_region_reads(4,32000000) and scheduler.register_collection(assets[0],a,live._model_checkpoints[assets[0]]),"metadata-started scene connects to retained shared scheduler")
    check(not live.restore_storage_snapshot(decoded.sections.structures) and a.region_stats().reserved_ids==6000,"active scheduler ownership blocks world replacement before mutation")
    var ticket: int=scheduler.request(assets[0],Vector3i.ZERO,packet.slice(packet.size()-32),false,0,0)
    var results: Array=[];var end:=Time.get_ticks_msec()+5000
    while results.is_empty() and Time.get_ticks_msec()<end:
        scheduler.tick(256,65536,500,4);results=scheduler.poll(4);await process_frame
    check(ticket>0 and results.size()==1 and results[0].result=="complete" and a.capture_region(Vector3i.ZERO)==packet,"one requested nearby region loads exact saved transforms through scheduler")
    check(a.region_stats().resident_instances==1000 and a.region_stats().reserved_ids==5000 and b.region_stats().resident_instances==0,"selective admission leaves other regions and assets unloaded")
    scheduler.stop();scheduler=null
    storage=live.capture_storage_snapshot()
    check(archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":storage}))==OK,"mixed resident/unavailable model scene remains saveable")
    archive.release()
    var legacy: RefCounted=ClassDB.instantiate("NativeRegionWorldArchive");legacy.configure(raw,live.snapshot_validator(),true);legacy.acquire(path)
    var full: Dictionary=legacy.decode(legacy.read(path))
    check(full.ok and live.restore_storage_snapshot(full.sections.structures) and a.region_stats().resident_instances==6000 and b.region_stats().resident_instances==6000,"default block-only metadata loader remains compatible and reconstructs all model transforms")
    legacy.release();live.free();source.free()
    var file:=FileAccess.open("res://reports/model_world_bootstrap.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"full_bundle_bytes":original.size(),"bootstrap_bytes":startup.size(),"cold":cold.model_bootstrap,"warm":warm.model_bootstrap,"scope":"Opt-in archive/scene model metadata bootstrap, transactional validation, selective scheduler admission and partial save compatibility. Not default game paging or frame/thermal qualification."},"  "));file.close()
    print("MODEL_WORLD_BOOTSTRAP checks=",checks," failures=",failures)
    quit(1 if failures else 0)
