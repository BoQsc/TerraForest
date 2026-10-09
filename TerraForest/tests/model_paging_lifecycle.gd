# SPDX-License-Identifier: 0BSD
extends SceneTree
const TERRAIN=preload("res://addons/volumetric_terrain/terrain_world.gd")
const STRUCTURES=preload("res://addons/structures/structures_world.gd")
const PERSISTENCE=preload("res://addons/world_runtime/world_persistence.gd")
const COORDINATOR=preload("res://addons/structures/model_paging_coordinator.gd")
var terrain: Node3D
var structures: Node3D
var coordinator: Node
var persistence: RefCounted
var history: RefCounted
var focus:=Vector3(129,65,129)
var slot:="model_lifecycle_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
var assets:=PackedStringArray(["test/lifecycle_a","test/lifecycle_b"])
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func until(predicate: Callable) -> bool:
    var end:=Time.get_ticks_msec()+20000
    while not predicate.call() and Time.get_ticks_msec()<end:await process_frame
    return predicate.call()
func pose(x: float) -> PackedFloat32Array:return PackedFloat32Array([1,0,0,x,0,1,0,65,0,0,1,129])
func setup() -> bool:
    terrain=TERRAIN.new();terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true;root.add_child(terrain)
    structures=STRUCTURES.new();root.add_child(structures)
    for id in assets:structures.register_model(id,BoxMesh.new())
    persistence=PERSISTENCE.new()
    if not persistence.register_component("structures",structures.capture_storage_snapshot,structures.restore_storage_snapshot,structures.snapshot_validator(),structures.empty_snapshot()):return false
    if not persistence.enable_region_structures(true,true) or persistence.attach(terrain)!=OK:return false
    history=ClassDB.instantiate("NativeStaticHistory");history.configure(structures._models.values(),1048576,128)
    coordinator=COORDINATOR.new();root.add_child(coordinator)
    if not coordinator.attach(terrain,structures,history,func():return focus):return false
    structures.changed.connect(func():terrain.changed_since_save=true)
    return terrain.start(StandardMaterial3D.new(),false)==OK
func dispose() -> void:
    coordinator.free();structures.free();terrain.free();persistence=null;history=null
func near_ready() -> bool:
    return terrain.world_ready and structures.model(assets[0]).is_region_loaded(Vector3i(4,2,4)) and structures.model(assets[1]).is_region_loaded(Vector3i(4,2,4)) and coordinator.operation==""
func run() -> void:
    Engine.max_fps=240;DirAccess.make_dir_recursive_absolute("res://reports")
    check(setup(),"real terrain worker attaches model lifecycle coordinator")
    check(await until(func():return terrain.world_ready or not terrain.latest_error.is_empty()) and terrain.world_ready,"persistent world starts")
    if not terrain.world_ready:
        terrain.shutdown();dispose();finish();return
    for id in assets:
        var ids:=PackedInt64Array();var values:=PackedFloat32Array()
        for i in 512:ids.append(i+1);values.append_array(pose((129 if i<256 else 1409)+(i%8)*0.1))
        structures.model(id).upsert_instances(ids,values)
    terrain.save_world()
    check(await until(func():return coordinator.successful_saves==1 and coordinator.operation==""),"normal manual save publishes and automatically resumes paging")
    check(await until(func():return not structures.model(assets[0]).is_region_loaded(Vector3i(44,2,4)) and not structures.model(assets[1]).is_region_loaded(Vector3i(44,2,4))),"coordinator retires far saved models without test-driven transfer calls")
    check(terrain.backend.snapshot_codec.region_read_stats().worker_starts==1 and terrain.backend.snapshot_codec.region_read_stats().request_limit==16,"block and model paging share one coordinator-owned archive service")
    focus=Vector3(1409,65,129)
    check(await until(func():return coordinator.last_state.get("jobs",0)>0),"travel creates pending model work")
    terrain.save_world()
    check(terrain._manual_save_requested and coordinator.operation=="save","manual save waits at transfer boundary instead of dropping the request")
    check(await until(func():return coordinator.successful_saves==2 and coordinator.operation==""),"queued manual save finishes and paging resumes automatically")
    focus=Vector3(129,65,129)
    check(await until(near_ready),"nearby models return after save-boundary cancellation")
    check(history.update(structures.model(assets[0]),1,pose(132),AABB()),"player-style model edit updates resident state")
    terrain.autosave_timer=16;terrain.last_interaction_us=Time.get_ticks_usec()-4000000;terrain.changed_since_save=true
    check(await until(func():return coordinator.successful_saves==3 and coordinator.operation==""),"normal autosave uses the same drain/publication/resume boundary")
    var before: PackedByteArray=FileAccess.get_file_as_bytes(terrain.backend.save_path)
    var provider: Dictionary=persistence._providers["structures"]
    var original_capture: Callable=provider.capture
    provider.capture=func():return PackedByteArray([1])
    var completed: int=coordinator.save_completions
    terrain.save_world()
    check(await until(func():return coordinator.save_completions>completed and coordinator.operation==""),"rejected save releases the lifecycle wait")
    check(coordinator.successful_saves==3 and FileAccess.get_file_as_bytes(terrain.backend.save_path)==before,"invalid capture preserves previous canonical save")
    provider.capture=original_capture
    terrain.save_world()
    check(await until(func():return coordinator.waiting_save),"valid follow-up save enters worker publication")
    var old_epoch: int=terrain.epoch
    terrain.reload_world()
    check(terrain._reload_requested and terrain.epoch==old_epoch,"reload queues behind in-flight save without replacing live collections")
    check(await until(func():return terrain.epoch>old_epoch and near_ready()),"normal reload detaches, restores and automatically reattaches model paging")
    check(structures.model(assets[0]).capture_region(Vector3i(4,2,4)).size()>0 and history.update(structures.model(assets[0]),1,pose(133),AABB()),"reloaded world accepts another edit for shutdown persistence")
    check(await terrain.shutdown_after_edits(),"normal asynchronous shutdown drains paging and saves the last edit")
    dispose()
    check(setup() and await until(near_ready),"fresh process-equivalent world instance loads shutdown save")
    # Compare a concrete placement through the public transform accessor.
    check(structures.model(assets[0]).get_instance(1)==pose(133),"shutdown edit survives fresh archive and scene reconstruction")
    old_epoch=terrain.epoch
    terrain.reload_world(true)
    check(await until(func():return terrain.epoch>old_epoch and terrain.world_ready and coordinator.operation=="" and structures._model_scheduler!=null),"normal reset restores and reattaches paging")
    check(structures.model(assets[0]).get_instance(1).is_empty() and structures.model(assets[1]).get_instance(1).is_empty(),"reset removes prior model placements")
    check(await terrain.shutdown_after_edits(),"reopened world shuts down cleanly")
    dispose();finish()
func finish() -> void:
    var file:=FileAccess.open("res://reports/model_paging_lifecycle.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Actual terrain worker/manual save/autosave/reload/shutdown lifecycle with native model paging; headless correctness, not rendered performance."},"  "));file.close()
    print("MODEL_PAGING_LIFECYCLE checks=",checks," failures=",failures)
    quit(1 if failures else 0)
