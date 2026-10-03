# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
	var center:=Vector3(416,172,400)
	core.execute(Codec.brush(center,center,8,1,true,1))
	var query:=Codec.point_command(Vector3(416,179,400));query.encode_u32(0,26)
	var before: PackedByteArray=core.execute(query)
	var outside:=Codec.point_command(Vector3(416,179,407));outside.encode_u32(0,26)
	var outside_before: PackedByteArray=core.execute(outside)
	var road:=Codec.road_bed(Vector3(408,180,400),Vector3(424,180,400),3,4,6)
	var result: PackedByteArray=core.execute(road)
	var after: PackedByteArray=core.execute(query)
	var repeated: PackedByteArray=core.execute(road)
	var passed: bool=Codec.reply_ok(result) and before.decode_u32(12)==1 and after.decode_u32(12)==4 and after.decode_float(16)==before.decode_float(16) and repeated.decode_u32(16)==0
	passed=passed and core.execute(outside)==outside_before
	var saved: PackedByteArray=core.execute(Codec.command(4)).slice(12)
	var restored=ClassDB.instantiate("TerrainCore")
	var packet:=Codec.command(5);packet.append_array(saved)
	passed=passed and Codec.reply_ok(restored.execute(packet)) and restored.execute(query)==after
	print("ROAD_EXISTING_SURFACE ",{"passed":passed,"before_material":before.decode_u32(12),"after_material":after.decode_u32(12),"before_density":before.decode_float(16),"after_density":after.decode_float(16),"repeat_changes":repeated.decode_u32(16)})
	quit(0 if passed else 1)
