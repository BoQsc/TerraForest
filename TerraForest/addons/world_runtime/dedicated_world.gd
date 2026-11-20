# SPDX-License-Identifier: 0BSD
extends RefCounted
## Single-writer local authority for terrain and finite inland lakes.
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const EditCommands=preload("res://addons/volumetric_terrain/terrain_edit_commands.gd")
const Lakes=preload("res://addons/volumetric_terrain/generated_lakes.gd")
const ItemCatalog=preload("res://addons/player_runtime/item_catalog.gd")
var inventory:RefCounted
var core:RefCounted
var water:RefCounted
var archive:RefCounted
var catalog:PackedByteArray
var path:String
var healthy:=false
var last_edit_profile:Dictionary={}
var occupancy_patch:RefCounted
var occupancy_coordinate:=Vector3i.ZERO
var occupancy_revision:=-1
var occupancy_epoch:=-1
# Requests are ordered. A bounded reply history covers delayed retries and
# is checkpointed with terrain and water. Older IDs can never execute again.
const RECEIPT_WINDOW:=32
var operator_receipts:Array[PackedByteArray]=[]
const RECEIPT_SECTION:="operator_receipt"
const RECEIPT_SIZE:=36
const SCOOP:=2
const POUR:=258
const BUCKET_RECEIPT_SIZE:=80

func open(slot:String)->bool:
	if not slot.is_valid_identifier() or slot.length()>64:return false
	var directory:=ProjectSettings.globalize_path("user://authority")
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return false
	path=directory.path_join(slot+".trw")
	archive=ClassDB.instantiate("NativeWorldArchive")
	if archive==null or not archive.acquire(path):return false
	core=ClassDB.instantiate("TerrainCore")
	water=ClassDB.instantiate("NativeRegionalWater")
	inventory=ItemCatalog.create_inventory()
	if core==null or water==null or inventory==null:return false
	var has_loadout:=false
	if FileAccess.file_exists(path):
		var decoded:Dictionary=archive.decode(archive.read(path))
		if not decoded.get("ok",false):return false
		var sections:Dictionary=decoded.sections
		# A host that does not own structure collision or region sidecars cannot
		# safely edit such a save. Never rewrite it as a terrain-only archive.
		for section in sections:
			if section not in ["terrain","volumetric_water","player_loadout",RECEIPT_SECTION]:return false
		if not sections.has("terrain") or not sections.has("volumetric_water"):return false
		has_loadout=sections.has("player_loadout")
		if has_loadout and not inventory.restore_storage_snapshot(sections.player_loadout):return false
		var load_packet:=Codec.command(5)
		load_packet.append_array(sections.terrain)
		if not Codec.reply_ok(core.execute(load_packet)) or not water.restore_snapshot(sections.volumetric_water):return false
		catalog=water.snapshot_catalog(sections.volumetric_water)
		if sections.has(RECEIPT_SECTION) and not restore_receipts(sections[RECEIPT_SECTION]):return false
	else:
		const GENERATOR:=17
		if not Codec.reply_ok(core.execute(Codec.command(6,[1703,GENERATOR]))):return false
		var definitions:=Lakes.describe(core,GENERATOR)
		if not definitions.get("ok",false):return false
		catalog=ClassDB.instantiate("NativeLakeCatalog").encode(definitions.records)
		var bake:Dictionary=ClassDB.instantiate("NativeGeneratedLakeBake").run(core,catalog,revision(),epoch(),60000)
		if not bake.get("ok",false) or not water.restore_snapshot(bake.snapshot):return false
	if not has_loadout and not ItemCatalog.grant_starter_loadout(inventory,true):return false
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
	var sections:={"terrain":terrain.slice(12),"volumetric_water":liquid,"player_loadout":inventory.capture_storage_snapshot()}
	if not operator_receipts.is_empty():
		var history:=PackedByteArray()
		for receipt in operator_receipts:history.append_array(receipt)
		sections[RECEIPT_SECTION]=history
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

