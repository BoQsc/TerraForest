# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var runs: Array=[]
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func pose(x: float) -> PackedFloat32Array:return PackedFloat32Array([1,0,0,x,0,1,0,1,0,0,1,1])
func signed_bytes(bytes: PackedByteArray) -> PackedByteArray:
	var payload:=bytes.slice(0,bytes.size()-32)
	var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(payload);payload.append_array(hash.finish());return payload
func fixture(count: int,neighbor: bool=false,rendered: bool=false) -> Node3D:
	var batch: Node3D=ClassDB.instantiate("NativeStaticBatch")
	if not rendered:batch.configure_collision_only()
	batch.configure_asset("test/retirement",BoxMesh.new())
	if rendered:
		batch.configure_render_streaming(true,128,8,65536,2,4096)
		batch.configure_collision(AABB(Vector3(-1,-1,-1),Vector3(2,2,2)),128,64,16)
	var ids:=PackedInt64Array();ids.resize(count)
	var values:=PackedFloat32Array();values.resize(count*12)
	for i in count:
		ids[i]=i+1;values[i*12]=1;values[i*12+5]=1;values[i*12+10]=1
		values[i*12+3]=i%10;values[i*12+7]=int(i/10)%10;values[i*12+11]=int(i/100)%10
	if neighbor:ids.append(1000);values.append_array(pose(65))
	check(batch.upsert_instances(ids,values),"fixture creates %d cold records" % count)
	return batch
