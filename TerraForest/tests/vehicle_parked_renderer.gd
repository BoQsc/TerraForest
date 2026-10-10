# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var fleet: RefCounted=ClassDB.instantiate("NativeVehicleFleet")
	var renderer: Node3D=ClassDB.instantiate("NativeParkedVehicleRenderer");root.add_child(renderer)
	var mesh:=BoxMesh.new();var material:=StandardMaterial3D.new();material.albedo_color=Color.CYAN
	var local:=Transform3D(Basis.from_euler(Vector3(0.1,0.2,0.3)).scaled(Vector3(2,3,4)),Vector3(1,2,3))
	check(not renderer.configure(fleet,[{"mesh":mesh,"transform":Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)}],8) and renderer.get_child_count()==0,"invalid prototype rejects without partial nodes")
	check(renderer.configure(fleet,[{"mesh":mesh,"transform":local,"material":material},{"mesh":mesh,"transform":Transform3D.IDENTITY}],8),"shared visual parts configure once")
	var pose:=Transform3D(Basis.from_euler(Vector3(0.2,1.0,0.1)),Vector3(800,50,1300))
	var first: int=fleet.spawn(pose);var second: int=fleet.spawn(Transform3D(Basis.IDENTITY,Vector3(810,50,1300)))
	var result: Dictionary=renderer.refresh(pose.origin,32,PackedInt64Array(),64)
	var batch: MultiMeshInstance3D=renderer.get_child(0)
	check(result.rendered==2 and batch.multimesh.get_instance_transform(0).is_equal_approx(pose*local),"batched prototype preserves rotated scaled part transform")
	check(batch.material_override==material and renderer.get_child_count()==2,"materials shared with one node per part,not per vehicle")
	check(renderer.refresh(pose.origin,32,PackedInt64Array(),64).upload_bytes==0,"unchanged parked records upload no transforms")
	result=renderer.refresh(pose.origin,32,PackedInt64Array([first]),64)
	check(result.ids==PackedInt64Array([second]) and result.rendered==1,"active identity excluded without duplicate representation")
	result=renderer.refresh(pose.origin,32,PackedInt64Array(),1)
	check(not result.complete and batch.multimesh.visible_instance_count==0 and not batch.visible,"candidate budget hides incomplete selection")
	result=renderer.refresh(pose.origin,32,PackedInt64Array(),64)
	check(result.rendered==2 and batch.visible,"complete refresh restores representation")
	fleet.remove(first);result=renderer.refresh(pose.origin,32,PackedInt64Array(),64)
	check(result.ids==PackedInt64Array([second]),"despawn removes old visual identity")
	batch.multimesh.instance_count=1;result=renderer.refresh(pose.origin,32,PackedInt64Array(),64)
	check(not result.ok and not batch.visible,"external buffer mutation fails closed")
	renderer.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/vehicle_parked_renderer.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures}));file.close()
	quit(1 if failures else 0)
