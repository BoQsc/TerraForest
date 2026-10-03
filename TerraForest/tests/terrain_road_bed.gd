# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func density(core: RefCounted,point: Vector3) -> float:
	return core.execute(Codec.point_command(point)).decode_float(16)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core: RefCounted=ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6,[1703,2]))
	var a:=Vector3(400,180,400);var b:=Vector3(432,184,400)
	var packet:=Codec.road_bed(a,b,3,4)
	var outside:=density(core,Vector3(416,181,409))
	check(Codec.reply_ok(core.execute(packet)),"graded volumetric bed accepted")
	check(density(core,Vector3(416,181,400))<0 and density(core,Vector3(416,184,400))>0 and density(core,Vector3(416,177,400))>0,"bed has solid interior and bounded top and bottom")
	check(absf(density(core,Vector3(416,182,400)))<0.001,"top follows endpoint grade at midpoint")
	check(density(core,Vector3(416,181,409))==outside,"outside field remains unchanged")
	check(core.execute(packet).decode_u32(16)==0,"repeated identical bed is idempotent")
	var saved: PackedByteArray=core.execute(Codec.command(4)).slice(12)
	for bad: PackedByteArray in [Codec.road_bed(a,a,3,4),Codec.road_bed(a,b,3,NAN),Codec.road_bed(a,b+Vector3(0,20,0),3,4),Codec.road_bed(Vector3.ZERO,b,3,4),Codec.road_bed(a,b,17,4)]:
		check(not Codec.reply_ok(core.execute(bad)) and core.execute(Codec.command(4)).slice(12)==saved,"invalid road geometry rejected without mutation")
	var restored: RefCounted=ClassDB.instantiate("TerrainCore")
	var load_packet:=Codec.command(5);load_packet.append_array(saved)
	check(Codec.reply_ok(restored.execute(load_packet)) and restored.execute(Codec.command(4)).slice(12)==saved,"bed density survives existing terrain snapshot format")
	check(Codec.reply_ok(core.execute(Codec.brush(Vector3(416,181,400),Vector3(416,181,400),1.5,0,false,1))) and density(core,Vector3(416,181,400))>0,"ordinary mining edits road volume")
	var epoch: int=restored.execute(Codec.command(13)).decode_u32(12)
	var mesh: Dictionary=Codec.decode_mesh(restored.build_owned_region(400,400,16,1,160,192,epoch))
	check(not mesh.has("error") and not mesh.arrays[Mesh.ARRAY_VERTEX].is_empty(),"bed uses existing native terrain meshing")
	var asphalt_vertices:=0
	var weights: PackedColorArray=mesh.arrays[Mesh.ARRAY_COLOR]
	var channels: PackedVector2Array=mesh.arrays[Mesh.ARRAY_TEX_UV2]
	var valid_weights:=true
	for i in channels.size():
		var asphalt: float=(channels[i].y-floorf(channels[i].y))*4.0
		if asphalt>0.9: asphalt_vertices+=1
		valid_weights=valid_weights and floorf(channels[i].y)==1 and asphalt>=0 and asphalt<=1 and weights[i].r+weights[i].g+weights[i].b+asphalt<=1.0001
	check(asphalt_vertices>20 and valid_weights,"saved asphalt reaches mesh as normalized continuous weights with LOD preserved")
	var terrain:=preload("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.diagnostics_pause_streaming=true;terrain.backend.world_generator=2;root.add_child(terrain)
	terrain.start(StandardMaterial3D.new(),true)
	var deadline:=Time.get_ticks_msec()+10000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(terrain.world_ready and terrain.construct_road_bed(a,b,3,4),"public road API submits through terrain worker")
	deadline=Time.get_ticks_msec()+10000
	while terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
	check(not terrain.pending_edit and terrain.latest_error.is_empty(),"road edit completes through existing publication lifecycle")
	terrain.shutdown();terrain.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/terrain_road_bed.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"scope":"graded asphalt density volume, native material weights, mesh, save format, mining and worker routing; no road editor or network"}));file.close()
	quit(1 if failures else 0)
