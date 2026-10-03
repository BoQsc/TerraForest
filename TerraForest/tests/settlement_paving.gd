# SPDX-License-Identifier: 0BSD
extends SceneTree
const Plan=preload("res://addons/structures/site_plan.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var asset=ClassDB.instantiate("NativeBlockPrefab")
	asset.compose_frontage([load("res://addons/structures/prefabs/brick_cottage.tres")],2,8,3,1703)
	asset.set_meta("frontage_version",1);asset.set_meta("street_width",8)
	for rotation in 4:
		var plan: Dictionary=Plan.prepare(asset,Vector3i(700,0,700),rotation,80)
		check(plan.ok and plan.paving_segments>0,"rotated frontage includes paving "+str(rotation))
		if not plan.ok: continue
		var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
		var ordered:=true;var asphalt:=false;var accepted:=true
		for segment: Dictionary in plan.segments:
			if segment.material==4: asphalt=true
			elif asphalt: ordered=false
			var packet:=Codec.graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material)
			packet.resize(48);packet.encode_float(44,segment.shoulder)
			accepted=Codec.reply_ok(core.execute(packet)) and accepted
		check(ordered and accepted,"stone grading precedes accepted native asphalt edits "+str(rotation))
		var point:=Vector3(10,0,0)
		for turn in rotation: point=Vector3(1-point.z,0,point.x)
		point+=Vector3(700,79,700)
		var query:=Codec.point_command(point);query.encode_u32(0,26)
		var result: PackedByteArray=core.execute(query)
		check(Codec.reply_ok(result) and result.decode_u32(12)==4 and result.decode_float(16)<0,"rotated street has solid native asphalt material "+str(rotation))
		var ends: PackedVector3Array=plan.street_ends
		var entrances_paved:=ends.size()==2 and ends[0].y==80 and ends[1].y==80
		for entrance in ends:
			query=Codec.point_command(entrance-Vector3.UP);query.encode_u32(0,26)
			result=core.execute(query)
			entrances_paved=entrances_paved and Codec.reply_ok(result) and result.decode_u32(12)==4 and result.decode_float(16)<0
		check(entrances_paved,"captured street entrances match real rotated asphalt "+str(rotation))
		var end: Vector3=ends[1]+(ends[1]-ends[0]).normalized()*16
		check(Codec.reply_ok(core.execute(Codec.graded_bed(ends[1],end,4,8,12,4))),"connecting road accepted at captured endpoint "+str(rotation))
		query=Codec.point_command(ends[1].lerp(end,0.5)-Vector3.UP);query.encode_u32(0,26);result=core.execute(query)
		check(Codec.reply_ok(result) and result.decode_u32(12)==4 and result.decode_float(16)<0,"connector extends asphalt outside original street "+str(rotation))
	asset.set_meta("street_width",64)
	check(not Plan.prepare(asset,Vector3i(700,0,700),0,80).ok,"street metadata cannot pave through actual foundation columns")
	asset.compose_frontage([load("res://addons/structures/prefabs/brick_cottage.tres")],2,64,3,1703)
	var wide: Dictionary=Plan.prepare(asset,Vector3i(700,0,700),0,80)
	check(wide.ok and wide.paving_segments==3,"64 m street splits into native-width strips")
	asset.set_meta("street_width",65)
	check(not Plan.prepare(asset,Vector3i(700,0,700),0,80).ok,"invalid street metadata rejects rather than guessing")
	asset.remove_meta("frontage_version")
	check(Plan.prepare(asset,Vector3i(700,0,700),0,80).paving_segments==0,"ordinary prefab does not acquire an invented street")
	quit(1 if failures else 0)
