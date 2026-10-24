# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,3]))
	for material:int in [1,8,9,10]:
		var point:=Vector3(800+material*8,130,1310)
		var stamp:=Codec.command(38,[int(point.x),int(point.y),int(point.z),material])
		var reply:PackedByteArray=core.execute(stamp)
		check(Codec.reply_ok(reply) and reply.decode_u32(16)>0,"native terrain material %d stamps"%material)
		var revision:int=reply.decode_u32(12)
		check(core.execute(stamp).decode_u32(12)==revision,"occupied stamp cannot repaint or deepen terrain")
		var query:=Codec.point_command(point);query.encode_u32(0,26)
		check(core.execute(query).decode_u32(12)==material,"placed terrain retains material identity")
		var saved:PackedByteArray=core.execute(Codec.command(4)).slice(12)
		var restore:=Codec.command(5);restore.append_array(saved)
		check(Codec.reply_ok(core.execute(restore)),"native density/material binary roundtrip")
		var removed:PackedInt64Array=Codec.excavation_samples(core.execute(Codec.brush(point,point,2,0,false,1)))
		var total:=0
		for count:int in removed:total+=count
		check(total==1 and removed[material]==1,"re-mining %d recovers one unit, never more"%material)
	var inv:RefCounted=ClassDB.instantiate("NativePlayerInventory");inv.register_item(501,1);inv.register_durable(501,300)
	check(inv.grant_durable(501,73,0).ok and inv.snapshot().slots[0].wear==73,"native carried vehicle retains damage")
	var before:PackedByteArray=inv.capture_storage_snapshot()
	check(not inv.grant_durable(501,300,inv.snapshot().revision).ok and inv.capture_storage_snapshot()==before,"invalid vehicle damage cannot create an item")
	var health:RefCounted=ClassDB.instantiate("NativeWorldDurability")
	health.hit("vehicle:1",300,73)
	check(health.repair("vehicle:1",300,25).remaining==252 and health.damage("vehicle:1",300)==48,"repair restores bounded native durability")
	health.repair("vehicle:1",300,100)
	check(health.record_count()==0 and not health.repair("vehicle:1",300,25).ok,"full repair releases sparse record and cannot repeat")
	print("TERRAIN_MATERIAL_ITEMS failures=",failures);quit(1 if failures else 0)
