# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failed:=false
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	failed=failed or not ok
func _initialize() -> void:
	var asset=ClassDB.instantiate("NativeBlockPrefab")
	check(asset.configure(PackedInt32Array([-2,3,1,1,-2,8,1,1,2,-1,-3,1])),"stepped and elevated columns accepted")
	var original: PackedVector3Array=asset.foundation_samples(Vector3i(10,20,30),0,3)
	check(original==PackedVector3Array([Vector3(8.5,22.75,31.5),Vector3(12.5,18.75,27.5)]),"lowest cell per column and below-base centre probes")
	check(asset.foundation_samples(Vector3i(10,20,30),1,3)==PackedVector3Array([Vector3(9.5,22.75,28.5),Vector3(13.5,18.75,32.5)]),"rotation follows integer cell placement")
	check(asset.foundation_samples(Vector3i(10,20,30),2,3)==PackedVector3Array([Vector3(12.5,22.75,29.5),Vector3(8.5,18.75,33.5)]),"half turn preserves stepped base heights")
	check(asset.foundation_samples(Vector3i(10,20,30),3,3)==PackedVector3Array([Vector3(11.5,22.75,32.5),Vector3(7.5,18.75,28.5)]),"three quarter turn follows cell-centred convention")
	check(asset.foundation_samples(Vector3i.ZERO,0,-1)==PackedVector3Array([Vector3(2.5,-1.25,-2.5)]),"explicit base band excludes elevated columns")
	check(not asset.configure(PackedInt32Array([0,0,0,1,0,0,0,1])) and asset.foundation_samples(Vector3i(10,20,30),0,3)==original,"rejected configure preserves cached footprint")
	check(asset.foundation_samples(Vector3i.ZERO,4,0).is_empty() and asset.foundation_samples(Vector3i(2147483647,0,0),0,0).is_empty(),"invalid placement rejects without overflow")
	var cottage=load("res://addons/structures/prefabs/brick_cottage.tres")
	check(asset.compose_frontage([cottage],2,8,3,1703),"four cottage frontage composed")
	var probes: PackedVector3Array=asset.foundation_samples(Vector3i.ZERO,0,0)
	var outside_street:=true
	for p in probes: outside_street=outside_street and absf(p.z)>4.0 and p.y==-0.25
	check(probes.size()==396 and outside_street,"frontage retains 396 actual foundation columns without street probes")
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6,[1703,2]))
	core.execute(Codec.brush(Vector3(412,164,400),Vector3(412,164,400),24,1,true,1))
	for z in [387,413]:
		core.execute(Codec.graded_bed(Vector3(400,180,z),Vector3(421,180,z),8,8,12,1))
	var placed_probes: PackedVector3Array=asset.foundation_samples(Vector3i(400,180,400),0,0)
	check(unsupported(core,placed_probes)==0,"actual graded terrain supports all foundation centre probes")
	var hole: Vector3=placed_probes[0]
	core.execute(Codec.brush(hole,hole,2,0,false,1))
	check(unsupported(core,placed_probes)>0,"local excavation exposes unsupported foundation probes")
	check(asset.configure(PackedInt32Array()) and asset.foundation_samples(Vector3i.ZERO,0,0).is_empty(),"empty reconfiguration clears cached footprint")
	quit(1 if failed else 0)
func unsupported(core: RefCounted,probes: PackedVector3Array) -> int:
	var count:=0
	for p in probes:
		var query:=Codec.point_command(p);query.encode_u32(0,26)
		var result: PackedByteArray=core.execute(query)
		if result.size()<20 or result.decode_float(16)>=0: count+=1
	return count
