# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var storage: RefCounted=ClassDB.instantiate("NativeVehicleStorage")
	var pose:=Transform3D(Basis.from_euler(Vector3(.1,1.2,-.2)),Vector3(800,50,1300))
	var data: PackedByteArray=storage.encode(pose)
	check(data.size()==72 and storage.decode(data).pose.is_equal_approx(pose),"full vehicle pose round trip")
	check(storage.validate_snapshot(PackedByteArray()) and not storage.decode(PackedByteArray()).present,"old saves default to no vehicle")
	check(not storage.validate_snapshot(data.slice(0,-1)),"truncated pose rejected")
	var bad:=data.duplicate();bad.encode_double(16,NAN)
	check(not storage.validate_snapshot(bad),"nonfinite vehicle position rejected")
	bad=data.duplicate();bad.encode_double(40,5)
	check(not storage.validate_snapshot(bad),"invalid quaternion rejected")
	bad=data.duplicate();bad.encode_u32(4,99)
	check(not storage.validate_snapshot(bad),"unknown schema rejected")
	check(storage.encode(Transform3D(Basis.IDENTITY,Vector3(-1,50,100))).is_empty(),"outside world rejected on capture")
	check(storage.encode(Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3(800,50,1300))).is_empty(),"singular rotation rejected without normalization")
	var archive: RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var packed: PackedByteArray=archive.encode({"terrain":PackedByteArray([1,2,3]),"vehicles":data})
	check(archive.decode(packed).sections.vehicles==data,"compound archive preserves vehicle section")
	packed[packed.size()-1]^=1
	check(not archive.decode(packed).ok,"compound checksum detects changed vehicle bytes")
	quit(0 if failures==0 else 1)
