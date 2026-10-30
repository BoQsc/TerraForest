# SPDX-License-Identifier: 0BSD
extends Node
const Tokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
var cover:Node3D
var terrain:Node3D
var removed:RefCounted
var picker:RefCounted
var native:RefCounted
var fractures:Node3D
var rock_collision:Node3D
var resident:Dictionary={}
var _samples:Dictionary={}
var _published:Dictionary={}
var _requests:Dictionary={}
var _pending:Dictionary={}
var _reconcile:Dictionary={}
var _resample:Dictionary={}
var _owners:Array[Vector2i]=[]
var _seed:=-1
var _support:RefCounted
var rejected:=0
var unchanged_publications:=0
var last_process_us:=0
var shared_surface_ready:Callable

func _ready()->void:
	terrain=cover.terrain;removed=cover.removed;native=cover.native
	fractures=cover.fractures;rock_collision=cover.rock_collision
	picker=ClassDB.instantiate("NativeGroundCoverPicker")
	if not picker.configure_owner_limit(3969):push_error("Boulder interaction capacity rejected");return
	_support=ClassDB.instantiate("NativeVegetationSupport")
	terrain.surface_batch_ready.connect(_surface_ready)
	terrain.region_changed.connect(_terrain_changed)
	terrain.register_edit_support(_capture_support,_apply_support)
	if cover.structures!=null:cover.structures.vegetation_changed.connect(_exclusion_changed)
	if cover.water!=null:cover.water.exclusion_changed.connect(_exclusion_changed)

func reset()->void:
	for key:Vector2i in resident:
		picker.remove_cell(key);rock_collision.remove_instances(resident[key][0].ids)
	if fractures!=null:fractures.clear()
	resident.clear();_samples.clear();_published.clear();_requests.clear();_pending.clear();_reconcile.clear();_resample.clear();_owners.clear();_seed=-1

func coverage_status()->Dictionary:
	return {"ready":_published.size()==1024 and _requests.is_empty() and _resample.is_empty() and _reconcile.is_empty(),"owners":_published.size(),"total":1024,"pending":_requests.size(),"reconcile":_reconcile.size(),"rejected":rejected,"unchanged_publications":unchanged_publications,"process_us":last_process_us,"render":fractures.statistics()}

func owner_available(key:Vector2i)->bool:
	var owner:=Vector2i(key.x/2,key.y/2)
	if _reconcile.has(owner) and not _pending.has(owner) and not _resample.has(owner):_publish(owner)
	return resident.has(key) and not _pending.has(owner) and not _resample.has(owner) and not _reconcile.has(owner)

func _process(_delta:float)->void:
	var began:=Time.get_ticks_usec()
	_step()
	last_process_us=Time.get_ticks_usec()-began

func _step()->void:
	if not cover.is_processing() or not terrain.world_ready or terrain.stopping:return
	_ensure_seed()
	if terrain.pending_edit:return
	for key:Vector2i in _reconcile.keys().slice(0,2):
		if _samples.has(key):_publish(key)
	if _published.size()==1024 and _resample.is_empty():return
	if shared_surface_ready.is_valid() and not shared_surface_ready.call():return
	_request_pages()

func _ensure_seed()->void:
	if _seed!=cover.seed:
		reset();_seed=cover.seed
		var scatter:RefCounted=ClassDB.instantiate("NativeVegetationScatter")
		_owners=scatter.world_cells(Vector2i(floori(cover.camera.global_position.x/64),floori(cover.camera.global_position.z/64)))

func _request_pages()->void:
	var admitted:=0
	for key:Vector2i in _owners:
		if (_published.has(key) and not _resample.has(key)) or _pending.has(key) or (_samples.has(key) and not _resample.has(key)):continue
		var data:Dictionary=candidates_for_page(key)
		if data.ids.is_empty():
			_samples[key]={"ids":PackedInt64Array(),"transforms":[]};_resample.erase(key);_reconcile[key]=true
		else:
			if _requests.size()>=2:break
			var token:=Tokens.allocate()
			if not terrain.request_surface_page(data.points,key,token):break
			data.key=key;_requests[token]=data;_pending[key]=token
		admitted+=1
		if admitted>=8:break

func _surface_ready(token:int,points:PackedVector3Array,normals:PackedVector3Array,epoch:int,revision:int)->void:
	if not _requests.has(token):return
	var data:Dictionary=_requests[token];_requests.erase(token);_pending.erase(data.key)
	accept_surface_page(data,points,normals,epoch,revision)

func candidates_for_page(key:Vector2i)->Dictionary:
	if cover.seed_source.is_valid():cover.seed=cover.seed_source.call()
	_ensure_seed()
	var data:Dictionary=native.boulder_candidates(key,cover.seed)
	data.key=key;data.seed=_seed
	return data

func accept_surface_page(data:Dictionary,points:PackedVector3Array,normals:PackedVector3Array,epoch:int,revision:int)->void:
	if data.seed!=cover.seed or epoch!=terrain.epoch or revision!=terrain.published_revision or terrain.pending_edit:
		_resample[data.key]=true;return
	var placed:Dictionary=native.place(data.ids,points,normals)
	if not placed.ok:rejected+=1;_resample[data.key]=true;return
	_samples[data.key]=placed;_resample.erase(data.key);_reconcile[data.key]=true

