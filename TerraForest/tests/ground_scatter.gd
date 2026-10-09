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
	var scatter=ClassDB.instantiate("NativeGroundCover")
	var wanted: Array=scatter.wanted(Vector2i(30,30))
	check(wanted.size()==49 and wanted[0]==Vector2i(30,30),"bounded nearest-first residency")
	var previous: int=-1
	var ordered:=true
	for cell in wanted:
		var distance: int=(cell-Vector2i(30,30)).length_squared()
		ordered=ordered and distance>=previous
		previous=distance
	check(ordered,"residency distance order")
	check(scatter.wanted(Vector2i(-999999,0)).is_empty(),"far outside world rejects safely")
	check(scatter.wanted(Vector2i.ZERO).size()==16,"world edge clips residency")
	var valid:=true
	var total:=0
	# Every owner uses its own ID interval, so uniqueness is checked without a huge set.
	for z in range(63):
		for x in range(63):
			var cell:=Vector2i(x,z)
			var data: Dictionary=scatter.candidates(cell,1703)
			valid=valid and data.ids.size()<=64 and data.ids.size()==data.points.size()
			var last: int=(z*63+x)*64
			for i in range(data.ids.size()):
				var point: Vector3=data.points[i]
				valid=valid and data.ids[i]>last and data.ids[i]<=(z*63+x+1)*64
				valid=valid and point.x>=2 and point.z>=2 and point.x<1998 and point.z<1998
				valid=valid and floori(point.x/32)==x and floori(point.z/32)==z
				last=data.ids[i]
				total+=1
	check(valid and total>200000,"all world candidates have unique owner identities and bounded positions")
	var data: Dictionary=scatter.candidates(Vector2i(30,30),1703)
	check(data==scatter.candidates(Vector2i(30,30),1703),"regeneration is deterministic")
	var other: Dictionary=scatter.candidates(Vector2i(30,30),1704)
	check(data.ids==other.ids and data.points!=other.points,"seed changes distribution within stable owner namespace")
	check(scatter.candidates(Vector2i(-1,0),1703).ids.is_empty() and scatter.candidates(Vector2i.ZERO,-1).ids.is_empty(),"invalid owner or seed rejected")
	var normals:=PackedVector3Array()
	normals.resize(data.ids.size());normals.fill(Vector3.UP)
	var placed: Dictionary=scatter.place(data.ids,data.points,normals)
	check(placed.ok and placed.ids==data.ids,"valid support preserves individual identities")
	normals[0]=Vector3.ZERO;normals[1]=Vector3(1,0.1,0)*100;normals[2]=Vector3(NAN,0,0)
	var rejected: Dictionary=scatter.place(data.ids,data.points,normals)
	check(rejected.ok and rejected.ids.size()==61 and not rejected.ids.has(data.ids[0]) and not rejected.ids.has(data.ids[1]) and not rejected.ids.has(data.ids[2]),"missing nonfinite and steep support rejected regardless of normal magnitude")
	var duplicate: PackedInt64Array=data.ids.duplicate();duplicate[1]=duplicate[0]
	check(not scatter.place(duplicate,data.points,normals).ok,"duplicate placement identities reject entire batch")
	var state=ClassDB.instantiate("NativeHarvestState")
	check(state.mark(data.ids[5]),"individual procedural removal recorded")
	var fresh=ClassDB.instantiate("NativeHarvestState")
	check(fresh.restore_storage_snapshot(state.capture_storage_snapshot()),"removal snapshot restores into new native state")
	var packed: Array=scatter.pack(placed.ids,placed.transforms,fresh.mask(placed.ids))
	var count:=0
	var correct:=packed.size()==3
	for species in packed:
		count+=species.ids.size()
		correct=correct and not species.ids.has(data.ids[5]) and species.transforms.size()==species.ids.size()*12
		for i in range(species.ids.size()):
			var index: int=placed.ids.find(species.ids[i])
			var t: Transform3D=placed.transforms[index]
			# Independent reference for Godot's row-major MultiMesh buffer.
			var expected: Array=[t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z]
			for j in range(12): correct=correct and is_equal_approx(species.transforms[i*12+j],expected[j])
	check(correct and count==63,"packing keeps neighbours and exact transforms while excluding only removed identity")
	check(scatter.pack(duplicate,placed.transforms,fresh.mask(placed.ids)).is_empty(),"duplicate packed identities rejected")
	var poses: Array[Transform3D]=placed.transforms.duplicate()
	poses[0]=Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)
	check(scatter.pack(placed.ids,poses,fresh.mask(placed.ids)).is_empty(),"singular transform rejected before renderer mutation")
	check(scatter.pack(placed.ids,placed.transforms,PackedByteArray()).is_empty(),"mismatched exclusion mask rejected")
	var report:={"checks":checks,"failures":failures,"world_candidates":total}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/ground_scatter.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report));file.close()
	print("GROUND_SCATTER ",JSON.stringify(report))
	quit(1 if failures else 0)
