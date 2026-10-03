# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func vector(data: PackedByteArray,offset: int) -> Vector3:
	return Vector3(data.decode_float(offset),data.decode_float(offset+4),data.decode_float(offset+8))
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
	var core: RefCounted=ClassDB.instantiate("TerrainCore")
	for seed_value: int in [0,1703,2468,2147483647]:
		check(Codec.reply_ok(core.execute(Codec.command(6,[seed_value,4]))),"lake generator accepts seed %d" % seed_value)
		var data: PackedByteArray=core.execute(Codec.command(27))
		check(data.size()==192 and data.decode_u32(12)==4,"four bounded lake definitions")
		if data.size()!=192: quit(1);return
		var saved: PackedByteArray=core.execute(Codec.command(4)).slice(12)
		var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
		for i in 4:
			var offset:=16+i*44
			var volume: RefCounted=ClassDB.instantiate("NativeLakeVolume")
			var seed_point:=vector(data,offset+32)
			check(volume.configure(vector(data,offset),Vector3i(56,16,56),1.0,data.decode_float(offset+28),seed_point),"lake %d definition configures" % i)
			var status:=0
			for slice_index in 64:
				status=volume.sample_terrain(core,2048,0,epoch)
				if status!=0: break
			check(status==1 and volume.contains(seed_point) and volume.depth_at(seed_point)>3.9,"lake %d is closed and contains water" % i)
			check(not volume.contains(seed_point+Vector3(28,0,0)),"lake %d stays inside basin" % i)
			check(not volume.surface_arrays()[Mesh.ARRAY_VERTEX].is_empty(),"lake %d produces water surface" % i)
		core.execute(Codec.command(6,[seed_value,3]))
		check(core.execute(Codec.command(27)).decode_u32(12)==0,"older generator has no implicit lakes")
		var load_packet:=Codec.command(5);load_packet.append_array(saved)
		check(Codec.reply_ok(core.execute(load_packet)) and core.execute(Codec.command(27))==data,"save restores exact basin definitions")
	quit(1 if failures else 0)
