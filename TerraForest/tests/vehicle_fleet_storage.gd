# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var storage: RefCounted=ClassDB.instantiate("NativeVehicleStorage")
	var pose:=Transform3D(Basis.from_euler(Vector3(0.1,1.2,-0.2)),Vector3(800,50,1300))
	var empty: Dictionary=storage.decode_fleet(PackedByteArray())
	check(empty.ok and empty.records.is_empty() and empty.next_identity==1,"legacy absence migrates to empty fleet")
	var migrated: Dictionary=storage.decode_fleet(storage.encode(pose))
	check(migrated.ok and migrated.records[0].identity==1 and migrated.next_identity==2 and migrated.records[0].pose.is_equal_approx(pose),"legacy car migrates with stable identity and pose")
	var rows: Array=[{"identity":1,"pose":pose},{"identity":9,"pose":Transform3D(Basis.IDENTITY,Vector3(900,60,1400))}]
	var data: PackedByteArray=storage.encode_fleet(rows,12)
	var result: Dictionary=storage.decode_fleet(data)
	check(data.size()==152 and result.ok and result.next_identity==12 and result.records[1].identity==9 and result.records[1].pose==rows[1].pose,"sparse identities and next counter round trip")
	check(not storage.validate_snapshot(data),"legacy single-car owner rejects fleet instead of truncating")
	check(storage.decode_fleet(storage.encode_fleet([],12)).next_identity==12,"empty fleet preserves nonreuse counter")
	check(storage.encode_fleet(rows,9).is_empty(),"next counter cannot reuse existing identity")
	check(storage.encode_fleet([rows[1],rows[0]],12).is_empty(),"unsorted identities rejected")
	check(storage.encode_fleet([rows[0],rows[0]],12).is_empty(),"duplicate identities rejected")
	check(storage.encode_fleet([{"identity":1.0,"pose":pose}],2).is_empty(),"floating identity rejected")
	check(storage.encode_fleet([{"identity":1,"pose":Vector3.ZERO}],2).is_empty(),"wrong pose type rejected")
	check(not storage.validate_fleet_snapshot(data.slice(0,-1)),"truncated fleet rejected")
	var bad:=data.duplicate();bad.append(0)
	check(not storage.validate_fleet_snapshot(bad),"trailing bytes rejected")
	bad=data.duplicate();bad.encode_u32(12,1)
	check(not storage.validate_fleet_snapshot(bad),"reserved header rejected")
	bad=data.duplicate();bad.encode_u64(88,1)
	check(not storage.validate_fleet_snapshot(bad),"duplicate serialized identity rejected")
	bad=data.duplicate();bad.encode_double(32,NAN)
	check(not storage.validate_fleet_snapshot(bad) and not storage.decode_fleet(bad).has("records"),"nonfinite pose rejected without partial decoded records")
	bad=data.duplicate();bad.encode_double(56,10)
	check(not storage.validate_fleet_snapshot(bad),"invalid quaternion rejected")
	var large: Array=[]
	for i in 65536:large.append({"identity":i+1,"pose":pose})
	var begin:=Time.get_ticks_usec();var full: PackedByteArray=storage.encode_fleet(large,65537);var elapsed:=Time.get_ticks_usec()-begin
	check(full.size()==4194328 and storage.validate_fleet_snapshot(full),"maximum65536 records remain bounded and validate")
	large.append({"identity":65537,"pose":pose})
	check(storage.encode_fleet(large,65538).is_empty(),"over-capacity rejected")
	print("Maximum archive encode_us=",elapsed," bytes=",full.size()," (not a runtime frame-budget qualification)")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/vehicle_fleet_storage.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"encode_us":elapsed,"bytes":full.size()}));file.close()
	quit(1 if failures else 0)
