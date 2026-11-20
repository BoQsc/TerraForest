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
var last_edit_profile:Dictionary={}
# The trusted operator has one ordered request stream. Publish its last
# committed receipt in the same archive transaction as terrain and water.
var operator_receipt:=PackedByteArray()
const RECEIPT_SECTION:="operator_receipt"
const RECEIPT_SIZE:=36

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
		if not sections.has("volumetric_water") or sections.size()!=(3 if sections.has(RECEIPT_SECTION) else 2):return false
		var load_packet:=Codec.command(5)
		load_packet.append_array(sections.terrain)
		if not Codec.reply_ok(core.execute(load_packet)) or not water.restore_snapshot(sections.volumetric_water):return false
		catalog=water.snapshot_catalog(sections.volumetric_water)
		if sections.has(RECEIPT_SECTION):
			var receipt:PackedByteArray=sections[RECEIPT_SECTION]
			if receipt.size()!=RECEIPT_SIZE or receipt.decode_u32(0)!=1 or receipt.decode_u32(4)==0:return false
			var before:=receipt.decode_u32(8)
			var after:=receipt.decode_u32(12)
			if after<before or after>before+1 or after>revision():return false
			if not valid_brush(receipt_point(receipt),receipt.decode_double(28)):return false
			operator_receipt=receipt
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
	var sections:={"terrain":terrain.slice(12),"volumetric_water":liquid}
	if not operator_receipt.is_empty():sections[RECEIPT_SECTION]=operator_receipt
	var payload:PackedByteArray=archive.encode(sections)
	return not payload.is_empty() and archive.publish(path,payload)==OK

const MAX_QUERY_POINTS:=8

func _sample_point(point:Vector3)->Dictionary:
	if not point.is_finite():return {"ok":false,"reason":"Invalid position"}
	var data:PackedByteArray=core.execute(Codec.point_command(point))
	if not Codec.reply_ok(data) or data.size()<20:return {"ok":false}
	return {"ok":true,"height":data.decode_float(12),"density":data.decode_float(16),"depth":water.depth_at(point)}

func sample(point:Vector3)->Dictionary:
	if not healthy:return {"ok":false,"reason":"World unavailable"}
	var result:=_sample_point(point)
	if result.ok:
		result.revision=revision()
		result.water_ml=water.total_water_ml()
	return result

func sample_points(points:PackedVector3Array)->Dictionary:
	if not healthy:return {"ok":false,"reason":"World unavailable"}
	if points.is_empty() or points.size()>MAX_QUERY_POINTS:return {"ok":false,"reason":"Invalid point count"}
	var rows:Array[Dictionary]=[]
	for point:Vector3 in points:
		if point!=point.clamp(Vector3.ZERO,Vector3(2000,256,2000)):return {"ok":false,"reason":"Outside world"}
		var row:=_sample_point(point)
		if not row.ok:return row
		row.erase("ok")
		rows.append(row)
	# The authority serializes commands. Every sample belongs to this revision.
	return {"ok":true,"version":1,"revision":revision(),"water_ml":water.total_water_ml(),"samples":rows}

signal edit_committed(revision:int,bounds:AABB)

func last_request_id()->int:
	return 0 if operator_receipt.is_empty() else operator_receipt.decode_u32(4)

static func receipt_point(receipt:PackedByteArray)->Vector3:
	return Vector3(receipt.decode_float(16),receipt.decode_float(20),receipt.decode_float(24))

static func valid_brush(point:Vector3,radius:float)->bool:
	if not point.is_finite() or not is_finite(radius) or radius<=0 or radius>8:return false
	return AABB(Vector3.ZERO,Vector3(2000,256,2000)).encloses(AABB(point-Vector3.ONE*radius,Vector3.ONE*radius*2))

func receipt_reply()->Dictionary:
	return {"ok":true,"version":1,"request_id":last_request_id(),"revision":operator_receipt.decode_u32(12),"changed":operator_receipt.decode_u32(8)!=operator_receipt.decode_u32(12)}

