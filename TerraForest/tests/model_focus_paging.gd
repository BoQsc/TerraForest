# SPDX-License-Identifier: 0BSD
extends SceneTree
const WORLD=preload("res://addons/structures/structures_world.gd")
var checks:=0
var failures:=0
var live: Node3D
var history: RefCounted
var archive: RefCounted
var assets:=PackedStringArray(["test/focus_a","test/focus_b"])
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func pose(x: float) -> PackedFloat32Array:return PackedFloat32Array([1,0,0,x,0,1,0,1,0,0,1,1])
func _initialize() -> void:run.call_deferred()
func drive(focus: Vector3, loaded: Vector3i, absent: Vector3i) -> bool:
    var end:=Time.get_ticks_msec()+8000
    while Time.get_ticks_msec()<end:
        var state: Dictionary=live.step_model_paging(focus,64,160)
        if state.selection_scans>64 or state.step_records>256 or state.step_hash_bytes>65536 or state.step_operations>8 or state.jobs>8:
            check(false,"shared native budgets exceeded");return false
        var ready:=true
        for id in assets:
            var batch: Node3D=live.model(id)
            var residency: Dictionary=batch.region_stats()
            if residency.unloaded_bounds_nodes!=residency.unloaded_regions:
                check(false,"spatial index disagrees with region residency");return false
            ready=ready and batch.is_region_loaded(loaded) and not batch.is_region_loaded(absent)
        if ready and state.jobs==0:return true
        await process_frame
    return false
func drain() -> bool:
    live.drain_model_paging()
    var end:=Time.get_ticks_msec()+5000
    while Time.get_ticks_msec()<end:
        if live.step_model_paging(Vector3.ZERO,64,160).drained:return true
        await process_frame
    return false
func run() -> void:
    GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
    GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
    Engine.max_fps=1000;DirAccess.make_dir_recursive_absolute("res://reports")
    var source: Node3D=WORLD.new();root.add_child(source)
    for id in assets:
        var batch: Node3D=source.register_model(id,BoxMesh.new())
        # Render radius is deliberately below the unload radius in this fixture.
        batch.configure_render_streaming(true,64,16,1048576,2,65536)
        var ids:=PackedInt64Array();var transforms:=PackedFloat32Array()
        for n in 288:
            ids.append(n+1);transforms.append_array(pose((n/96)*2048+1+(n%16)*0.1))
        batch.upsert_instances(ids,transforms)
    var original: PackedByteArray=source.capture_snapshot()
    var raw: RefCounted=ClassDB.instantiate("NativeWorldArchive")
    var codec: RefCounted=ClassDB.instantiate("NativeStructuresSnapshot")
    codec.configure_assets(PackedStringArray([assets[0],assets[1],"test/new_asset"]))
    archive=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,codec,true,true)
    var path:=ProjectSettings.globalize_path("res://reports/model_focus_%d_%d.trw"%[OS.get_process_id(),Time.get_ticks_usec()])
    check(archive.acquire(path) and archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":original}))==OK and archive.start_region_reads(8,64*1024*1024),"saved multi-asset world opens one shared archive worker")
    live=WORLD.new();root.add_child(live)
    for id in assets:live.register_model(id,BoxMesh.new()).configure_render_streaming(true,64,16,1048576,2,65536)
    live.register_model("test/new_asset",BoxMesh.new()).configure_render_streaming(true,64,16,1048576,2,65536)
    check(live.restore_storage_snapshot(archive.decode(archive.read(path)).sections.structures),"scene restores unavailable model metadata")
    history=ClassDB.instantiate("NativeStaticHistory");history.configure(live._models.values(),1048576,128)
    check(live.enable_model_paging(archive,history),"scene adapter registers all saved assets with the shared scheduler")
    var before: Dictionary=live._model_scheduler.stats()
    live._model_scheduler.select_focus(Vector3(NAN,0,0),64,160)
    live._model_scheduler.select_focus(Vector3.ZERO,160,64)
    check(live._model_scheduler.stats().jobs==before.jobs and live._model_paging_assets.size()==2,"invalid focus/radii enqueue no work and unsaved empty asset waits for first save")
    check(await drive(Vector3.ZERO,Vector3i.ZERO,Vector3i(64,0,0)),"near focus automatically admits both assets without explicit region requests")
    check(await drive(Vector3(2048,0,0),Vector3i(64,0,0),Vector3i.ZERO),"travel automatically admits destination and retires old regions in both assets")
    check(await drive(Vector3.ZERO,Vector3i.ZERO,Vector3i(64,0,0)),"return travel restores both original nearby regions")
    check(live.model(assets[0]).capture_region(Vector3i.ZERO)==source.model(assets[0]).capture_region(Vector3i.ZERO),"automatic travel preserves exact model transforms")
    check(await drain(),"scene adapter drains before editing and saving")
    check(history.update(live.model(assets[0]),1,pose(4),AABB()),"editor journal changes a resident model")
    var edited: PackedByteArray=live.model(assets[0]).capture_region(Vector3i.ZERO)
    check(archive.publish(path,archive.encode({"terrain":PackedByteArray([1]),"structures":live.capture_storage_snapshot()}))==OK and live.resume_model_paging(),"partial save and resume adopt current model checkpoints")
    check(history.stats().undo_steps==1,"save handover preserves the external editor journal")
    check(live._model_paging_assets.size()==3,"first save makes newly registered asset eligible for paging")
    for frame in 30:
        live.step_model_paging(Vector3(2048,0,0),64,160)
        await process_frame
    check(live.model(assets[0]).is_region_loaded(Vector3i.ZERO) and history.stats().undo_steps==1,"automatic focus selection preserves resident region pinned by editor history")
    check(await drain() and history.clear_history() and live.resume_model_paging(),"explicit user history clear releases region pin without recreating journal")
    check(await drive(Vector3(2048,0,0),Vector3i(64,0,0),Vector3i.ZERO) and await drive(Vector3.ZERO,Vector3i.ZERO,Vector3i(64,0,0)),"saved edited region participates in automatic travel after its history pin is cleared")
    check(live.model(assets[0]).capture_region(Vector3i.ZERO)==edited,"edited transforms survive automatic retirement and readmission")
    live.step_model_paging(Vector3(4096,0,0),64,160)
    check(not live.finish_model_paging(),"reload cannot detach a scheduler without first requesting drain")
    check(await drain() and live.finish_model_paging(),"focus change with pending work drains and detaches before reload")
    check(live.restore_storage_snapshot(archive.decode(archive.read(path)).sections.structures) and live.enable_model_paging(archive,history),"saved scene reloads and reattaches native paging")
    check(await drive(Vector3.ZERO,Vector3i.ZERO,Vector3i(64,0,0)) and live.model(assets[0]).capture_region(Vector3i.ZERO)==edited,"reloaded world automatically admits the persisted edit")
    var state: Dictionary=live.step_model_paging(Vector3.ZERO,64,160)
    check(state.failed_transfers==0,"ordinary travel/save/reload produced no failed transfers")
    check(await drain() and live.finish_model_paging(),"normal shutdown drains and detaches all collections")
    live.free();source.free();history=null
    check(archive.region_read_stats().checkpoint_leases==0,"destroying scenes releases remaining unavailable-region backing leases")
    archive.release()
    var file:=FileAccess.open("res://reports/model_focus_paging.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Native automatic focus selection through scene adapter, partial save and explicit drain/reload. Headless; default game reload barrier and performance qualification remain open."},"  "));file.close()
    print("MODEL_FOCUS_PAGING checks=",checks," failures=",failures)
    quit(1 if failures else 0)
