# SPDX-License-Identifier: 0BSD
extends RefCounted
## Single-writer local authority for terrain and finite inland lakes.
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const EditCommands=preload("res://addons/volumetric_terrain/terrain_edit_commands.gd")
const Lakes=preload("res://addons/volumetric_terrain/generated_lakes.gd")
var core:RefCounted
var water:RefCounted
var archive:RefCounted
var catalog:PackedByteArray
var path:String
var healthy:=false

func open(slot:String)->bool:
	if not slot.is_valid_identifier() or slot.length()>64:return false
	var directory:=ProjectSettings.globalize_path("user://authority")
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return false
	path=directory.path_join(slot+".trw")
	archive=ClassDB.instantiate("NativeWorldArchive")
	if archive==null or not archive.acquire(path):return false
	core=ClassDB.instantiate("TerrainCore")
	water=ClassDB.instantiate("NativeRegionalWater")
	if core==null or water==null:return false
	if FileAccess.file_exists(path):
		var decoded:Dictionary=archive.decode(archive.read(path))
		if not decoded.get("ok",false):return false
		var sections:Dictionary=decoded.sections
		# A host that does not own structure collision or region sidecars cannot
		# safely edit such a save. Never rewrite it as a terrain-only archive.
		if sections.size()!=2 or not sections.has("volumetric_water"):return false
		var load_packet:=Codec.command(5)
		load_packet.append_array(sections.terrain)
		if not Codec.reply_ok(core.execute(load_packet)) or not water.restore_snapshot(sections.volumetric_water):return false
		catalog=water.snapshot_catalog(sections.volumetric_water)
	else:
		const GENERATOR:=17
		if not Codec.reply_ok(core.execute(Codec.command(6,[1703,GENERATOR]))):return false
		var definitions:=Lakes.describe(core,GENERATOR)
		if not definitions.get("ok",false):return false
		catalog=ClassDB.instantiate("NativeLakeCatalog").encode(definitions.records)
		var bake:Dictionary=ClassDB.instantiate("NativeGeneratedLakeBake").run(core,catalog,revision(),epoch(),60000)
		if not bake.get("ok",false) or not water.restore_snapshot(bake.snapshot):return false
	healthy=not catalog.is_empty()
	return healthy

func revision()->int:return core.execute(Codec.command(0)).decode_u32(12)
func epoch()->int:return core.execute(Codec.command(13)).decode_u32(12)

func save()->bool:
	if not healthy:return false
	var terrain:PackedByteArray=core.execute(Codec.command(4,[3]))
	if not Codec.reply_ok(terrain):return false
	var liquid:PackedByteArray=water.capture_streaming_snapshot(catalog)
	if liquid.is_empty():return false
	var payload:PackedByteArray=archive.encode({"terrain":terrain.slice(12),"volumetric_water":liquid})
	return not payload.is_empty() and archive.publish(path,payload)==OK

func sample(point:Vector3)->Dictionary:
	if not healthy or not point.is_finite():return {"ok":false,"reason":"World unavailable"}
	var data:PackedByteArray=core.execute(Codec.point_command(point))
	if not Codec.reply_ok(data) or data.size()<20:return {"ok":false}
	return {"ok":true,"revision":revision(),"height":data.decode_float(12),"density":data.decode_float(16),"depth":water.depth_at(point),"water_ml":water.statistics().water_ml}

signal edit_committed(revision:int,bounds:AABB)

func excavate(point:Vector3,radius:float,expected:int)->Dictionary:
	if not healthy or expected!=revision():return {"ok":false,"reason":"Unavailable or stale revision"}
	if not point.is_finite() or not is_finite(radius) or radius<=0 or radius>8:return {"ok":false,"reason":"Invalid brush"}
	var bounds:=AABB(point-Vector3.ONE*radius,Vector3.ONE*radius*2)
	if not AABB(Vector3.ZERO,Vector3(2000,256,2000)).encloses(bounds):return {"ok":false,"reason":"Outside world"}
	var packet:=Codec.brush(point,point,radius,0,false,1)
	var edit:=EditCommands.execute(core,[packet],expected)
	if not Codec.reply_ok(edit.reply):return {"ok":false,"reason":"Terrain rejected brush"}
	if edit.changed[0]:
		water.invalidate(bounds)
		water.settle_after_edit(bounds)
		healthy=_resolve_water()
	if not healthy:return {"ok":false,"reason":"Water commit failed; reload the last saved revision"}
	if edit.changed[0]:
		edit_committed.emit(revision(),bounds)
	return sample(point)

func _resolve_water()->bool:
	var deadline:=Time.get_ticks_msec()+30000
	var rev:=revision()
	var generation:=epoch()
	while Time.get_ticks_msec()<deadline:
		var request:Dictionary=water.next_request()
		if not request.is_empty():
			var patch:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
			if not patch.configure(request.coordinate):return false
			var status:=0
			while status==0 and Time.get_ticks_msec()<deadline:
				status=patch.sample_terrain(core,2048,rev,generation)
			if status!=1 or not water.accept_patch(patch):return false
		elif water.runtime_state().settling_regions==0:
			return true
		else:
			var job:RefCounted=water.begin_equilibrium()
			if job!=null:
				job.prepare()
				if not water.finish_equilibrium(job).get("ok",false):return false
	return false