func excavate(point:Vector3,radius:float,expected:int,request_id:int=0)->Dictionary:
	if not healthy:return {"ok":false,"reason":"World unavailable"}
	if not valid_brush(point,radius):return {"ok":false,"reason":"Invalid brush bounds"}
	if request_id!=0:
		var last:=last_request_id()
		if request_id==last:
			if expected==operator_receipt.decode_u32(8) and point==receipt_point(operator_receipt) and radius==operator_receipt.decode_double(28):return receipt_reply()
			return {"ok":false,"reason":"Request ID already committed with different arguments"}
		if request_id!=last+1 or request_id>0xffffffff:return {"ok":false,"reason":"Unexpected request ID"}
	if expected!=revision():return {"ok":false,"reason":"Stale revision"}
	var bounds:=AABB(point-Vector3.ONE*radius,Vector3.ONE*radius*2)
	var packet:=Codec.brush(point,point,radius,0,false,1)
	var began:=Time.get_ticks_usec()
	var edit:=EditCommands.execute(core,[packet],expected)
	if not Codec.reply_ok(edit.reply):return {"ok":false,"reason":"Terrain rejected brush"}
	last_edit_profile={"terrain_us":Time.get_ticks_usec()-began,"invalidate_us":0,"patch_us":0,"patches":0,"solve_us":0,"commit_us":0,"capture_us":0,"solves":0,"solve_phases_us":[0,0,0,0,0,0,0,0]}
	if edit.changed[0]:
		var started:=Time.get_ticks_usec()
		water.invalidate(bounds)
		water.settle_after_edit(bounds)
		last_edit_profile.invalidate_us=Time.get_ticks_usec()-started
		healthy=_resolve_water()
	if not healthy:return {"ok":false,"reason":"Water commit failed; reload the last saved revision"}
	if request_id!=0:
		operator_receipt.resize(RECEIPT_SIZE)
		operator_receipt.encode_u32(0,1)
		operator_receipt.encode_u32(4,request_id)
		operator_receipt.encode_u32(8,expected)
		operator_receipt.encode_u32(12,revision())
		operator_receipt.encode_float(16,point.x)
		operator_receipt.encode_float(20,point.y)
		operator_receipt.encode_float(24,point.z)
		operator_receipt.encode_double(28,radius)
	var response:=receipt_reply() if request_id!=0 else sample(point)
	last_edit_profile.total_us=Time.get_ticks_usec()-began
	if edit.changed[0]:
		edit_committed.emit(revision(),bounds)
	return response

func _resolve_water()->bool:
	var deadline:=Time.get_ticks_msec()+30000
	var rev:=revision()
	var generation:=epoch()
	while Time.get_ticks_msec()<deadline:
		var request:Dictionary=water.next_request()
		if not request.is_empty():
			var started:=Time.get_ticks_usec()
			var patch:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
			if not patch.configure(request.coordinate):return false
			var status:=0
			while status==0 and Time.get_ticks_msec()<deadline:
				status=patch.sample_terrain(core,2048,rev,generation)
			if status!=1 or not water.accept_patch(patch):return false
			last_edit_profile.patch_us+=Time.get_ticks_usec()-started
			last_edit_profile.patches+=1
		elif water.runtime_state().settling_regions==0:
			return true
		else:
			var started:=Time.get_ticks_usec()
			var job:RefCounted=water.begin_equilibrium()
			last_edit_profile.capture_us+=Time.get_ticks_usec()-started
			if job!=null:
				started=Time.get_ticks_usec()
				job.prepare()
				last_edit_profile.solve_us+=Time.get_ticks_usec()-started
				started=Time.get_ticks_usec()
				var result:Dictionary=water.finish_equilibrium(job)
				last_edit_profile.commit_us+=Time.get_ticks_usec()-started
				if not result.get("ok",false):return false
				last_edit_profile.solves+=1
				for index in result.phase_us.size():
					last_edit_profile.solve_phases_us[index]+=result.phase_us[index]
	return false
