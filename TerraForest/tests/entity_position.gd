# SPDX-License-Identifier: 0BSD
extends SceneTree
const Extension=preload("res://addons/world_runtime/world_runtime.gdextension")
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:
	var store: RefCounted=ClassDB.instantiate("NativeEntityStore");store.configure(4)
	var moving: int=store.spawn(Vector3.ZERO,Vector3(10,0,0))
	var sleeping: int=store.spawn(Vector3.ONE,Vector3.ZERO)
	var identity: int=store.persistent_id(moving)
	check(store.set_position(moving,Vector3(100,2,-100)),"cross-cell correction accepted")
	check(store.query_sphere(Vector3.ZERO,0.1,4,16).ids.is_empty() and store.query_sphere(Vector3(100,2,-100),0.1,4,16).ids==PackedInt64Array([moving]),"spatial ownership follows corrected position")
	check(store.persistent_id(moving)==identity and store.resolve_identity(identity)==moving,"correction preserves persistent identity and handle")
	store.step(0.1)
	check(store.get_position(moving)==Vector3(101,2,-100) and store.statistics().moving==1,"correction preserves velocity and moving membership")
	check(store.set_position(sleeping,Vector3(-100,4,100)) and store.statistics().moving==1,"relocating stationary entity does not wake it")
	check(store.set_position(moving,Vector3(102,2,-100)) and store.query_sphere(Vector3(102,2,-100),0.1,4,16).ids==PackedInt64Array([moving]),"within-cell correction updates query position")
	var snapshot: PackedByteArray=store.capture_storage_snapshot()
	check(not store.set_position(moving,Vector3(INF,0,0)) and not store.set_position(moving,Vector3(NAN,0,0)) and store.capture_storage_snapshot()==snapshot,"nonfinite correction rejects without mutation")
	store.despawn(sleeping);var reused: int=store.spawn(Vector3.ZERO,Vector3.ZERO)
	check(not store.set_position(sleeping,Vector3.ONE) and store.get_position(reused)==Vector3.ZERO,"stale handle cannot relocate reused slot")
	check(store.restore_storage_snapshot(snapshot) and store.get_position(store.resolve_identity(identity))==Vector3(102,2,-100),"corrected position survives snapshot restore")
	check(not store.set_position(moving,Vector3.ZERO),"pre-restore handle cannot modify restored entity")
	print("ENTITY_POSITION failures=",failures)
	DirAccess.make_dir_recursive_absolute("res://reports")
	var report:=FileAccess.open("res://reports/entity_position.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"failures":failures}));report.close()
	quit(1 if failures else 0)
