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
	asset.configure(PackedInt32Array([0,0,0,1,0,3,0,1,0,5,0,1,2,4,0,128,2,8,0,1]))
	var old:PackedVector3Array=asset.clearance_samples(Vector3i.ZERO,0,0,512)
	var banded:PackedVector3Array=asset.clearance_samples(Vector3i.ZERO,0,0,512,5)
	check(old.size()==banded.size() and old[0]==banded[0] and banded[0].y==1.5,"surface band preserves buried room probes and paging counts")
	check(old[5].y==4.5 and banded[5].y==5.5,"surface-floor footing does not count soil beneath a garage slab as room intrusion")
	check(old[2].y==3.5 and banded[2].y==5.5 and old[1]==banded[1],"soil inside a solid underground wall is allowed without skipping adjacent room air")
	check(asset.clearance_samples(Vector3i.ZERO,0,0,512,-1).is_empty() and asset.clearance_samples(Vector3i.ZERO,0,0,512,33).is_empty(),"invalid surface bands are rejected")
	quit(1 if failures else 0)
