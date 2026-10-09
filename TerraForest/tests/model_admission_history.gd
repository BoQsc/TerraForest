# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func pose(x: float) -> PackedFloat32Array:return PackedFloat32Array([1,0,0,x,0,1,0,1,0,0,1,1])
func drain(history: RefCounted,batch: Node3D,ticket: int) -> Dictionary:
	var state: Dictionary=batch.region_admission_stats()
	for i in 1000:
		if not state.active:break
		state=history.advance_region_admission(batch,ticket,1,65536,500)
		if not state.get("accepted",false):break
	check(not state.get("active",true),"journal-owned admission or rollback terminates")
	return state
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var batch: Node3D=ClassDB.instantiate("NativeStaticBatch")
	batch.configure_collision_only();batch.configure_asset("test/history_admission",BoxMesh.new())
	var ids:=PackedInt64Array();var values:=PackedFloat32Array()
	for i in 32:ids.append(i+1);values.append_array(pose(i%10))
	ids.append(1000);values.append_array(pose(65));ids.append(1001);values.append_array(pose(97))
	check(batch.upsert_instances(ids,values),"fixture has dense region and two unrelated loaded regions")
	var packet: PackedByteArray=batch.capture_region(Vector3i.ZERO)
	var history: RefCounted=ClassDB.instantiate("NativeStaticHistory")
	check(history.configure([batch],1048576,256),"journal registers collection")
	history.update(batch,1000,pose(66),AABB());history.update(batch,1000,pose(67),AABB());history.undo(AABB())
	check(history.stats().undo_steps==1 and history.stats().redo_steps==1,"fixture retains both undo and redo stacks")
	check(history.unload_region(batch,packet),"unreferenced region unload preserves history")
	var ticket: int=history.begin_region_admission(batch,packet)
	check(ticket>0 and batch.region_admission_stats().ticket==ticket,"journal admission returns generation ticket")
	check(not history.configure([batch],1048576,256),"journal cannot reconfigure away from an owned transfer")
	var unchanged: Dictionary=batch.region_admission_stats()
	check(batch.advance_region_admission(1,65536,500)==unchanged and not batch.cancel_region_admission(),"raw callers cannot advance or cancel journal-owned work")
	check(not history.advance_region_admission(batch,ticket+1,1,65536,500).accepted and not history.cancel_region_admission(batch,ticket+1),"wrong ticket cannot advance or cancel active generation")
	var other: RefCounted=ClassDB.instantiate("NativeStaticHistory");other.configure([batch],1048576,256)
	check(not other.advance_region_admission(batch,ticket,1,65536,500).accepted and not other.cancel_region_admission(batch,ticket),"another registered journal cannot steal ownership")
	for i in 20:
		history.advance_region_admission(batch,ticket,1,65536,500)
		if batch.region_admission_stats().staged_records>0:break
	check(batch.region_admission_stats().staged_records==1 and batch.get_instance(1).is_empty(),"journal advance preserves hidden partial state")
	check(history.redo(AABB()) and batch.get_instance(1000)==pose(67) and history.undo(AABB()) and batch.get_instance(1000)==pose(66),"unrelated undo and redo remain usable between admission steps")
	var observations: Dictionary={"calls":0,"intact":false,"reentrant":false}
	var observer:=func():
		observations.calls+=1
		observations.intact=history.stats().undo_steps==1 and history.stats().redo_steps==1
		observations.reentrant=history.undo(AABB()) or history.redo(AABB()) or history.begin_region_admission(batch,packet)!=0
	batch.changed.connect(observer)
	check(drain(history,batch,ticket).result=="complete" and batch.capture_region(Vector3i.ZERO)==packet,"owned admission publishes exact region")
	batch.changed.disconnect(observer);observer=Callable()
	check(observations.calls==1 and observations.intact and not observations.reentrant,"publication observer sees intact stacks and rejects reentrant journal commands")
	check(history.undo(AABB()) and batch.get_instance(1000)==pose(65) and history.redo(AABB()) and batch.get_instance(1000)==pose(66),"undo and redo remain exact after publication")
	check(not history.advance_region_admission(batch,ticket,1,65536,500).accepted,"completed ticket cannot replay publication")
	history.unload_region(batch,packet)
	var newer: int=history.begin_region_admission(batch,packet)
	check(newer>ticket and not history.advance_region_admission(batch,ticket,1,65536,500).accepted,"stale generation cannot advance replacement admission")
	history.advance_region_admission(batch,newer,1,65536,500)
	check(history.cancel_region_admission(batch,newer) and drain(history,batch,newer).result=="cancelled","journal cancellation drains through bounded rollback")
	check(history.stats().undo_steps==1 and history.stats().redo_steps==1 and batch.region_stats().reserved_ids==32,"cancelled transfer preserves both stacks and identities")
	var corrupt:=packet.duplicate();corrupt[40+corrupt.decode_u32(32)+8]^=1
	newer=history.begin_region_admission(batch,corrupt)
	check(newer>0 and drain(history,batch,newer).result=="failed" and history.stats().undo_steps==1 and history.stats().redo_steps==1,"checksum failure preserves both journal stacks")
	newer=history.begin_region_admission(batch,packet)
	var changed: Dictionary={"done":false}
	var external:=func():
		if not changed.done:
			changed.done=true;batch.upsert_instances(PackedInt64Array([1001]),pose(98))
	batch.changed.connect(external)
	drain(history,batch,newer)
	batch.changed.disconnect(external);external=Callable()
	check(changed.done and history.stats().undo_steps==0 and history.stats().redo_steps==0,"external mutation during publication still creates a history barrier")
	# Ownership is weak: discarding a journal must not permanently lock the batch.
	check(history.unload_region(batch,packet),"orphan fixture unloads")
	newer=history.begin_region_admission(batch,packet)
	history=null
	check(batch.cancel_region_admission(),"destroyed journal releases raw cancellation capability")
	for i in 1000:
		if not batch.region_admission_stats().active:break
		batch.advance_region_admission(1,65536,500)
	check(batch.region_admission_stats().result=="cancelled" and batch.region_stats().reserved_ids==32,"orphan rollback preserves stored-region reservations")
	check(batch.begin_region_admission(packet),"raw transfer can start after orphan cleanup")
	check(other.begin_region_admission(batch,packet)==0 and not other.advance_region_admission(batch,batch.region_admission_stats().ticket,1,65536,500).accepted,"journal cannot adopt an unrelated raw transfer")
	batch.cancel_region_admission()
	for i in 1000:
		if not batch.region_admission_stats().active:break
		batch.advance_region_admission(1,65536,500)
	newer=other.begin_region_admission(batch,packet)
	check(newer>0,"remaining journal can start its own transfer")
	batch.free()
	check(other.configure([],1048576,256),"destroyed collection does not pin journal configuration")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/model_admission_history.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures}));file.close()
	print("MODEL_ADMISSION_HISTORY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
