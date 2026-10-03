# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func point(data: PackedByteArray,offset: int) -> Vector3:
	return Vector3(data.decode_float(offset),data.decode_float(offset+4),data.decode_float(offset+8))
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core: RefCounted=ClassDB.instantiate("TerrainCore")
	check(Codec.reply_ok(core.execute(Codec.command(6,[2468,2]))),"seeded profile selected")
	var descriptors: PackedByteArray=core.execute(Codec.command(25))
	check(descriptors.size()==24+20*28 and descriptors.decode_u32(12)==2,"four cave networks have bounded 20 capsule representation")
	var key: Dictionary=core.geometry_cache_key(352,352,16,1)
	var saved: PackedByteArray=core.execute(Codec.command(4)).slice(12)
	var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
	for i in range(4):
		var offset:=24+(i*5+2)*28
		var center:=point(descriptors,offset)
		var radius: float=descriptors.decode_float(offset+24)
		var query:=Codec.density_ray_command(center,center+Vector3.UP*(radius+8),256,epoch,true)
		var hit: Dictionary=Codec.decode_density_ray(core.execute(query))
		check(hit.status=="hit" and hit.position.y>center.y+radius-2,"chamber %d has open interior and canonical ceiling"%i)
	core.execute(Codec.command(6,[2468,2]))
	check(core.execute(Codec.command(25))==descriptors,"same seed reproduces complete cave network")
	core.execute(Codec.command(6,[2469,2]))
	check(core.execute(Codec.command(25))!=descriptors,"different seed changes cave routes")
	core.execute(Codec.command(6,[2468,1]))
	check(core.geometry_cache_key(352,352,16,1)!=key,"generator profiles cannot share geometry cache identity")
	var load_packet:=Codec.command(5);load_packet.append_array(saved)
	check(Codec.reply_ok(core.execute(load_packet)) and core.execute(Codec.command(25))==descriptors,"save reload restores generator profile and cave routes")
	check(core.geometry_cache_key(352,352,16,1)==key,"save reload restores exact geometry identity")
	check(not Codec.reply_ok(core.execute(Codec.command(6,[2468,99]))) and core.execute(Codec.command(25))==descriptors,"invalid profile reset leaves world unchanged")
	quit(1 if failures else 0)