static func valid_bucket_ray(origin:Vector3,end:Vector3)->bool:
	var extent:=Vector3(2000,256,2000)
	for point:Vector3 in [origin,end]:
		if not point.is_finite() or point!=point.clamp(Vector3.ZERO,extent):return false
	var distance_squared:=origin.distance_squared_to(end)
	return distance_squared>=1e-12 and distance_squared<=25

func water_surface(origin:Vector3,end:Vector3)->Dictionary:
	if not healthy:return {"ok":false,"reason":"World unavailable"}
	if not valid_bucket_ray(origin,end):return {"ok":false,"reason":"Invalid bucket reach"}
	var surface:Dictionary=water.raycast_surface(origin,end)
	var reply:={"ok":true,"version":1,"revision":revision(),"hit":surface.hit}
	if surface.hit:
		var point:Vector3=surface.point
		var normal:Vector3=surface.normal
		var cell:Vector3i=surface.cell
		reply.point=[point.x,point.y,point.z]
		reply.normal=[normal.x,normal.y,normal.z]
		reply.cell=[cell.x,cell.y,cell.z]
	return reply

func last_request_id()->int:
	return 0 if operator_receipts.is_empty() else operator_receipts[-1].decode_u32(4)

func restore_receipts(data:PackedByteArray)->bool:
	if data.is_empty() or data.size()>RECEIPT_WINDOW*BUCKET_RECEIPT_SIZE:return false
	var restored:Array[PackedByteArray]=[]
	var previous_id:=0
	var previous_revision:=0
	var saved_revision:=revision()
	var offset:=0
	while offset<data.size():
		if data.size()-offset<4 or restored.size()>=RECEIPT_WINDOW:return false
		var tag:=data.decode_u32(offset)
		var is_bucket:=tag==SCOOP or tag==POUR
		var length:=BUCKET_RECEIPT_SIZE if is_bucket else RECEIPT_SIZE
		if data.size()-offset<length:return false
		var receipt:=data.slice(offset,offset+length)
		offset+=length
		var id:=receipt.decode_u32(4)
		var before:=receipt.decode_u32(8)
		var after:=receipt.decode_u32(12)
		if id==0 or (previous_id!=0 and id!=previous_id+1):return false
		if before<previous_revision or after<before or after>before+1 or after>saved_revision:return false
		if is_bucket:
			var amount:=receipt.decode_u32(76)
			if after!=before or receipt.decode_u32(40)>=32 or amount<1 or amount>1000000:return false
			if not valid_bucket_ray(receipt_point(receipt),receipt_point(receipt,28)):return false
		else:
			if tag not in [brush_tag(0),brush_tag(1),brush_tag(2),brush_tag(3)]:return false
			if not valid_brush(receipt_point(receipt),receipt.decode_double(28)):return false
		restored.append(receipt)
		previous_id=id
		previous_revision=after
	operator_receipts=restored
	return true

static func receipt_point(receipt:PackedByteArray,offset:int=16)->Vector3:
	return Vector3(receipt.decode_float(offset),receipt.decode_float(offset+4),receipt.decode_float(offset+8))

static func valid_brush(point:Vector3,radius:float)->bool:
	if not point.is_finite() or not is_finite(radius) or radius<=0 or radius>8:return false
	return AABB(Vector3.ZERO,Vector3(2000,256,2000)).encloses(AABB(point-Vector3.ONE*radius,Vector3.ONE*radius*2))

static func receipt_reply(receipt:PackedByteArray)->Dictionary:
	var reply:={"ok":true,"version":1,"request_id":receipt.decode_u32(4),"revision":receipt.decode_u32(12),"changed":receipt.decode_u32(8)!=receipt.decode_u32(12)}
	if receipt.size()==BUCKET_RECEIPT_SIZE:
		reply.changed=true
		reply.water_ml=receipt.decode_u32(76)
	return reply

func inventory_digest()->PackedByteArray:
	var hash:=HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(inventory.capture_storage_snapshot())
	return hash.finish()

func remember(receipt:PackedByteArray)->void:
	if operator_receipts.size()==RECEIPT_WINDOW:operator_receipts.pop_front()
	operator_receipts.append(receipt)

