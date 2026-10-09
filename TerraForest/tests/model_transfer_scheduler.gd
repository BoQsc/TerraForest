# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var scheduler: RefCounted
var archive: RefCounted
var history: RefCounted
var raw: RefCounted
var codec: RefCounted
var world: Node3D
var batches: Array[Node3D]=[]
var packets: Array[PackedByteArray]=[]
var pins: Array[PackedByteArray]=[]
var assets:=PackedStringArray(["test/scheduler_a","test/scheduler_b"])
var path: String
var max_tick_usec:=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func pose(x: float) -> PackedFloat32Array:return PackedFloat32Array([1,0,0,x,0,1,0,1,0,0,1,1])
func snapshot() -> PackedByteArray:
    return archive.encode({"terrain":PackedByteArray([1]),"structures":codec.encode(world.capture_snapshot(),{assets[0]:batches[0].capture_snapshot(),assets[1]:batches[1].capture_snapshot()})})
func request(index: int,retire: bool,priority: int=0) -> int:
    return scheduler.request(assets[index],Vector3i.ZERO,packets[index].slice(packets[index].size()-32),retire,priority,scheduler.stats().epoch)
func step() -> Dictionary:
    var state: Dictionary=scheduler.tick(7,4096,500,8)
    max_tick_usec=max(max_tick_usec,state.step_usec)
    if state.step_records>7 or state.step_hash_bytes>4096 or state.step_operations>8:check(false,"global work budgets exceeded")
    return state
func drain(count: int) -> Array:
    var result: Array=[];var end:=Time.get_ticks_msec()+10000
    while result.size()<count and Time.get_ticks_msec()<end:
        step();result.append_array(scheduler.poll(8));await process_frame
    check(result.size()==count,"requested jobs terminate within short fixture timeout")
    return result
func complete(results: Array) -> bool:
    for result in results:
        if result.result!="complete":return false
    return true
