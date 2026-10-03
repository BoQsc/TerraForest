# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void:
	var asset=ClassDB.instantiate("NativeBlockPrefab")
	asset.configure(PackedInt32Array([0,0,0,1,0,3,0,1,2,5,-1,1]))
	check(asset.clearance_sample_count()==4,"column envelope includes empty room beneath roof and isolated eave")
	var expected:=PackedVector3Array([Vector3(10.5,21.5,30.5),Vector3(10.5,22.5,30.5),Vector3(10.5,23.5,30.5),Vector3(11.5,25.5,32.5)])
	check(asset.clearance_samples(Vector3i(10,20,30),1,0,512)==expected,"rotation and interior sample positions match cell convention")
	check(asset.clearance_samples(Vector3i(10,20,30),1,2,1)==PackedVector3Array([expected[2]]) and asset.clearance_samples(Vector3i(10,20,30),1,3,512)==PackedVector3Array([expected[3]]),"cursor crosses column boundary without skipped probes")
	check(asset.clearance_samples(Vector3i.ZERO,0,4,512).is_empty() and asset.clearance_samples(Vector3i.ZERO,0,-1,512).is_empty() and asset.clearance_samples(Vector3i.ZERO,0,0,513).is_empty(),"invalid cursor and oversized batch rejected")
	check(not asset.configure(PackedInt32Array([0,0,0,0])) and asset.clearance_sample_count()==4,"failed configuration preserves clearance cache")
	asset.configure(PackedInt32Array([0,0,0,1,0,4095,0,1]))
	check(asset.clearance_sample_count()==4095 and asset.clearance_samples(Vector3i.ZERO,0,3584,512).size()==511,"tall sparse column is paged without expanded volume storage")
	asset.configure(PackedInt32Array())
	check(asset.clearance_sample_count()==0,"empty configuration clears envelopes")
	quit(1 if failures else 0)
