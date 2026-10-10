# SPDX-License-Identifier: 0BSD
extends SceneTree
const Extension=preload("res://addons/world_runtime/world_runtime.gdextension")
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var store: RefCounted=ClassDB.instantiate("NativeEntityStore");store.configure(100020)
	store.spawn_grid(100000,Vector3(10000,0,10000),2,Vector3.ZERO)
	var local:=PackedInt64Array()
	for i in 6:local.append(store.spawn(Vector3(i*2,2,0),Vector3.ZERO))
	var pool: Node3D=ClassDB.instantiate("NativeEntityActivation");root.add_child(pool)
	check(not pool.configure(store,65) and pool.configure(store,3) and not pool.configure(store,3),"pool capacity bounded and immutable")
	var nodes:=PackedInt64Array()
	for child in pool.get_children():nodes.append(child.get_instance_id())
	var selected: Dictionary=pool.select(Vector3.ZERO,16,4096)
	check(selected.active==3 and selected.selection_complete and not selected.complete,"nearest three activate with explicit population truncation")
	check(pool.active_handles()==local.slice(0,3),"nearest identities selected deterministically")
	var targets:=PackedVector3Array([Vector3(10,2,0),Vector3(12,2,0),Vector3(14,2,0)])
	var snapshot: PackedByteArray=store.capture_storage_snapshot()
	check(pool.tick(targets,1.0/60,PackedByteArray([0,0,0])) and store.capture_storage_snapshot()==snapshot,"unready active entities remain unchanged")
	check(not pool.tick(targets,1.0/60,PackedByteArray([1,1])) and store.capture_storage_snapshot()==snapshot,"mismatched readiness rejects before mutation")
	var invalid:=targets.duplicate();invalid[2]=Vector3(NAN,0,0)
	check(not pool.tick(invalid,1.0/60,PackedByteArray([1,1,1])) and store.capture_storage_snapshot()==snapshot,"invalid last target rejects whole batch")
	await physics_frame
	check(pool.tick(targets,1.0/60,PackedByteArray([1,1,1])) and store.get_position(local[0]).x>0,"native batch advances selected actors")
	pool.select(Vector3(10,2,0),3,4096)
	check(pool.active_handles().has(local[5]) and not pool.active_handles().has(local[0]),"focus change retires distant actor and activates nearer identity")
	pool.select(Vector3(5000,0,0),16,4096)
	var disabled:=true
	for child in pool.get_children():disabled=disabled and child.collision_layer==0 and child.collision_mask==0
	check(pool.active_handles().is_empty() and disabled,"empty interest region disables every collision proxy")
	selected=pool.select(Vector3.ZERO,16,1)
	check(not selected.selection_complete and pool.active_handles().is_empty(),"exhausted candidate budget cannot activate uncertified nearest subset")
	pool.select(Vector3.ZERO,16,4096)
	store.restore_storage_snapshot(snapshot)
	check(not pool.tick(targets,1.0/60,PackedByteArray([1,1,1])),"restore invalidates old active handles")
	pool.select(Vector3.ZERO,16,4096)
	check(pool.active_handles().size()==3 and pool.active_handles()[0]!=local[0],"selection rebinds restored identities using fresh handles")
	var after:=PackedInt64Array()
	for child in pool.get_children():after.append(child.get_instance_id())
	check(after==nodes and pool.get_child_count()==3,"travel saturation and restore reuse fixed body allocation")
	pool.free();await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/entity_activation.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close();quit(1 if failures else 0)
