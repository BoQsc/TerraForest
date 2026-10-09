# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var timings: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func pose(x: float) -> PackedFloat32Array:return PackedFloat32Array([1,0,0,x,0,1,0,1,0,0,1,1])
func signed_bytes(bytes: PackedByteArray) -> PackedByteArray:
	var payload:=bytes.slice(0,bytes.size()-32)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(payload);payload.append_array(hash.finish());return payload
func fixture(count: int) -> Dictionary:
	var source: Node3D=ClassDB.instantiate("NativeStaticBatch")
	source.configure_collision_only();source.configure_asset("test/incremental",BoxMesh.new())
	var ids:=PackedInt64Array();ids.resize(count)
	var values:=PackedFloat32Array();values.resize(count*12)
	for i in count:
		ids[i]=i+1;values[i*12]=1;values[i*12+5]=1;values[i*12+10]=1
		values[i*12+3]=i%10;values[i*12+7]=int(i/10)%10;values[i*12+11]=int(i/100)%10
	check(source.upsert_instances(ids,values),"fixture admits %d placements" % count)
	var store: RefCounted=ClassDB.instantiate("NativeModelRegionStore")
	var path:=ProjectSettings.globalize_path("res://reports/incremental_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(path)
	check(store.open_store(path,"test/incremental").ok and store.publish_snapshot(source.capture_snapshot()).ok,"fixture persists exact regions")
	var metadata: PackedByteArray=store.read_metadata(store.pin_checkpoint().checkpoint).metadata
	var out: Dictionary={"metadata":metadata,"packet":source.capture_region(Vector3i.ZERO),"snapshot":source.capture_snapshot()}
	store.close();source.free();return out
func live(metadata: PackedByteArray) -> Node3D:
	var batch: Node3D=ClassDB.instantiate("NativeStaticBatch")
	batch.configure_collision_only();batch.configure_asset("test/incremental",BoxMesh.new())
	batch.configure_collision(AABB(Vector3(-1,-1,-1),Vector3(2,2,2)),0,8,2)
	check(batch.restore_metadata(metadata),"metadata bootstrap succeeds")
	return batch
func drain(batch: Node3D,records: int=256) -> Dictionary:
	var elapsed: Array=[];var bounded:=true;var state: Dictionary=batch.region_admission_stats()
	for i in 20000:
		if not state.active:break
		var start:=Time.get_ticks_usec();state=batch.advance_region_admission(records,65536,500);elapsed.append(Time.get_ticks_usec()-start)
		bounded=bounded and state.step_records<=records and state.step_hash_bytes<=65536
	check(not state.active and bounded,"admission or rollback terminates within record and hash-byte budgets")
	if not elapsed.is_empty():timings.append({"steps":elapsed.size(),"max_step_us":elapsed.max(),"result":state.result,"times_us":elapsed})
	return state
func patch_metadata(metadata: PackedByteArray,packet: PackedByteArray) -> PackedByteArray:
	var changed:=metadata.duplicate();var offset:=48+changed.decode_u32(8)+12
	for i in 32:changed[offset+i]=packet[packet.size()-32+i]
	return signed_bytes(changed)
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var small:=fixture(32);var batch:=live(small.metadata)
	var before: Dictionary=batch.capture_storage_state()
	check(batch.begin_region_admission(small.packet),"begin reserves one cooperative admission")
	check(not batch.begin_region_admission(small.packet),"second admission rejected without replacing active work")
	var state: Dictionary=batch.region_admission_stats()
	for i in 100:
		state=batch.advance_region_admission(1,65536,500)
		if state.staged_records>0:break
	check(state.staged_records==1 and not batch.is_region_loaded(Vector3i.ZERO),"partially inserted region remains unavailable")
	check(batch.get_ids().is_empty() and batch.get_instance(1).is_empty() and batch.stats().instances==0,"partial records remain invisible to queries")
	check(batch.region_stats().logical_instances==32 and batch.region_stats().reserved_ids==32,"partial records preserve logical count and reserved identities")
	check(batch.capture_storage_state()==before and batch.capture_snapshot().is_empty(),"save during admission retains whole unavailable disk region")
	check(not batch.remove_instances(PackedInt64Array([1])) and not batch.upsert_instances(PackedInt64Array([1]),pose(90)),"staged identity cannot be removed or moved to a loaded region")
	check(batch.upsert_instances(PackedInt64Array([999]),pose(90)) and batch.get_instance(999)==pose(90),"unrelated loaded-region authoring remains available")
	check(not batch.restore_snapshot(small.snapshot) and not batch.restore_metadata(small.metadata) and not batch.restore_region(small.packet),"whole replacement and synchronous admission reject active transfer")
	check(not batch.configure_render_streaming(false,64,8,65536,1,4096),"active transfer cannot switch to unbounded render publication")
	check(not batch.is_collision_region_ready(AABB(Vector3.ZERO,Vector3.ONE)),"partial region remains collision unavailable")
	check(batch.cancel_region_admission(),"cancel begins bounded rollback")
	state=drain(batch,1)
	check(state.result=="cancelled" and batch.region_stats().staged_instances==0 and batch.region_stats().logical_instances==33 and batch.get_ids()==PackedInt64Array([999]),"rollback restores reservations and preserves unrelated authoring")
	check(batch.begin_region_admission(small.packet) and drain(batch).result=="complete","cancelled region can retry successfully")
	check(batch.capture_region(Vector3i.ZERO)==small.packet and batch.get_ids().size()==33,"publication exposes every exact record together")
	batch.free()
	# Published staged indexes must feed the existing bounded render/proxy paths.
	batch=ClassDB.instantiate("NativeStaticBatch");root.add_child(batch)
	batch.configure_asset("test/incremental",BoxMesh.new())
	batch.configure_render_streaming(true,128,8,65536,2,4096)
	batch.configure_collision(AABB(Vector3(-1,-1,-1),Vector3(2,2,2)),128,64,16)
	check(batch.restore_metadata(small.metadata) and batch.begin_region_admission(small.packet) and drain(batch).result=="complete","streaming collection accepts cooperative publication")
	for frame in 10:await physics_frame
	check(batch.render_stats().resident_instances==32 and batch.collision_stats().resident_bodies==32,"published records enter existing render and collision admission")
	check(batch.is_collision_region_ready(AABB(Vector3.ZERO,Vector3.ONE)),"collision readiness opens only after proxy admission")
	batch.free()
	batch=ClassDB.instantiate("NativeStaticBatch");batch.configure_collision_only();batch.configure_asset("test/incremental",BoxMesh.new())
	var empty: PackedByteArray=batch.capture_region(Vector3i.ZERO)
	check(batch.unload_region(empty) and batch.begin_region_admission(empty) and drain(batch).result=="complete" and batch.is_region_loaded(Vector3i.ZERO),"empty region publishes without phantom group indexes")
	batch.free()
	var dense:=fixture(100000);batch=live(dense.metadata)
	var start:=Time.get_ticks_usec();var began: bool=batch.begin_region_admission(dense.packet);var begin_us:=Time.get_ticks_usec()-start
	check(began and drain(batch).result=="complete" and batch.capture_snapshot()==dense.snapshot,"100000-object admission publishes byte-exact snapshot")
	check(batch.render_stats().indexed_instances==100000 and batch.region_stats().reserved_ids==0,"publication installs prepared indexes and releases all reservations")
	batch.free()
	# Correct outer and inner checksums cannot legitimize an invalid last record.
	var invalid: PackedByteArray=dense.packet.duplicate()
	var last:=40+invalid.decode_u32(32)+99999*56
	invalid.encode_u64(last,99999) # duplicates the preceding sorted ID
	var inner:=signed_bytes(invalid.slice(24,invalid.size()-32))
	invalid=invalid.slice(0,24);invalid.append_array(inner);invalid.resize(invalid.size()+32)
	invalid=signed_bytes(invalid)
	batch=live(patch_metadata(dense.metadata,invalid))
	check(batch.begin_region_admission(invalid),"signed malformed packet enters bounded validation")
	state=drain(batch)
	check(state.result=="failed" and state.error=="record" and batch.region_stats().resident_instances==0 and batch.region_stats().staged_instances==0 and batch.region_stats().reserved_ids==100000,"late malformed record rolls back all staged records without losing identities")
	batch.free()
	var corrupt: PackedByteArray=small.packet.duplicate();corrupt[40+corrupt.decode_u32(32)+8]^=1
	batch=live(small.metadata)
	check(batch.begin_region_admission(corrupt) and drain(batch).result=="failed" and batch.region_stats().reserved_ids==32,"corrupt payload fails incremental checksum before installation")
	batch.free()
	var bad_inner: PackedByteArray=small.packet.duplicate();bad_inner[bad_inner.size()-64]^=1;bad_inner=signed_bytes(bad_inner)
	batch=live(patch_metadata(small.metadata,bad_inner))
	check(batch.begin_region_admission(bad_inner) and drain(batch).result=="failed" and batch.region_stats().reserved_ids==32,"valid outer checksum cannot bypass corrupt inner checksum")
	batch.free()
	var qualified:=begin_us<=2000
	for row in timings:qualified=qualified and row.max_step_us<=2000
	var report: Dictionary={"runtime_admission_qualified":qualified,"runtime_call_budget_us":2000,"checks":checks,"failures":failures,"dense_begin_us":begin_us,"runs":timings,"scope":"Headless admission CPU only. Cooperative time target 500 us, at most 256 records and 65536 hash bytes per call. Scheduler stalls and one operation may exceed time target. Does not qualify render/collision selection, unload, whole-world paging, or thermal stability."}
	var file:=FileAccess.open("res://reports/model_incremental_admission.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	for row in timings:print("ADMISSION_STEPS ",row.steps," max_us=",row.max_step_us," result=",row.result)
	print("MODEL_INCREMENTAL_ADMISSION checks=",checks," failures=",failures," dense_begin_us=",begin_us)
	quit(1 if failures else (0 if qualified else 2))