func drain(batch: Node3D,history: RefCounted=null,ticket: int=0,budget: int=256,label: String="retire") -> Dictionary:
	var state: Dictionary=batch.region_admission_stats();var times: Array=[];var bounded:=true
	for i in 20000:
		if not state.active:break
		var start:=Time.get_ticks_usec()
		state=history.advance_region_retirement(batch,ticket,budget,65536,500) if history else batch.advance_region_retirement(budget,65536,500)
		times.append(Time.get_ticks_usec()-start)
		if not state.get("accepted",true):break
		bounded=bounded and state.step_records<=budget and state.step_hash_bytes<=65536
	check(not state.get("active",true) and bounded,"retirement terminates within record/hash work limits")
	if not times.is_empty():runs.append({"label":label,"steps":times.size(),"max_us":times.max(),"times_us":times})
	return state
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var batch:=fixture(32,true)
	var packet: PackedByteArray=batch.capture_region(Vector3i.ZERO)
	var history: RefCounted=ClassDB.instantiate("NativeStaticHistory");history.configure([batch],1048576,256)
	history.update(batch,1000,pose(66),AABB());history.update(batch,1000,pose(67),AABB());history.undo(AABB())
	var before: PackedByteArray=batch.capture_snapshot()
	var ticket: int=history.begin_region_retirement(batch,packet)
	check(ticket>0,"journal starts cold region retirement")
	check(not history.advance_region_admission(batch,ticket,1,65536,500).accepted and not history.cancel_region_admission(batch,ticket),"admission APIs cannot drive or cancel retirement ticket")
	check(not batch.cancel_region_retirement() and not batch.begin_region_retirement(packet),"raw caller cannot replace or cancel journal-owned retirement")
	history.advance_region_retirement(batch,ticket,1,1,500)
	check(batch.capture_snapshot()==before and batch.get_ids().size()==33,"validation keeps whole live region readable")
	check(not batch.remove_instances(PackedInt64Array([1])) and not batch.upsert_instances(PackedInt64Array([1]),pose(90)) and not batch.can_insert_instance(pose(5),AABB()),"validation locks removals, moves and insertions in target region")
	check(not batch.set_instances(BoxMesh.new(),pose(3)) and not batch.restore_snapshot(before) and not batch.configure_asset("test/retirement",BoxMesh.new()),"whole replacement and prototype mutation cannot invalidate validation")
	check(history.redo(AABB()) and history.undo(AABB()) and batch.get_instance(1000)==pose(66),"unrelated journal editing remains usable during validation")
	check(history.cancel_region_retirement(batch,ticket) and drain(batch,history,ticket,1).result=="cancelled" and batch.capture_snapshot()==before,"prepublication cancellation preserves all live records")
	ticket=history.begin_region_retirement(batch,packet)
	var notification: Dictionary={"calls":0,"hidden":false,"history":false,"reentrant":false}
	var observer:=func():
		notification.calls+=1
		notification.hidden=not batch.is_region_loaded(Vector3i.ZERO) and batch.get_instance(1).is_empty() and batch.get_ids()==PackedInt64Array([1000])
		notification.history=history.stats().undo_steps==1 and history.stats().redo_steps==1
		notification.reentrant=history.undo(AABB()) or history.cancel_region_retirement(batch,ticket)
	batch.changed.connect(observer)
	for i in 100:
		history.advance_region_retirement(batch,ticket,1,65536,500)
		if not batch.is_region_loaded(Vector3i.ZERO):break
	batch.changed.disconnect(observer);observer=Callable()
	check(notification.calls==1 and notification.hidden and notification.history and not notification.reentrant,"availability publishes once with hidden records and intact history")
	check(batch.region_admission_stats().retiring_records==32 and batch.region_stats().logical_instances==33 and batch.region_stats().reserved_ids==32,"all retiring records remain logically reserved before cleanup")
	var storage: Dictionary=batch.capture_storage_state()
	var visible: Node3D=ClassDB.instantiate("NativeStaticBatch");visible.configure_collision_only();visible.configure_asset("test/retirement",BoxMesh.new())
	check(visible.restore_snapshot(storage.resident) and visible.get_ids()==PackedInt64Array([1000]) and storage.unavailable_checksums==packet.slice(packet.size()-32),"save during cleanup references whole exact disk region and only unrelated live records")
	visible.free()
	check(not history.cancel_region_retirement(batch,ticket) and not batch.begin_region_admission(packet),"published retirement must finish cleanup before reload")
	check(history.undo(AABB()) and history.redo(AABB()),"unrelated undo and redo remain usable during cleanup")
	check(drain(batch,history,ticket,1).result=="complete" and batch.region_stats().retiring_instances==0 and batch.region_stats().resident_instances==1,"bounded cleanup removes every target transform")
	check(history.stats().undo_steps==1 and history.stats().redo_steps==1,"cleanup does not add another history barrier")
	var reload: int=history.begin_region_admission(batch,packet)
	for i in 100:
		if not batch.region_admission_stats().active:break
		history.advance_region_admission(batch,reload,1,65536,500)
	check(batch.capture_snapshot()==before and history.stats().undo_steps==1 and history.stats().redo_steps==1,"retired region reloads byte exactly with history intact")
	history.clear_history();history.update(batch,1,pose(2),AABB())
	check(history.begin_region_retirement(batch,batch.capture_region(Vector3i.ZERO))==0,"journal-pinned region cannot retire")
	check(batch.begin_region_retirement(packet) and drain(batch).result=="failed" and not batch.get_instance(1).is_empty(),"stale packet cannot discard newer transform")
	batch.free();history=null
	batch=fixture(32);packet=batch.capture_region(Vector3i.ZERO);before=batch.capture_snapshot()
	var invalid:=packet.duplicate();invalid.encode_u64(40+invalid.decode_u32(32)+31*56,31)
	var inner:=signed_bytes(invalid.slice(24,invalid.size()-32));invalid=invalid.slice(0,24);invalid.append_array(inner);invalid.resize(invalid.size()+32);invalid=signed_bytes(invalid)
	check(batch.begin_region_retirement(invalid) and drain(batch).result=="failed" and batch.capture_snapshot()==before,"signed invalid final record leaves entire live region unchanged")
	var corrupt:=packet.duplicate();corrupt[40+corrupt.decode_u32(32)+8]^=1
	check(batch.begin_region_retirement(corrupt) and drain(batch).result=="failed" and batch.capture_snapshot()==before,"corrupt checksum cannot retire live data")
	var negative_zero:=before.duplicate();negative_zero.encode_u32(16+negative_zero.decode_u32(8)+8+4,0x80000000);negative_zero=signed_bytes(negative_zero)
	check(batch.restore_snapshot(negative_zero) and batch.begin_region_retirement(packet) and drain(batch).result=="failed" and batch.capture_snapshot()==negative_zero,"bitwise signed-zero change rejects stale retirement")
	batch.free()
	batch=fixture(0);packet=batch.capture_region(Vector3i.ZERO);before=batch.capture_snapshot()
	check(batch.begin_region_retirement(packet) and drain(batch).result=="complete" and batch.restore_region(packet) and batch.capture_snapshot()==before,"empty region retires and reloads without phantom records")
	batch.free()
	# Raw observers also cannot advance recursively or reset outer step counters.
	batch=fixture(32);packet=batch.capture_region(Vector3i.ZERO)
	var raw_observation: Dictionary={"checked":false,"unchanged":false}
	var raw_observer:=func():
		var prior: Dictionary=batch.region_admission_stats()
		raw_observation.checked=true
		raw_observation.unchanged=batch.advance_region_retirement(1,65536,500)==prior
	batch.changed.connect(raw_observer)
	check(batch.begin_region_retirement(packet) and drain(batch).result=="complete" and raw_observation.checked and raw_observation.unchanged,"raw publication callback cannot advance recursively or alter work counters")
	batch.changed.disconnect(raw_observer);raw_observer=Callable();batch.free()
	# An empty-region reservation must recheck capacity at publication because
	# unrelated authoring remains allowed while checksums advance.
	batch=fixture(0)
	var capacity_ids:=PackedInt64Array();var capacity_values:=PackedFloat32Array()
	for i in 4095:capacity_ids.append(i+1);capacity_values.append_array(pose(i*32))
	check(batch.upsert_instances(capacity_ids,capacity_values),"capacity fixture fills 4095 origin groups")
	packet=batch.capture_region(Vector3i(-1,0,0))
	check(batch.begin_region_retirement(packet) and batch.upsert_instances(PackedInt64Array([4096]),pose(4095*32)),"unrelated authoring can fill final group during empty retirement validation")
	check(drain(batch).result=="failed" and batch.region_stats().resident_regions==4096 and batch.region_stats().unloaded_regions==0,"empty retirement cannot exceed region capacity at publication")
	batch.free()
	# Published retirement cannot be cancelled, even when the owning journal dies.
	batch=fixture(32);packet=batch.capture_region(Vector3i.ZERO)
	history=ClassDB.instantiate("NativeStaticHistory");history.configure([batch],1048576,256)
	ticket=history.begin_region_retirement(batch,packet)
	for i in 100:
		history.advance_region_retirement(batch,ticket,1,65536,500)
		if not batch.is_region_loaded(Vector3i.ZERO):break
	history=null
	check(not batch.cancel_region_retirement() and drain(batch).result=="complete" and batch.region_stats().reserved_ids==32,"orphaned published retirement finishes cleanup without losing reservations")
	batch.free()
	batch=fixture(32,false,true);root.add_child(batch)
	for frame in 10:await physics_frame
	packet=batch.capture_region(Vector3i.ZERO)
	check(batch.render_stats().resident_instances==32 and not batch.begin_region_retirement(packet),"active rendered region cannot retire")
	batch.set_render_focus(Vector3(5000,0,0))
	for frame in 10:await physics_frame
	check(batch.render_stats().resident_instances==0 and batch.collision_stats().resident_bodies==32 and not batch.begin_region_retirement(packet),"physics residency independently prevents retirement")
	batch.set_collision_focus(Vector3(5000,0,0))
	for frame in 10:await physics_frame
	check(batch.collision_stats().resident_bodies==0 and batch.begin_region_retirement(packet),"region becomes eligible after render and physics owners release it")
	batch.set_render_focus(Vector3.ZERO);batch.set_collision_focus(Vector3.ZERO)
	for frame in 10:await physics_frame
	check(batch.render_stats().resident_instances==0 and batch.collision_stats().resident_bodies==0,"focus movement cannot readmit resources into locked retirement")
	check(batch.cancel_region_retirement() and drain(batch).result=="cancelled","cold region can cancel when focus returns")
	for frame in 10:await physics_frame
	check(batch.render_stats().resident_instances==32 and batch.collision_stats().resident_bodies==32,"cancelled retirement permits render and physics admission again")
	batch.free()
	batch=fixture(100000);before=batch.capture_snapshot();packet=batch.capture_region(Vector3i.ZERO)
	var store: RefCounted=ClassDB.instantiate("NativeModelRegionStore")
	var path:=ProjectSettings.globalize_path("res://reports/retirement_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]);DirAccess.make_dir_recursive_absolute(path)
	check(store.open_store(path,"test/retirement").ok and store.publish_snapshot(before).ok and store.read_region(Vector3i.ZERO).bytes==packet,"dense fixture persists and reads back exact region before retirement")
	var start:=Time.get_ticks_usec();var began: bool=batch.begin_region_retirement(packet);var begin_us:=Time.get_ticks_usec()-start
	check(began and drain(batch,null,0,256,"dense").result=="complete" and batch.region_stats().resident_instances==0 and batch.region_stats().reserved_ids==100000,"100000-record retirement removes all transforms without losing identities")
	check(batch.restore_region(store.read_region(Vector3i.ZERO).bytes) and batch.capture_snapshot()==before,"disk reload reconstructs dense retired region byte exactly")
	store.close();batch.free()
	var qualified:=begin_us<=2000
	for row in runs:qualified=qualified and row.max_us<=2000
	var report: Dictionary={"checks":checks,"failures":failures,"runtime_retirement_qualified":qualified,"runtime_call_budget_us":2000,"dense_begin_us":begin_us,"runs":runs,"scope":"Headless native cold-region retirement. GPU/physics residency prevents retirement. Capture and disk persistence are outside step timing; no automatic paging or thermal qualification."}
	var file:=FileAccess.open("res://reports/model_incremental_retirement.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	for row in runs:print("RETIREMENT_STEPS ",row.label," steps=",row.steps," max_us=",row.max_us)
	print("MODEL_INCREMENTAL_RETIREMENT checks=",checks," failures=",failures," qualified=",qualified)
	quit(1 if failures else (0 if qualified else 2))
