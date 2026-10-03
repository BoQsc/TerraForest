# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func seal(data: PackedByteArray) -> PackedByteArray:
	var hash_value:=2166136261
	for i in range(data.size()-4): hash_value=((hash_value^data[i])*16777619)&0xffffffff
	data.encode_u32(data.size()-4,hash_value)
	return data
func load_into(core: RefCounted,data: PackedByteArray) -> bool:
	var packet:=Codec.command(5);packet.append_array(data)
	return Codec.reply_ok(core.execute(packet))
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core: RefCounted=ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6,[1703]))
	core.execute(Codec.brush(Vector3(800,50,1310),Vector3(800,50,1310),2,0,false,1))
	core.execute(Codec.command(3,[805,60,1310,2]))
	var modern: PackedByteArray=core.execute(Codec.command(4)).slice(12)
	check(modern.decode_u32(4)==2 and modern.decode_u32(28)==1,"save explicitly names format 2 and generator 1")
	var key: Dictionary=core.geometry_cache_key(800,1296,16,1)
	check(load_into(core,modern) and core.execute(Codec.command(4)).slice(12)==modern,"versioned edited terrain roundtrips exactly")
	var legacy:=modern.slice(0,28);legacy.append_array(modern.slice(32));legacy.encode_u32(4,1);legacy=seal(legacy)
	check(load_into(core,legacy),"legacy seed-only save remains readable")
	check(core.execute(Codec.command(4)).slice(12)==modern,"legacy migration preserves pages blocks seed and edit metadata")
	check(core.geometry_cache_key(800,1296,16,1)==key,"legacy migration preserves generator cache identity")
	var bad:=modern.duplicate();bad.encode_u32(28,99);bad=seal(bad)
	check(not load_into(core,bad) and core.execute(Codec.command(4)).slice(12)==modern,"unknown generator rejected atomically despite valid checksum")
	bad=modern.duplicate();bad.encode_u32(4,99);bad=seal(bad)
	check(not load_into(core,bad),"unknown save format rejected")
	check(not load_into(core,modern.slice(0,31)),"truncated generator header rejected")
	quit(1 if failures else 0)
