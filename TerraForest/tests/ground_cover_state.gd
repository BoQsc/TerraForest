# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
	var state=ClassDB.instantiate("NativeGroundCoverState")
	var pose:=Transform3D(Basis(Vector3.UP,0.7).scaled(Vector3(0.8,1.2,0.9)),Vector3(970,20,970))
	var empty: PackedByteArray=state.capture_storage_snapshot()
	check(state.validate_snapshot(empty) and empty.size()==64,"unbound empty snapshot is valid")
	check(not state.mark(1) and state.add(0,pose)==0,"unbound state cannot accept edits")
	check(state.bind_world(1703,1) and state.bind_world(1703,1),"matching generation profile binds idempotently")
	check(not state.bind_world(1704,1) and not state.bind_world(1703,2),"different seed or generator is rejected")
	check(state.mark(1) and not state.mark(1) and not state.mark(0) and not state.mark(254017),"natural removal range and duplicates validated")
	var id: int=state.add(2,pose)
	check(id==4294967296,"authored identity is separate from all natural identities")
	var rows: Array=state.query(Vector2i(30,30))
	check(rows[2].ids==PackedInt64Array([id]) and rows[0].ids.is_empty(),"cell query returns only requested species and owner")
	check(state.query(Vector2i(31,30))[2].ids.is_empty() and state.query(Vector2i(-1,0)).is_empty(),"other and invalid cells do not expose record")
	var saved: PackedByteArray=state.capture_storage_snapshot()
	var fresh=ClassDB.instantiate("NativeGroundCoverState")
	check(fresh.restore_storage_snapshot(saved) and fresh.capture_storage_snapshot()==saved and fresh.query(Vector2i(30,30))==rows and fresh.contains(1),"fresh native state restores exact profile removals and placements")
	check(not fresh.bind_world(1704,1),"restored state cannot silently apply to a different seed")
	var broken: Array[PackedByteArray]=[]
	for offset in [0,8,16,24,32,40,48,56,64,72,80]:
		var data:=saved.duplicate();data.encode_u64(offset,0 if offset==32 else 9223372036854775807);broken.append(data)
	var nan_data:=saved.duplicate();nan_data.encode_float(88,NAN);broken.append(nan_data)
	broken.append(saved.slice(0,saved.size()-1))
	var extra:=saved.duplicate();extra.append(0);broken.append(extra)
	var atomic:=true
	for data in broken:
		var rejected: bool=not fresh.validate_snapshot(data) and not fresh.restore_storage_snapshot(data) and fresh.capture_storage_snapshot()==saved
		atomic=rejected and atomic
	check(atomic,"malformed header counts IDs species transforms and lengths reject without mutation")
	check(fresh.erase(id) and not fresh.erase(id) and fresh.add(1,pose)>id,"deleted authored IDs are never reused")
	check(saved==state.capture_storage_snapshot(),"other state edits do not mutate captured snapshot")
	var full=ClassDB.instantiate("NativeGroundCoverState");full.bind_world(1703,1)
	var accepted:=true
	for i in range(256): accepted=accepted and full.add(i%3,pose)!=0
	var before: PackedByteArray=full.capture_storage_snapshot()
	check(accepted and full.add(0,pose)==0 and before==full.capture_storage_snapshot(),"per-cell limit rejects atomically at 256 authored placements")
	pose.origin.x+=32
	check(full.add(0,pose)!=0,"full cell does not prevent placement in another cell")
	var invalid:=pose;invalid.origin.x=-1
	check(full.add(0,invalid)==0 and full.add(3,pose)==0,"invalid positions and species rejected")
	check(fresh.restore_storage_snapshot(empty) and fresh.bind_world(1704,1) and fresh.profile().placed==0,"explicit empty-world restore clears old edit ownership")
	var filtered=ClassDB.instantiate("NativeGroundCoverState");filtered.bind_world(1703,1)
	var keys:=[]
	for species in [2,0,1]: keys.append(filtered.add(species,Transform3D(Basis.IDENTITY,Vector3(970+species,20,970))))
	var samples: Array[Transform3D]=filtered.sample_transforms(Vector2i(30,30))
	check(samples.size()==3 and samples[0].origin.x==970 and samples[1].origin.x==971 and samples[2].origin.x==972,"authored samples use the same species order as packed queries")
	var source: PackedByteArray=filtered.capture_storage_snapshot()
	var visible: Array=filtered.query_filtered(Vector2i(30,30),PackedByteArray([1,0,0]),PackedByteArray([0,0,1]))
	check(visible.size()==3 and visible[0].ids.is_empty() and visible[2].ids.is_empty() and visible[1].ids==PackedInt64Array([keys[2]]),"structure and water masks exclude exact authored identities")
	check(filtered.capture_storage_snapshot()==source and filtered.query_filtered(Vector2i(30,30),PackedByteArray([0,0,0]),PackedByteArray([0,0,0]))==filtered.query(Vector2i(30,30)),"exclusion preserves durable records and removing exclusion restores originals")
	check(filtered.query_filtered(Vector2i(30,30),PackedByteArray(),PackedByteArray([0,0,0])).is_empty(),"mismatched authored exclusion mask rejects rather than publishing partial data")
	check(filtered.support_points(Vector2i(30,30)).size()==6,"authored support generates two bounded density probes per item")
	check(filtered.support_mask(PackedFloat32Array([-1,1,1,1,-1,-1]),PackedByteArray([0,0,0]))==PackedByteArray([0,1,1]),"support mask distinguishes supported floating and buried placements")
	check(filtered.support_mask(PackedFloat32Array([1,1,1,-1,NAN,1]),PackedByteArray([1,1,1]))==PackedByteArray([0,1,1]),"structure support permits floor placement but not terrain burial or invalid samples")
	check(filtered.support_mask(PackedFloat32Array([1]),PackedByteArray([0])).is_empty(),"partial density reply rejected")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var report:={"checks":checks,"failures":failures}
	var file:=FileAccess.open("res://reports/ground_cover_state.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report));file.close()
	print("GROUND_COVER_STATE ",JSON.stringify(report))
	quit(1 if failures else 0)
