# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var fleet: RefCounted=ClassDB.instantiate("NativeVehicleFleet")
	var pose:=Transform3D(Basis.IDENTITY,Vector3(100,50,100))
	var first: int=fleet.spawn(pose);var second: int=fleet.spawn(pose)
	check(first==1 and second==2,"fresh records receive monotonic identities")
	check(fleet.query_near(pose.origin,0,1,16).ids==PackedInt64Array([first]) and fleet.query_near(pose.origin,0,1,16).truncated,"nearest ties use identity and cap is explicit")
	var limited: Dictionary=fleet.query_near(pose.origin,1,2,1)
	check(limited.ok and not limited.complete and limited.ids.is_empty() and limited.visited==1,"candidate exhaustion publishes no misleading nearest subset")
	check(fleet.remove(first) and not fleet.get_record(first).present,"removal retires identity")
	var third: int=fleet.spawn(pose);check(third==3,"removed identity is not reused")
	var moved:=Transform3D(Basis.IDENTITY,Vector3(800,50,800))
	check(fleet.set_pose(second,moved) and fleet.query_near(moved.origin,1,8,16).ids==PackedInt64Array([second]),"pose correction updates spatial membership")
	check(fleet.query_near(pose.origin,1,8,16).ids==PackedInt64Array([third]),"old cell no longer contains moved record")
	var before: PackedByteArray=fleet.capture_storage_snapshot()
	check(not fleet.set_pose(second,Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))) and fleet.capture_storage_snapshot()==before,"invalid correction leaves records intact")
	var restored: RefCounted=ClassDB.instantiate("NativeVehicleFleet")
	check(restored.restore_storage_snapshot(before) and restored.get_record(second).pose==moved and restored.statistics().next_identity==4,"snapshot restores identities poses and allocation counter")
	check(not restored.restore_storage_snapshot(PackedByteArray([1])) and restored.capture_storage_snapshot()==before,"invalid restore is atomic")
	check(not fleet.query_near(Vector3(NAN,0,0),1,8,16).ok and not fleet.query_near(pose.origin,129,8,16).ok,"invalid or unbounded query rejected")
	check(fleet.query_near(Vector3(1e30,1e30,1e30),1,8,16).complete,"distant finite query avoids integer conversion overflow")
	var codec: RefCounted=ClassDB.instantiate("NativeVehicleStorage")
	check(restored.restore_storage_snapshot(codec.encode(pose)) and restored.get_record(1).present and restored.statistics().next_identity==2,"legacy single car migrates into live ownership")
	var rows: Array=[]
	for i in 10000:rows.append({"identity":i+1,"pose":Transform3D(Basis.IDENTITY,Vector3(1500+(i%10),50,1500))})
	rows.append({"identity":10001,"pose":pose})
	check(fleet.restore_storage_snapshot(codec.encode_fleet(rows,10002)),"large parked population restores without scene bodies")
	var local: Dictionary=fleet.query_near(pose.origin,8,8,16)
	check(local.complete and local.visited==1 and local.ids==PackedInt64Array([10001]),"local selection visits1 record with10000 distant vehicles")
	check(fleet.remove(10001) and fleet.query_near(pose.origin,8,8,16).visited==0,"empty spatial cell is retired")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/vehicle_fleet.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"local_visited":local.visited,"population":10001}));file.close()
	quit(1 if failures else 0)