func run() -> void:
    GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
    GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
    Engine.max_fps=1000
    DirAccess.make_dir_recursive_absolute("res://reports")
    path=ProjectSettings.globalize_path("res://reports/model_scheduler_%d_%d.trw" % [OS.get_process_id(),Time.get_ticks_usec()])
    codec=ClassDB.instantiate("NativeStructuresSnapshot");codec.configure_assets(assets)
    raw=ClassDB.instantiate("NativeWorldArchive");archive=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,codec,true)
    world=ClassDB.instantiate("NativeBlockWorld")
    for asset in assets:
        var batch: Node3D=ClassDB.instantiate("NativeStaticBatch");batch.configure_collision_only();batch.configure_asset(asset,BoxMesh.new())
        var ids:=PackedInt64Array();var transforms:=PackedFloat32Array()
        for i in 512:ids.append(i+1);transforms.append_array(pose(i%20))
        ids.append(10000);transforms.append_array(pose(65));batch.upsert_instances(ids,transforms)
        batches.append(batch);packets.append(batch.capture_region(Vector3i.ZERO))
    check(archive.acquire(path) and archive.publish(path,snapshot())==OK and archive.start_region_reads(8,64*1024*1024),"two saved collections share one archive read worker")
    var root: Dictionary=codec.decode_reference(raw.decode(archive.read(path)).sections.structures)
    for asset in assets:
        var reference: PackedByteArray=root.models[asset];var size:=reference.decode_u32(8)
        pins.append(reference.slice(12+size,44+size))
    var read_tickets:=PackedInt64Array()
    for i in 8:read_tickets.append(archive.request_model_metadata(assets[i%2],pins[i%2],100+i))
    check(not read_tickets.has(0) and archive.take_model_region_read(-1).is_empty(),"ticket-specific polling rejects unknown tickets without consuming shared results")
    var discard_ok:=true
    for i in [0,2,4,6]:discard_ok=archive.discard_model_region_read(read_tickets[i]) and discard_ok
    var read_end:=Time.get_ticks_msec()+5000
    while (archive.region_read_stats().outstanding!=4 or archive.region_read_stats().completed!=4) and Time.get_ticks_msec()<read_end:await process_frame
    var retained: Array=archive.poll_model_region_reads(8)
    for result in retained:discard_ok=discard_ok and result.ticket in [read_tickets[1],read_tickets[3],read_tickets[5],read_tickets[7]] and result.ok
    check(discard_ok and retained.size()==4 and archive.region_read_stats().reserved_bytes==0,"mixed pending/active/completed discards preserve other owners and release all reservations")
    check(not archive.discard_model_region_read(read_tickets[0]),"discarded or consumed tickets cannot affect later requests")
    var future: Array[PackedByteArray]=[]
    for version in range(3):
        for batch in batches:batch.upsert_instances(PackedInt64Array([10000]),pose(66+version))
        future.append(snapshot())
    for batch in batches:batch.upsert_instances(PackedInt64Array([10000]),pose(65))
    var far_packet: PackedByteArray=batches[0].capture_region(Vector3i(2,0,0))
    history=ClassDB.instantiate("NativeStaticHistory");history.configure(batches,1048576,256)
    history.update(batches[0],10000,pose(66),AABB());history.update(batches[0],10000,pose(67),AABB());history.undo(AABB())
    scheduler=ClassDB.instantiate("NativeModelTransferScheduler")
    check(not scheduler.configure(archive,history,0,64000000) and scheduler.configure(archive,history,4,3*5600232),"scheduler validates shared job and payload budgets")
    check(scheduler.register_collection(assets[0],batches[0],pins[0]) and scheduler.register_collection(assets[1],batches[1],pins[1]),"collections reserve checkpoint leases")
    var other: RefCounted=ClassDB.instantiate("NativeModelTransferScheduler");other.configure(archive,history,4,64000000)
    check(not other.register_collection(assets[0],batches[0],pins[0]),"two schedulers cannot control one collection")
    other=null
    var bound_jobs:=PackedInt64Array()
    for x in [1,2,3]:bound_jobs.append(scheduler.request(assets[0],Vector3i(x,0,0),packets[0].slice(packets[0].size()-32),true,0,0))
    check(not bound_jobs.has(0) and scheduler.request(assets[1],Vector3i.ZERO,packets[1].slice(packets[1].size()-32),true,0,0)==0 and scheduler.stats().reserved_bytes==3*5600232,"one shared byte budget rejects fourth job across asset collections")
    for ticket in bound_jobs:scheduler.cancel(ticket)
    check(scheduler.stats().completed==3 and request(0,true)==0,"unpolled completion records retain bounded queue reservations")
    check(scheduler.poll(8).size()==3 and scheduler.stats().reserved_bytes==0,"poll releases scheduler reservations")
    var io_cancel:=request(0,true);scheduler.tick(7,4096,2000,1)
    check(scheduler.cancel(io_cancel) and scheduler.poll(1)[0].result=="cancelled","in-flight read cancellation discards only its owned ticket")
    var io_end:=Time.get_ticks_msec()+5000
    while archive.region_read_stats().outstanding>0 and Time.get_ticks_msec()<io_end:await process_frame
    check(archive.region_read_stats().outstanding==0 and archive.region_read_stats().reserved_bytes==0,"discarded asynchronous read eventually releases archive byte and checkpoint references")
    var history_job: int=scheduler.request(assets[0],Vector3i(2,0,0),far_packet.slice(far_packet.size()-32),true,0,0)
    var rejected_history:=await drain(1)
    check(history_job>0 and rejected_history.size()==1 and rejected_history[0].result=="failed" and batches[0].is_region_loaded(Vector3i(2,0,0)),"history-pinned region cannot be retired even with verified saved bytes")
    var reentrant: Dictionary={"calls":0,"blocked":true}
    var observer:=func():
        reentrant.calls+=1
        reentrant.blocked=reentrant.blocked and scheduler.stats().busy and not scheduler.set_epoch(99) and not scheduler.stop() and scheduler.poll(8).is_empty()
    batches[1].changed.connect(observer)
    var low:=request(0,true,1);var high:=request(1,true,200)
    check(low>0 and high>low and request(0,true)==0,"duplicate region jobs are rejected with monotonic tickets")
    var external: int=archive.request_model_metadata(assets[0],pins[0],99)
    scheduler.tick(7,4096,2000,1)
    var end:=Time.get_ticks_msec()+5000
    while archive.region_read_stats().completed<2 and Time.get_ticks_msec()<end:await process_frame
    scheduler.tick(7,4096,2000,1);scheduler.tick(7,4096,2000,1)
    check(batches[1].region_admission_stats().active and not batches[0].region_admission_stats().active,"higher-priority collection starts before earlier lower-priority request")
    var foreign: Dictionary=archive.take_model_region_read(external)
    check(foreign.get("ok",false) and foreign.epoch==99,"scheduler leaves another consumer's metadata completion untouched")
    check(complete(await drain(2)) and batches[0].region_stats().unloaded_regions==1 and batches[1].region_stats().unloaded_regions==1,"both collections retire under one global records/hash/operations budget")
    batches[1].changed.disconnect(observer);observer=Callable()
    check(reentrant.calls==1 and reentrant.blocked,"publication callbacks cannot mutate scheduler jobs or budgets reentrantly")
    check(history.stats().undo_steps==1 and history.stats().redo_steps==1 and history.redo(AABB()) and history.undo(AABB()),"unrelated editor undo/redo survives shared retirement")
    request(0,false);request(1,false)
    end=Time.get_ticks_msec()+5000
    while batches[0].region_admission_stats().staged_records==0 and Time.get_ticks_msec()<end:step();await process_frame
    check(batches[0].region_admission_stats().staged_records>0 and scheduler.set_epoch(1),"new focus epoch cancels an admission after partial staging")
    var cancelled:=await drain(2)
    check(cancelled.size()==2 and cancelled[0].result=="cancelled" and cancelled[1].result=="cancelled" and batches[0].region_stats().reserved_ids==512 and batches[1].region_stats().reserved_ids==512,"cancelled staging rolls back both collections without losing reserved IDs")
    check(scheduler.request(assets[0],Vector3i.ZERO,packets[0].slice(packets[0].size()-32),false,0,0)==0,"stale focus epoch cannot enqueue new work")
    request(0,false);request(1,false)
    check(complete(await drain(2)) and batches[0].capture_region(Vector3i.ZERO)==packets[0] and batches[1].capture_region(Vector3i.ZERO)==packets[1],"new epoch restores exact saved transforms in both collections")
    var committed:=request(0,true)
    end=Time.get_ticks_msec()+5000
    while batches[0].region_admission_stats().phase!=4 and Time.get_ticks_msec()<end:step();await process_frame
    check(batches[0].region_admission_stats().phase==4 and scheduler.cancel(committed),"cancellation can arrive after logical retirement commits")
    var committed_result:=await drain(1)
    check(committed_result.size()==1 and committed_result[0].result=="complete" and committed_result[0].cancel_requested and batches[0].region_stats().retiring_instances==0,"committed retirement finishes bounded cleanup instead of pretending to roll back")
    var vanished:=request(1,true);batches[1].free()
    check(scheduler.tick(7,4096,2000,1).step_operations==1,"destroyed-collection cleanup consumes the shared operation budget")
    var vanished_result:=await drain(1)
    check(vanished>0 and vanished_result.size()==1 and vanished_result[0].error=="collection_destroyed","weak collection destruction terminates queued work without dereferencing freed nodes")
    request(0,false)
    check(scheduler.stop() and scheduler.poll(8).size()==1 and request(0,false)==0,"stop cancels queued work and rejects new jobs without stopping shared archive worker")
    check(scheduler.unregister_collection(assets[0]) and scheduler.unregister_collection(assets[1]) and archive.region_read_stats().checkpoint_leases==1,"unregister retains backing lease only for the unavailable collection")
    scheduler=null
    for bytes in future:check(archive.publish(path,bytes)==OK,"later world save publishes while detached collection retains old checkpoint")
    var ticket: int=archive.request_model_checkpoint_region_read(assets[0],Vector3i.ZERO,packets[0].slice(packets[0].size()-32),pins[0],4)
    end=Time.get_ticks_msec()+5000
    while archive.region_read_stats().completed<1 and Time.get_ticks_msec()<end:await process_frame
    check(archive.take_model_region_read(ticket).get("checkpoint_verified",false),"collection-owned lease survives scheduler destruction and root rotations")
    scheduler=ClassDB.instantiate("NativeModelTransferScheduler");scheduler.configure(archive,history,4,3*5600232)
    check(scheduler.register_collection(assets[0],batches[0],pins[0]),"replacement scheduler adopts retained collection checkpoint")
    request(0,false)
    end=Time.get_ticks_msec()+5000
    while batches[0].region_admission_stats().staged_records==0 and Time.get_ticks_msec()<end:step();await process_frame
    scheduler=null
    check(not batches[0].region_admission_stats().active and batches[0].region_stats().reserved_ids==512 and archive.region_read_stats().checkpoint_leases==1,"exceptional scheduler destruction rolls back owned staging and leaves backing lease with collection")
    batches[0].free();world.free()
    check(archive.region_read_stats().checkpoint_leases==0,"collection destruction releases the final checkpoint lease")
    archive.release()
    var file:=FileAccess.open("res://reports/model_transfer_scheduler.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"maximum_observed_tick_usec":max_tick_usec,"tick_observation_limit_usec":2000,"tick_observation_passed":max_tick_usec<=2000,"scope":"Shared native model transfer correctness and aggregate work budgets; not rendered frame or thermal qualification."},"  "));file.close()
    print("MODEL_TRANSFER_SCHEDULER checks=",checks," failures=",failures," max_tick_usec=",max_tick_usec)
    quit(1 if failures else 0)
