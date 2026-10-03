# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func sample(core: RefCounted,p: Vector3) -> PackedByteArray:
	var query:=Codec.point_command(p);query.encode_u32(0,26)
	return core.execute(query)
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
	var a:=Vector3(400,180,400);var b:=Vector3(432,180,400)
	var bed:=Codec.graded_bed(a,b,12,4,12,3)
	check(Codec.reply_ok(core.execute(bed)),"wide foundation grading accepted")
	check(sample(core,Vector3(416,179,408)).decode_u32(12)==3 and sample(core,Vector3(416,179,408)).decode_float(16)<0,"foundation uses selected solid material")
	var before: PackedByteArray=sample(core,Vector3(416,179,400))
	check(Codec.reply_ok(core.execute(Codec.road_bed(a,b,4,4,12))),"asphalt street stamps over graded foundation")
	var after: PackedByteArray=sample(core,Vector3(416,179,400))
	check(after.decode_u32(12)==4 and before.decode_float(16)==after.decode_float(16),"street changes material without changing established grade")
	check(sample(core,Vector3(416,179,408)).decode_u32(12)==3,"paving preserves foundation material outside street")
	var saved: PackedByteArray=core.execute(Codec.command(4)).slice(12)
	for material in [0,5,4294967295]:
		check(not Codec.reply_ok(core.execute(Codec.graded_bed(a,b,12,4,12,material))) and core.execute(Codec.command(4)).slice(12)==saved,"invalid grading material rejected without mutation")
	var restored=ClassDB.instantiate("TerrainCore");var packet:=Codec.command(5);packet.append_array(saved)
	check(Codec.reply_ok(restored.execute(packet)) and sample(restored,Vector3(416,179,400))==after and sample(restored,Vector3(416,179,408)).decode_u32(12)==3,"foundation and street survive terrain snapshot")
	var terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	check(terrain.has_method("construct_graded_bed") and not terrain.construct_graded_bed(a,b,12,4,12,0),"public grading API rejects invalid material before worker submission")
	terrain.free();quit(0 if failures==0 else 1)