func _publish(key:Vector2i)->void:
	var sample:Dictionary=_samples[key]
	var poses:Array[Transform3D]=[];poses.assign(sample.transforms)
	var mask:PackedByteArray=removed.mask(sample.ids)
	var structure_mask:=PackedByteArray();var water_mask:=PackedByteArray()
	if cover.structures!=null:structure_mask=cover.structures.overlap_mask(poses,AABB(Vector3(-0.4,0,-0.4),Vector3(0.8,0.8,0.8)))
	if cover.water!=null:water_mask=cover.water.placement_mask(poses)
	if (cover.structures!=null and structure_mask.size()!=mask.size()) or (cover.water!=null and water_mask.size()!=mask.size()):return
	var probes:Array[Transform3D]=[]
	for pose:Transform3D in poses:
		probes.append(Transform3D(Basis.IDENTITY,pose.origin))
		for side in 8:probes.append(Transform3D(Basis.IDENTITY,pose.origin+Vector3(cos(side*TAU/8),0,sin(side*TAU/8))*4.0))
	var road_mask:PackedByteArray=cover.road_regions.placement_mask(probes,4.0) if cover.road_regions!=null else PackedByteArray()
	if cover.road_regions!=null and road_mask.size()!=probes.size():return
	for index in mask.size():
		if (not structure_mask.is_empty() and structure_mask[index]) or (not water_mask.is_empty() and water_mask[index]):mask[index]=1
		if not road_mask.is_empty():
			for probe in 9:
				if road_mask[index*9+probe]:mask[index]=1
	if _published.has(key) and sample.get("published_mask") == mask:
		unchanged_publications+=1;_reconcile.erase(key);return
	var shelters:Array=[]
	for index in 4:
		var cell:=key*2+Vector2i(index%2,index/2)
		shelters.append(cover.shelter_source.call(cell) if cover.shelter_source.is_valid() else PackedVector3Array())
	var packed:Dictionary=native.pack_boulders(sample.ids,poses,mask,shelters)
	if packed.is_empty():rejected+=1;return
	for index in 4:
		var cell:=key*2+Vector2i(index%2,index/2)
		if cell.x>=63 or cell.y>=63:continue
		var rows:=empty_rows();rows[0]=packed.owners[index]
		if not _replace(cell,rows):rejected+=1;return
	sample.published_mask=mask
	_published[key]=true;_reconcile.erase(key)

static func empty_rows()->Array:
	var rows:Array=[]
	for species in 9:rows.append({"ids":PackedInt64Array(),"transforms":PackedFloat32Array()})
	return rows

func restore_render_row(row:Dictionary,_species:int)->bool:
	return fractures.upsert_rows(row.ids,row.transforms)

func _replace(key:Vector2i,rows:Array)->bool:
	var previous:Array=resident.get(key,empty_rows())
	if previous==rows:return true
	var row:Dictionary=rows[0];var prior:Dictionary=previous[0]
	if not fractures.upsert_rows(row.ids,row.transforms):return false
	if not rock_collision.upsert_instances(row.ids,row.transforms) or not picker.replace_cell(key,rows):
		fractures.remove_rows(row.ids);fractures.upsert_rows(prior.ids,prior.transforms)
		rock_collision.remove_instances(row.ids);rock_collision.upsert_instances(prior.ids,prior.transforms)
		picker.replace_cell(key,previous);return false
	var retired:=PackedInt64Array()
	for identity:int in prior.ids:
		if not row.ids.has(identity):retired.append(identity)
	fractures.remove_rows(retired);rock_collision.remove_instances(retired)
	if row.ids.is_empty():resident.erase(key);picker.remove_cell(key)
	else:resident[key]=rows
	cover.obstacles_changed.emit(AABB(Vector3(key.x*32,-4096,key.y*32),Vector3(32,8192,32)).grow(8))
	return true

func _keys(bounds:AABB)->Array[Vector2i]:
	var keys:Array[Vector2i]=[]
	for row in range(maxi(0,floori(bounds.position.z/32)),mini(62,floori(bounds.end.z/32))+1):
		for column in range(maxi(0,floori(bounds.position.x/32)),mini(62,floori(bounds.end.x/32))+1):
			var key:=Vector2i(column,row)
			if resident.has(key):keys.append(key)
	return keys

func _capture_support(bounds:AABB)->Array:
	var snapshots:Array=[]
	for key:Vector2i in _keys(bounds.grow(1)):
		var snapshot:Dictionary=_support.ground_probes(resident[key],bounds)
		if snapshot.ids.is_empty():continue
		snapshot.key=key;snapshot.rows=resident[key];snapshots.append(snapshot)
	return snapshots

func _apply_support(snapshot:Dictionary,result:Dictionary)->bool:
	var verdict:Dictionary=result.verdict if result.has("verdict") else _support.lost_roots(snapshot,result.before,result.after)
	if not verdict.ok:return false
	if verdict.ids.is_empty():return true
	if not removed.remove_roots(verdict.destroyed):return false
	if not resident.has(snapshot.key):return true
	return _replace(snapshot.key,_support.filter_ground(resident[snapshot.key],verdict.ids))

func _terrain_changed(bounds:AABB,_revision:int)->void:
	var road:bool=terrain.latest_edit_members.any(func(member:Dictionary):return member.descriptor.command==28)
	for key:Vector2i in _owners:
		if (road or not _published.has(key)) and AABB(Vector3(key.x*64,bounds.position.y,key.y*64),Vector3(64,maxf(1,bounds.size.y),64)).intersects(bounds):_resample[key]=true

func _exclusion_changed(bounds:AABB)->void:
	for key:Vector2i in _samples:
		if _samples[key].transforms.is_empty():continue
		if bounds.size==Vector3.ZERO or AABB(Vector3(key.x*64,bounds.position.y,key.y*64),Vector3(64,maxf(1,bounds.size.y),64)).grow(8).intersects(bounds):_reconcile[key]=true