signal bucket_committed(request_id:int,slot:int,poured:bool,water_ml:int)

func transfer_bucket(id:int,pour:bool,origin:Vector3,end:Vector3,slot:int,expected:int,loadout:String)->Dictionary:
	if not healthy:return {"ok":false,"reason":"World unavailable"}
	if not valid_bucket_ray(origin,end) or slot<0 or slot>=32 or id<1 or id>0xffffffff or expected<0 or expected>0xffffffff:
		return {"ok":false,"reason":"Invalid bucket request"}
	if loadout.length()!=64 or not loadout.is_valid_hex_number(false) or loadout[0] in ["-","+"]:return {"ok":false,"reason":"Invalid loadout digest"}
	var digest:=loadout.hex_decode()
	var receipt:=PackedByteArray()
	receipt.resize(BUCKET_RECEIPT_SIZE)
	receipt.encode_u32(0,POUR if pour else SCOOP)
	receipt.encode_u32(4,id)
	receipt.encode_u32(8,expected)
	receipt.encode_u32(12,expected)
	for axis in 3:
		receipt.encode_float(16+4*axis,origin[axis])
		receipt.encode_float(28+4*axis,end[axis])
	receipt.encode_u32(40,slot)
	for index in digest.size():receipt[44+index]=digest[index]
	var last:=last_request_id()
	if id<=last:
		var index:=operator_receipts.size()-1-(last-id)
		if index<0:return {"ok":false,"reason":"Receipt expired","last_request_id":last}
		var prior:=operator_receipts[index]
		if prior.slice(0,76)==receipt.slice(0,76):return receipt_reply(prior)
		return {"ok":false,"reason":"Request ID already committed with different arguments"}
	if id!=last+1:return {"ok":false,"reason":"Unexpected request ID"}
	if expected!=revision() or inventory_digest()!=digest:return {"ok":false,"reason":"Stale terrain or inventory"}
	var inventory_revision:int=inventory.snapshot().revision
	var result:Dictionary=water.transfer_bucket(origin,end,pour,inventory,slot,inventory_revision)
	if result.get("pending",false):
		var request:Dictionary=water.next_request()
		if not request.is_empty():
			var status:=advance_water_patch(request.coordinate,expected,epoch(),64)
			if status<0:return {"ok":false,"reason":"Water occupancy preparation failed"}
			if status==1:result=water.transfer_bucket(origin,end,pour,inventory,slot,inventory_revision)
	if not result.ok:return result
	receipt.encode_u32(76,result.water_ml)
	remember(receipt)
	bucket_committed.emit(id,slot,pour,result.water_ml)
	return receipt_reply(receipt)

# The low byte is the record format. Material zero denotes excavation.
static func brush_tag(deposit_material:int)->int:return 1 | (deposit_material << 8)

func excavate(point:Vector3,radius:float,expected:int,request_id:int=0)->Dictionary:
	return _edit_brush(point,radius,expected,request_id,0)

func deposit(point:Vector3,radius:float,material:int,expected:int,request_id:int)->Dictionary:
	if material<1 or material>3:return {"ok":false,"reason":"Invalid terrain material"}
	return _edit_brush(point,radius,expected,request_id,material)

