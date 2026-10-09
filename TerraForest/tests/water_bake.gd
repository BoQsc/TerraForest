# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func fresh() -> RefCounted:return ClassDB.instantiate("NativeLakeVolume")
func checksum(bytes: PackedByteArray) -> void:
	var value:=2166136261
	for i in range(16,bytes.size()):value=((value^bytes[i])*16777619)&0xffffffff
	bytes.encode_u32(12,value)
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
	var identity: PackedByteArray="terrain-content-test-v1".sha256_buffer()
	var source:=fresh();source.configure(Vector3.ZERO,Vector3i(8,6,8),1,3.5,Vector3(2.5,2.5,2.5))
	var field:=PackedFloat32Array()
	for z in range(9):
		for y in range(7):
			for x in range(9):field.append(-1.0 if x==0 or x==8 or z==0 or z==8 or y==0 else 1.0)
	check(source.capture_bake(identity).is_empty(),"unfinished builder cannot produce cache")
	check(source.bake_density(field)==1,"enclosed lake bakes")
	var bytes: PackedByteArray=source.capture_bake(identity)
	var restored:=fresh()
	check(restored.restore_bake(bytes,identity),"versioned native bake restores")
	check(restored.capture_bake(identity)==bytes,"deterministic byte round trip")
	check(restored.smooth_surface_arrays()==source.smooth_surface_arrays(),"exact shoreline geometry round trip")
	check(restored.statistics().sampled_nodes==0 and restored.statistics().builder_bytes==0,"restore performs no density sampling and retains no builder buffers")
	var exact:=true
	for z in range(8):
		for y in range(6):
			for x in range(8):
				var point:=Vector3(x,y,z)+Vector3.ONE*0.5
				exact=exact and restored.contains(point)==source.contains(point) and restored.depth_at(point)==source.depth_at(point) and restored.submerges_root(point)==source.submerges_root(point)
	check(exact,"all cell occupancy depth and root exclusions match")
	check(not restored.restore_bake(bytes,identity) and restored.capture_bake(identity)==bytes,"published volume immutable")
	check(not fresh().restore_bake(bytes,"changed-terrain".sha256_buffer()),"terrain identity mismatch rejected")
	for offset in [0,4,8,12,16,48,60,72,76,80,92,96,100,104,bytes.size()-1]:
		var corrupt:=bytes.duplicate();corrupt[offset]^=1
		var target:=fresh()
		check(not target.restore_bake(corrupt,identity) and target.restore_bake(bytes,identity),"corruption rejects without poisoning fresh instance at %d"%offset)
	var truncated:=bytes.slice(0,bytes.size()-1)
	check(not fresh().restore_bake(truncated,identity),"truncation rejected")
	var trailing:=bytes.duplicate();trailing.append(0)
	check(not fresh().restore_bake(trailing,identity),"trailing data rejected")
	var invalid:=bytes.duplicate();invalid[104]=1;checksum(invalid)
	check(not fresh().restore_bake(invalid,identity),"checksummed boundary occupancy rejected")
	invalid=bytes.duplicate();invalid.encode_float(72,NAN);checksum(invalid)
	check(not fresh().restore_bake(invalid,identity),"checksummed nonfinite dimensions rejected")
	invalid=bytes.duplicate();invalid.encode_u32(invalid.size()-4,0xffffffff);checksum(invalid)
	check(not fresh().restore_bake(invalid,identity),"checksummed invalid mesh index rejected")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var f:=FileAccess.open("res://reports/water_bake.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures,"bytes":bytes.size(),"scope":"Native codec only; worker cache admission, terrain identity derivation, disk lifecycle and main-world reuse not yet connected."},"  "));f.close();quit(1 if failures else 0)
