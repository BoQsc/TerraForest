# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize() -> void: call_deferred("run")
func sample(core: RefCounted,p: Vector3) -> PackedByteArray:
	var query:=Codec.point_command(p);query.encode_u32(0,26);return core.execute(query)
func run() -> void:
	var game=load("res://demo/structures.tscn").instantiate();root.add_child(game)
	for prop in game.props: prop.free()
	game.props.clear();game.set_process(false)
	var blank=ClassDB.instantiate("NativeBlockWorld");game.buildings.restore_snapshot(blank.capture_snapshot());blank.free()
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
	# Controlled solid hill above the target grade, on the real density field.
	var center:=Vector3(412,164,400)
	var passed: bool=Codec.reply_ok(core.execute(Codec.brush(center,center,24,1,true,1)))
	for z in [387,413]:
		passed=passed and Codec.reply_ok(core.execute(Codec.graded_bed(Vector3(400,180,z),Vector3(421,180,z),8,8,12,1)))
	passed=passed and Codec.reply_ok(core.execute(Codec.road_bed(Vector3(400,180,400),Vector3(421,180,400),5,8,12)))
	var frontage=ClassDB.instantiate("NativeBlockPrefab")
	passed=passed and frontage.compose_frontage([load("res://addons/structures/prefabs/brick_cottage.tres")],2,8,3,1703)
	var records: PackedInt32Array=frontage.get_records()
	var support_samples:=0;var clearance_samples:=0
	var bad_support:=0;var bad_clearance:=0
	for i in range(0,records.size(),4):
		var p:=Vector3(records[i]+400,records[i+1]+180,records[i+2]+400)
		if records[i+1]==0:
			if sample(core,p-Vector3.UP).decode_float(16)>=0: bad_support+=1
			support_samples+=1
		else:
			if sample(core,p).decode_float(16)<0: bad_clearance+=1
			clearance_samples+=1
	passed=passed and bad_support==0 and bad_clearance==0
	var asphalt: int=sample(core,Vector3(410,179,400)).decode_u32(12)
	var placed: bool=game.buildings.place_prefab(frontage,Vector3i(400,180,400),0,false)
	print("GROUNDING_STAGES ",{"edits_and_support":passed,"asphalt":asphalt,"placed":placed})
	passed=passed and asphalt==4 and placed
	var material=preload("res://addons/volumetric_terrain/runtime_assets.gd").make_terrain_material()
	var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
	for x in [384,400,416,432]:
		for z in [368,384,400,416]:
			for y in [128,160]:
				var decoded: Dictionary=Codec.decode_mesh(core.build_owned_region(x,z,16,1,y,y+32,epoch))
				if decoded.has("error"): print("MESH_ERROR ",decoded);passed=false;continue
				if decoded.arrays[Mesh.ARRAY_VERTEX].is_empty(): continue
				var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,decoded.arrays)
				var visual:=MeshInstance3D.new();visual.mesh=mesh;visual.material_override=material;game.add_child(visual)
	game.camera.position=Vector3(448,209,446);game.camera.look_at(Vector3(410,184,400));game.buildings.set_focus(game.camera.position)
	var deadline:=Time.get_ticks_msec()+15000
	while not game.buildings.is_idle() and Time.get_ticks_msec()<deadline: await process_frame
	passed=passed and game.buildings.is_idle()
	game.label.text="Four cottages on graded terrain\nStone foundations + asphalt street\nControlled hill fixture · visual/correctness check\nNo performance or automatic placement claim"
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/settlement_grounding.png")
	print("SETTLEMENT_GROUNDING ",{"passed":passed,"support_samples":support_samples,"clearance_samples":clearance_samples,"bad_support":bad_support,"bad_clearance":bad_clearance,"cells":frontage.get_cell_count()})
	game.free();quit(0 if passed else 1)
