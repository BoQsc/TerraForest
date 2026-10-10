# SPDX-License-Identifier: 0BSD
extends SceneTree
const Extension=preload("res://addons/world_runtime/world_runtime.gdextension")
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var store: RefCounted=ClassDB.instantiate("NativeEntityStore");store.configure(4)
	var handle: int=store.spawn(Vector3(0,2,0),Vector3.ZERO);var id: int=store.persistent_id(handle)
	var orders: RefCounted=ClassDB.instantiate("NativeActorOrders")
	check(orders.configure(store) and not orders.configure(store),"order ownership configured once")
	check(not orders.set_target(999,Vector3.ONE) and not orders.set_target(id,Vector3(INF,0,0)),"unknown identity and invalid target rejected")
	check(orders.set_target(id,Vector3(10,2,0)),"persistent identity receives movement target")
	var snapshot: PackedByteArray=orders.capture_storage_snapshot()
	var bad:=snapshot.duplicate();bad.encode_u32(8,2)
	check(not orders.restore_storage_snapshot(bad) and orders.capture_storage_snapshot()==snapshot,"malformed order snapshot rejects atomically")
	bad=snapshot.duplicate();bad.encode_s64(16,999)
	check(not orders.restore_storage_snapshot(bad) and orders.capture_storage_snapshot()==snapshot,"orphan destination rejects against actor owner")
	var positions: PackedByteArray=store.capture_storage_snapshot();store.restore_storage_snapshot(positions)
	check(orders.restore_storage_snapshot(snapshot) and orders.get_target(id).target==Vector3(10,2,0),"orders survive handle regeneration")
	var pool: Node3D=ClassDB.instantiate("NativeEntityActivation");root.add_child(pool);pool.configure(store,2)
	check(pool.set_orders(orders),"activation pool binds matching order owner")
	pool.select(Vector3.ZERO,10,64);await physics_frame
	var result: Dictionary=pool.settle(1.0/60,func(_bounds: AABB):return true)
	check(result.ok and store.get_position(store.resolve_identity(id)).x>0,"native automatic simulation executes stored target")
	check(orders.clear_target(id) and not orders.get_target(id).present,"stop clears target")
	var x: float=store.get_position(store.resolve_identity(id)).x;await physics_frame;pool.settle(1.0/60,func(_bounds: AABB):return true)
	check(store.get_position(store.resolve_identity(id)).x==x,"cleared order stops horizontal movement")
	pool.free();await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/actor_orders.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close();quit(1 if failures else 0)