func _edit_brush(point:Vector3,radius:float,expected:int,request_id:int,deposit_material:int)->Dictionary:
	if not healthy:return {"ok":false,"reason":"World unavailable"}
	if not valid_brush(point,radius):return {"ok":false,"reason":"Invalid brush bounds"}
	if request_id!=0:
		var last:=last_request_id()
		if request_id<=last:
			var index:=operator_receipts.size()-1-(last-request_id)
			if index<0:return {"ok":false,"reason":"Receipt expired","last_request_id":last}
			var prior:=operator_receipts[index]
			if prior.decode_u32(0)==brush_tag(deposit_material) and expected==prior.decode_u32(8) and point==receipt_point(prior) and radius==prior.decode_double(28):return receipt_reply(prior)
			return {"ok":false,"reason":"Request ID already committed with different arguments"}
		if request_id!=last+1 or request_id>0xffffffff:return {"ok":false,"reason":"Unexpected request ID"}
	# Historical receipts may predate gameplay's minimum-radius check. Replay
	# their acknowledgement above, but never admit another undersized brush.
	if radius<Codec.MIN_BRUSH_RADIUS:return {"ok":false,"reason":"Invalid brush radius"}
	if expected!=revision():return {"ok":false,"reason":"Stale revision"}
	var bounds:=AABB(point-Vector3.ONE*radius,Vector3.ONE*radius*2)
	var packet:=Codec.brush(point,point,radius,0,deposit_material!=0,maxi(1,deposit_material))
	var began:=Time.get_ticks_usec()
	var edit:=EditCommands.execute(core,[packet],expected)
	if not Codec.reply_ok(edit.reply):return {"ok":false,"reason":"Terrain rejected brush"}
	last_edit_profile={"terrain_us":Time.get_ticks_usec()-began,"invalidate_us":0,"patch_us":0,"patches":0,"solve_us":0,"commit_us":0,"capture_us":0,"solves":0,"displacement_visits":0,"displacement_searches":0,"solve_phases_us":[0,0,0,0,0,0,0,0]}
	if edit.changed[0]:
		var started:=Time.get_ticks_usec()
		water.invalidate(bounds,deposit_material!=0)
		water.settle_after_edit(bounds)
		last_edit_profile.invalidate_us=Time.get_ticks_usec()-started
		healthy=_resolve_water()
	if not healthy:return {"ok":false,"reason":"Water commit failed; reload the last saved revision"}
	if request_id!=0:
		var operator_receipt:=PackedByteArray()
		operator_receipt.resize(RECEIPT_SIZE)
		operator_receipt.encode_u32(0,brush_tag(deposit_material))
		operator_receipt.encode_u32(4,request_id)
		operator_receipt.encode_u32(8,expected)
		operator_receipt.encode_u32(12,revision())
		operator_receipt.encode_float(16,point.x)
		operator_receipt.encode_float(20,point.y)
		operator_receipt.encode_float(24,point.z)
		operator_receipt.encode_double(28,radius)
		remember(operator_receipt)
	var response:=receipt_reply(operator_receipts[-1]) if request_id!=0 else sample(point)
	last_edit_profile.total_us=Time.get_ticks_usec()-began
	if edit.changed[0]:
		edit_committed.emit(revision(),bounds)
	return response

func advance_water_patch(coordinate:Vector3i,rev:int,generation:int,budget:int)->int:
	if occupancy_patch==null or coordinate!=occupancy_coordinate or rev!=occupancy_revision or generation!=occupancy_epoch:
		occupancy_patch=ClassDB.instantiate("NativeWaterTerrainPatch")
		if not occupancy_patch.configure(coordinate):
			occupancy_patch=null
			return -1
		occupancy_coordinate=coordinate
		occupancy_revision=rev
		occupancy_epoch=generation
	var status:int=occupancy_patch.sample_terrain(core,budget,rev,generation)
	if status==0:return 0
	var accepted:bool=status==1 and water.accept_patch(occupancy_patch)
	occupancy_patch=null
	return 1 if accepted else -1

func _resolve_water()->bool:
	var deadline:=Time.get_ticks_msec()+30000
	var rev:=revision()
	var generation:=epoch()
	while Time.get_ticks_msec()<deadline:
		var request:Dictionary=water.next_request()
		if not request.is_empty():
			var started:=Time.get_ticks_usec()
			var status:=advance_water_patch(request.coordinate,rev,generation,2048)
			if status<0:return false
			last_edit_profile.patch_us+=Time.get_ticks_usec()-started
			if status==1:last_edit_profile.patches+=1
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
				last_edit_profile.displacement_visits+=int(result.displacement_visits)
				last_edit_profile.displacement_searches+=int(result.displacement_searches)
				for index in result.phase_us.size():
					last_edit_profile.solve_phases_us[index]+=result.phase_us[index]
	return false
