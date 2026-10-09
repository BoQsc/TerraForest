# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
    checks+=1
    if not ok:failures+=1
    print(("PASS " if ok else "FAIL ")+label)
func metadata(asset: String,count: int,checkpoint: PackedByteArray,axis: int,offset: int) -> PackedByteArray:
    var name_bytes:=asset.to_ascii_buffer()
    var bytes:=PackedByteArray();bytes.resize(48+name_bytes.size()+count*92)
    bytes[0]=84;bytes[1]=70;bytes[2]=77;bytes[3]=68;bytes[4]=1
    bytes.encode_u32(8,name_bytes.size());bytes.encode_u32(12,count)
    for i in 32:bytes[16+i]=checkpoint[i]
    for i in name_bytes.size():bytes[48+i]=name_bytes[i]
    var at:=48+name_bytes.size()
    for i in count:
        if axis==3:
            bytes.encode_s32(at,int(i/256)+offset);bytes.encode_s32(at+4,int(i/16)%16+offset);bytes.encode_s32(at+8,i%16+offset)
        else:bytes.encode_s32(at+axis*4,i+offset)
        for n in 32:bytes[at+12+n]=1
        bytes.encode_u32(at+44,1)
        for diagonal in [0,4,8]:bytes.encode_float(at+48+diagonal*4,1)
        bytes.encode_u64(at+84,i+1);at+=92
    var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes);bytes.append_array(hash.finish())
    return bytes
func _initialize() -> void:run.call_deferred()
func mutation_check(batch: Node3D,archive: RefCounted,asset: String,checkpoint: PackedByteArray) -> void:
    var source: Node3D=ClassDB.instantiate("NativeStaticBatch");source.configure_collision_only();source.configure_asset(asset,BoxMesh.new())
    var ids:=PackedInt64Array();var values:=PackedFloat32Array()
    for i in 64:
        ids.append(i+1);values.append_array(PackedFloat32Array([1,0,0,i*32+1,0,1,0,1,0,0,1,1]))
    source.upsert_instances(ids,values)
    var snapshot: PackedByteArray=source.capture_snapshot();var packets: Array=[]
    for i in 64:packets.append(source.capture_region(Vector3i(i,0,0)))
    var valid: bool=batch.restore_snapshot(snapshot)
    for i in 64:
        valid=batch.unload_region(packets[(i*17)%64]) and valid
        var state: Dictionary=batch.region_stats()
        valid=valid and state.unloaded_bounds_nodes==i+1 and state.unloaded_bounds_height<=16
    check(valid,"shuffled retirement maintains exact balanced bounds index")
    var history: RefCounted=ClassDB.instantiate("NativeStaticHistory");history.configure([batch],1048576,128)
    var scheduler: RefCounted=ClassDB.instantiate("NativeModelTransferScheduler");scheduler.configure(archive,history,8,64*1024*1024)
    valid=scheduler.register_collection(asset,batch,checkpoint)
    for i in 64:
        scheduler.set_epoch(i+1);scheduler.poll(64)
        var selected: int=(i*29)%64
        valid=batch.restore_region(packets[selected]) and valid
        var state: Dictionary=batch.region_stats()
        valid=valid and state.unloaded_bounds_nodes==63-i and state.unloaded_bounds_height<=16
        for visit in 4:scheduler.select_focus(Vector3(selected*32+1,1,1),4,32768,64,2000)
        valid=valid and scheduler.stats().jobs==0
        if i<63:
            var remaining:=0
            while batch.is_region_loaded(Vector3i(remaining,0,0)):remaining+=1
            for visit in 4:scheduler.select_focus(Vector3(remaining*32+1,1,1),4,32768,64,2000)
            valid=valid and scheduler.stats().jobs>0
    scheduler.stop();scheduler.poll(64);scheduler.unregister_collection(asset)
    check(valid and batch.capture_snapshot()==snapshot,"shuffled admissions remove stale bounds and preserve discovery of remaining regions and exact final data")
    source.free()
