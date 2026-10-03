# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func density(core: RefCounted,p: Vector3) -> float:
	var query:=Codec.point_command(p);query.encode_u32(0,26);return core.execute(query).decode_float(16)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
	var a:=Vector3(400,180,400);var b:=Vector3(432,180,400)
	var packet:=Codec.graded_bed(a,b,4,8,12,1);packet.resize(48);packet.encode_float(44,8)
	var outside:=density(core,Vector3(416,176,424))
	check(Codec.reply_ok(core.execute(packet)),"sloped fill packet accepted")
	check(density(core,Vector3(416,179,400))<0 and density(core,Vector3(416,181,400))>0,"flat central grade retained")
	check(density(core,Vector3(416,177,406))<0 and density(core,Vector3(416,179,406))>0,"inner shoulder tapers below platform height")
	check(density(core,Vector3(416,173,410))<0 and density(core,Vector3(416,175,410))>0,"outer shoulder descends toward bounded fill bottom")
	check(density(core,Vector3(392,175,400))<0 and density(core,Vector3(392,177,400))>0,"capsule end also tapers")
	check(density(core,Vector3(416,176,424))==outside,"outside expanded footprint unchanged")
	check(core.execute(packet).decode_u32(16)==0,"repeated shoulder grading is idempotent")
	var saved: PackedByteArray=core.execute(Codec.command(4))
	for shoulder in [-1.0,17.0,NAN]:
		var bad:=packet.duplicate();bad.encode_float(44,shoulder)
		check(not Codec.reply_ok(core.execute(bad)) and core.execute(Codec.command(4))==saved,"invalid shoulder preserves world")
	var terrain=preload("res://addons/volumetric_terrain/terrain_world.gd").new();terrain.diagnostics_pause_streaming=true;terrain.backend.world_generator=2;root.add_child(terrain)
	terrain.start(StandardMaterial3D.new(),true)
	var deadline:=Time.get_ticks_msec()+30000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(terrain.world_ready and terrain.construct_graded_bed(a,b,4,8,12,1,8),"expanded grading admitted through worker facade")
	deadline=Time.get_ticks_msec()+10000
	while terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
	check(not terrain.pending_edit and terrain.latest_error.is_empty(),"shoulder publishes through edit lifecycle")
	terrain.shutdown();terrain.free();quit(1 if failures else 0)
