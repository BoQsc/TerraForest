# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func settle() -> void:
	for i in 12:await physics_frame;await process_frame
func ray() -> Dictionary:
	return root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0.5,1,2),Vector3(0.5,1,-2),2))
func run() -> void:
	check(load("res://demo/world.tscn")!=null,"production door interaction parses")
	var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
	check(world.prepare(),"structures prepared")
	var entry: Dictionary=preload("res://addons/structures/door_catalog.gd").register(world)
	check(not entry.is_empty(),"production door catalog registered")
	if entry.is_empty():world.free();quit(1);return
	var batch: Node3D=entry.collection
	var state: RefCounted=ClassDB.instantiate("NativeHingedDoors")
	var closed:=PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0])
	check(batch.upsert_instances(PackedInt64Array([7]),closed),"stable door placed")
	batch.set_collision_focus(Vector3.ZERO);await settle()
	check(not ray().is_empty(),"closed leaf blocks entrance")
	check(state.toggle(batch,7,AABB()).ok and state.is_open(7),"door opens without changing identity")
	await settle();check(ray().is_empty(),"open leaf clears entrance collision")
	var hinge_bytes: PackedByteArray=state.capture_storage_snapshot()
	var model_bytes: PackedByteArray=batch.capture_snapshot()
	var protected:=AABB(Vector3(0.3,0,-0.3),Vector3(0.4,1.8,0.6))
	check(not state.toggle(batch,7,protected).ok and state.capture_storage_snapshot()==hinge_bytes and batch.capture_snapshot()==model_bytes,"occupied swing rejects closing without mutation")
	var restored: RefCounted=ClassDB.instantiate("NativeHingedDoors")
	check(restored.restore_storage_snapshot(hinge_bytes) and batch.restore_snapshot(model_bytes),"open hinge and model restore")
	check(restored.toggle(batch,7,AABB()).ok and batch.get_instance(7)==closed and not restored.is_open(7),"restored door closes to exact original pose")
	await settle();check(not ray().is_empty(),"closed collision restored")
	var stable:=true
	for i in 100:
		stable=restored.toggle(batch,7,AABB()).ok and restored.toggle(batch,7,AABB()).ok and batch.get_instance(7)==closed and stable
	check(stable,"100 cycles have no hinge drift or identity loss")
	var corrupt:=hinge_bytes.duplicate();corrupt.resize(corrupt.size()-1)
	var before: PackedByteArray=restored.capture_storage_snapshot()
	check(not restored.restore_storage_snapshot(corrupt) and restored.capture_storage_snapshot()==before,"malformed hinge save rejected transactionally")
	check(not restored.toggle(batch,999,AABB()).ok,"missing door rejected")
	check(restored.toggle(batch,7,AABB()).ok,"door opens before editor relocation")
	var moved: PackedFloat32Array=batch.get_instance(7);moved[3]+=10
	check(batch.upsert_instances(PackedInt64Array([7]),moved),"editor relocates opened door")
	check(restored.toggle(batch,7,AABB()).ok and restored.toggle(batch,7,AABB()).ok and batch.get_instance(7)==moved,"stale hinge cannot teleport relocated door")
	var rotated:=PackedFloat32Array([0,0,1,5,0,1,0,2,-1,0,0,7])
	check(batch.upsert_instances(PackedInt64Array([8]),rotated) and restored.toggle(batch,8,AABB()).ok and restored.toggle(batch,8,AABB()).ok and batch.get_instance(8)==rotated,"rotated placed door uses its local hinge")
	world.free();print("DOOR_COMPONENT failures=",failures);quit(1 if failures else 0)
