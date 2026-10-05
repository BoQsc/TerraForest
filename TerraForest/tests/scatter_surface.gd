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
	var native=ClassDB.instantiate("NativeVegetationScatter")
	var data: Dictionary=native.candidates(Vector2i(12,20),1703,1.0)
	var normals:=PackedVector3Array()
	var expected_ids:=PackedInt64Array()
	var expected: Array[Transform3D]=[]
	var cutoff:=0.5
	for i in range(data.ids.size()):
		data.points[i].y=12.5+i
		normals.append(Vector3(0,0.5 if i%2==0 else 0.49,0))
		if i%2==0:
			expected_ids.append(data.ids[i])
			expected.append(Transform3D(Basis(Vector3.UP,data.rotations[i]).scaled(Vector3.ONE*data.scales[i]),data.points[i]-Vector3(0,.2,0)))
	var result: Dictionary=native.place_surface(data.ids,data.points,normals,data.rotations,data.scales,cutoff)
	check(result.ok and result.ids==expected_ids,"slope threshold accepts equality and rejects below cutoff")
	var exact: bool=result.transforms.size()==expected.size()
	for i in range(expected.size()): exact=exact and result.transforms[i]==expected[i]
	check(exact,"valid placements preserve legacy basis, scale and root offset exactly")
	var original: PackedVector3Array=data.points.duplicate()
	data.points[0]=Vector3(NAN,0,0);normals[2]=Vector3(0,NAN,0)
	result=native.place_surface(data.ids,data.points,normals,data.rotations,data.scales,cutoff)
	check(result.ok and not result.ids.has(data.ids[0]) and not result.ids.has(data.ids[2]) and result.ids.size()==expected.size()-2,"nonfinite support samples are skipped without invalid transforms")
	data.points=original;normals[2]=Vector3.UP
	for field in ["ids","points","rotations","scales"]:
		var malformed: Dictionary=data.duplicate(true);malformed[field].resize(malformed[field].size()-1)
		check(not native.place_surface(malformed.ids,malformed.points,normals,malformed.rotations,malformed.scales,cutoff).ok,"mismatched "+field+" array rejects complete batch")
	var duplicate: PackedInt64Array=data.ids.duplicate();duplicate[1]=duplicate[0]
	check(not native.place_surface(duplicate,data.points,normals,data.rotations,data.scales,cutoff).ok,"duplicate identities reject batch")
	for invalid in [0,-3]:
		duplicate=data.ids.duplicate();duplicate[0]=invalid
		check(not native.place_surface(duplicate,data.points,normals,data.rotations,data.scales,cutoff).ok,"invalid identity rejects batch")
	for invalid in [0.0,-1.0,NAN,INF,11.0]:
		var scales: PackedFloat32Array=data.scales.duplicate();scales[0]=invalid
		check(not native.place_surface(data.ids,data.points,normals,data.rotations,scales,cutoff).ok,"invalid scale rejects batch")
	var rotations: PackedFloat32Array=data.rotations.duplicate();rotations[0]=NAN
	check(not native.place_surface(data.ids,data.points,normals,rotations,data.scales,cutoff).ok,"nonfinite rotation rejects batch")
	for invalid in [-0.1,1.1,NAN,INF]:
		check(not native.place_surface(data.ids,data.points,normals,data.rotations,data.scales,invalid).ok,"invalid slope cutoff rejects batch")
	check(native.place_surface(PackedInt64Array(),PackedVector3Array(),PackedVector3Array(),PackedFloat32Array(),PackedFloat32Array(),cutoff).ok,"empty support batch is valid")
	var oversized:=PackedInt64Array();oversized.resize(4097)
	check(not native.place_surface(oversized,PackedVector3Array(),PackedVector3Array(),PackedFloat32Array(),PackedFloat32Array(),cutoff).ok,"oversized batch rejects before work")
	print("SCATTER_SURFACE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