func run() -> void:
    GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
    GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
    DirAccess.make_dir_recursive_absolute("res://reports")
    var results: Array=[]
    for spec in [[64,1,0,0,false],[4096,1,0,0,false],[4096,32,0,0,false],[4096,1,1,-2048,false],[4096,1,2,-2048,false],[4096,1,0,28672,false],[4096,1,0,0,true],[4096,32,3,-8,false]]:
        var count: int=spec[0];var asset_count: int=spec[1]
        var axis: int=spec[2];var offset: int=spec[3];var extended: bool=spec[4]
        var ids:=PackedStringArray();var batches: Array=[]
        var checkpoint:=PackedByteArray();checkpoint.resize(32);checkpoint.fill(2)
        var valid:=true
        for i in asset_count:
            var id:="test/discovery_%02d"%i;ids.append(id)
            var mesh:=BoxMesh.new()
            if extended:mesh.size=Vector3(300000,1,1)
            var batch: Node3D=ClassDB.instantiate("NativeStaticBatch");batch.configure_asset(id,mesh)
            if extended:batch.configure_collision(AABB(Vector3(-0.1,-0.1,-0.1),Vector3(0.2,0.2,0.2)),8,4,1)
            batch.configure_render_streaming(true,16,4,65536,1,4096)
            valid=batch.restore_metadata(metadata(id,count,checkpoint,axis,offset)) and valid;batches.append(batch)
        check(valid,"valid native metadata fixture: %d regions across %d assets"%[count,asset_count])
        var balanced:=true
        for batch in batches:
            var stats: Dictionary=batch.region_stats()
            balanced=balanced and stats.unloaded_bounds_nodes==count and stats.unloaded_bounds_height<=24
        check(balanced,"unavailable bounds index contains exactly the regions and remains balanced")
        var codec: RefCounted=ClassDB.instantiate("NativeStructuresSnapshot");codec.configure_assets(ids)
        var raw: RefCounted=ClassDB.instantiate("NativeWorldArchive")
        var archive: RefCounted=ClassDB.instantiate("NativeRegionWorldArchive");archive.configure(raw,codec,true,true)
        var path:=ProjectSettings.globalize_path("res://reports/discovery_%d_%d_%d_%d_%d_%d.trw"%[OS.get_process_id(),count,asset_count,axis,offset,int(extended)])
        check(archive.acquire(path),"selection fixture acquires an archive without reading region packets")
        var history: RefCounted=ClassDB.instantiate("NativeStaticHistory");history.configure(batches,1048576,128)
        var scheduler: RefCounted=ClassDB.instantiate("NativeModelTransferScheduler");scheduler.configure(archive,history,8,64*1024*1024)
        valid=true
        for i in asset_count:valid=scheduler.register_collection(ids[i],batches[i],checkpoint) and valid
        check(valid,"all metadata collections register")
        var calls:=0;var visits:=0;var peak_usec:=0;var queued:=false
        var focus:=Vector3(16,16,16)
        if axis==3:focus=Vector3.ONE*((15+offset)*32+16)
        else:focus[axis]=(count-1+offset)*32+16
        if extended:focus.x=-500 # Beyond every origin cell; only actual mesh bounds reach here.
        var begin:=Time.get_ticks_usec()
        while calls<4096:
            var state: Dictionary=scheduler.select_focus(focus,4,64,64,250)
            calls+=1;visits+=state.selection_scans;peak_usec=maxi(peak_usec,state.selection_usec)
            if state.selection_scans>64:check(false,"selection exceeded shared visit budget");break
            if state.jobs>0:queued=true;break
        var elapsed:=Time.get_ticks_usec()-begin
        results.append({"regions_per_asset":count,"assets":asset_count,"axis":axis,"offset":offset,"extended_visual_small_proxy":extended,"calls_to_first_request":calls,"visits":visits,"peak_selection_usec":peak_usec,"wall_usec":elapsed,"queued":queued,"first_request_gate_calls":4})
        check(queued and calls<=4,"near destination discovered within four selection calls: %d regions, %d assets (actual %d)"%[count,asset_count,calls])
        scheduler.set_epoch(1);scheduler.poll(64)
        scheduler.select_focus(Vector3(1000000,1000000,1000000),4,64,64,250)
        check(scheduler.stats().jobs==0,"empty distant query creates no false region requests")
        # Deliberately never tick: these synthetic digests test selection only,
        # not disk provenance, admission, arrival, rendering or frame timing.
        scheduler.stop();scheduler.poll(64)
        for id in ids:scheduler.unregister_collection(id)
        scheduler=null;history=null
        if count==64:mutation_check(batches[0],archive,ids[0],checkpoint)
        for batch in batches:batch.free()
        archive.release()
    var file:=FileAccess.open("res://reports/model_focus_discovery.json",FileAccess.WRITE)
    file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":results,"scope":"Synthetic validated metadata selection only, no disk packets or scheduler ticks. Calls are not elapsed game frames; no actual arrival/FPS claim."},"  "));file.close()
    print("MODEL_FOCUS_DISCOVERY ",JSON.stringify(results))
    quit(1 if failures else 0)
