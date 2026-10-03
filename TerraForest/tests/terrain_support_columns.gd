# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func query(core: RefCounted,points: PackedVector3Array,depth: int,revision: int) -> PackedByteArray:
	var p:=Codec.command(30,[revision,points.size(),depth]);p.append_array(points.to_byte_array());return core.execute(p)
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
	core.execute(Codec.brush(Vector3(400,175,400),Vector3(400,175,400),10,1,true,1))
	var revision: int=core.execute(Codec.command(0)).decode_u32(12)
	var points:=PackedVector3Array([Vector3(400.5,179.75,400.5)])
	check(query(core,points,8,revision).decode_float(20)<0,"solid column accepted")
	core.execute(Codec.brush(Vector3(400,175,400),Vector3(400,175,400),1,0,false,1))
	revision=core.execute(Codec.command(0)).decode_u32(12)
	check(query(core,points,8,revision).decode_float(20)>0,"intermediate air pocket detected")
	check(query(core,points,0,revision).decode_float(20)<0 and query(core,PackedVector3Array([Vector3(400.5,171.75,400.5)]),0,revision).decode_float(20)<0,"two endpoint probes would miss the pocket")
	check(not Codec.reply_ok(query(core,points,9,revision)) and not Codec.reply_ok(query(core,points,8,revision-1)),"invalid depth and stale revision rejected")
	var many:=PackedVector3Array();many.resize(512);many.fill(Vector3(400,179,400))
	var start:=Time.get_ticks_usec();var result:=query(core,many,8,revision)
	print("SUPPORT_COLUMN_512_US ",Time.get_ticks_usec()-start)
	check(Codec.reply_ok(result) and result.size()==2068,"maximum batch has bounded reply size")
	check(query(core,PackedVector3Array([Vector3(400,3.75,400)]),8,revision).decode_float(20)<0,"low-altitude scan stops at protected bedrock")
	quit(1 if failures else 0)
