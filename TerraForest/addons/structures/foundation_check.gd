# SPDX-License-Identifier: 0BSD
extends RefCounted
const SCAN_LIMIT:=4096
const SurfaceTokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
# Orchestration only: footprint generation and density sampling are native.
var points:=PackedVector3Array()
var offset:=0
var token:=0
var epoch:=0
var revision:=0
var deadline:=0
var waiting:=false
var status:="idle"
var clearance:=false
var deep_support:=false
var checked_asset: Resource
var checked_target:=Vector3i.ZERO
var checked_rotation:=0
var clearance_total:=0
var surfaces:=false
var surface_total:=0
var failure_point:=Vector3.INF
var checked_band:=0
var model_clearance:=PackedVector3Array()
func begin(terrain: Node,asset: Resource,target: Vector3i,rotation: int) -> bool:
	if status=="checking" or not terrain.world_ready or terrain.pending_edit: return false
	var contract:=preload("res://addons/structures/terrain_contact.gd").describe(asset)
	if not contract.ok:status=contract.reason;return false
	points=asset.foundation_samples(target,rotation,int(asset.get_meta("site_sample_band",0)))
	if points.is_empty(): status="No foundation probes";return false
	checked_asset=asset;checked_target=target;checked_rotation=rotation
	model_clearance=PackedVector3Array()
	checked_band=int(contract.sample_band)
	clearance=false;deep_support=false;clearance_total=asset.clearance_sample_count()
	surfaces=false;failure_point=Vector3.INF
	surface_total=asset.terrain_surface_sample_count(int(contract.sample_band))
	if surface_total<0:status="Terrain surface check exceeds bounded probe budget";return false
	epoch=terrain.epoch;revision=terrain.density_revision
	offset=0;waiting=false;status="checking";deadline=Time.get_ticks_msec()+10000
	return true

func begin_surfaces_only(terrain:Node,asset:Resource,target:Vector3i,rotation:int,band:int=4095)->bool:
	if status=="checking" or not terrain.world_ready or terrain.pending_edit:return false
	if asset==null or not asset.is_class("NativeBlockPrefab") or rotation<0 or rotation>3:return false
	checked_asset=asset;checked_target=target;checked_rotation=rotation;checked_band=band
	model_clearance=PackedVector3Array()
	surface_total=asset.terrain_surface_sample_count(band)
	if surface_total<=0:status="Missing or excessive terrain surface probes";return false
	surfaces=true;clearance=false;deep_support=false;failure_point=Vector3.INF
	epoch=terrain.epoch;revision=terrain.density_revision
	offset=0;waiting=false;status="checking";deadline=Time.get_ticks_msec()+10000
	return true
func begin_ground_models(terrain:Node,asset:Resource,target:Vector3i,rotation:int,models:Dictionary)->bool:
	if status=="checking" or not terrain.world_ready or terrain.pending_edit:return false
	var sampler:RefCounted=ClassDB.instantiate("NativePrefabPlacement")
	var probes:Dictionary=sampler.ground_model_samples(asset,target,rotation,models)
	if not probes.get("ok",false):status=probes.get("reason","Invalid model probes");return false
	points=probes.support;model_clearance=probes.clearance
	checked_asset=null;checked_target=target;checked_rotation=rotation;checked_band=0
	clearance=false;deep_support=false;surfaces=false;surface_total=0;clearance_total=model_clearance.size();failure_point=Vector3.INF
	epoch=terrain.epoch;revision=terrain.density_revision
	offset=0;waiting=false;status="checking";deadline=Time.get_ticks_msec()+10000
	return true
func tick(terrain: Node) -> void:
	if status!="checking": return
	if terrain.epoch!=epoch or terrain.density_revision!=revision or terrain.pending_edit or terrain.stopping:
		status="Terrain changed; place again";return
	if Time.get_ticks_msec()>deadline: status="Terrain check timed out; place again";return
	if waiting: return
	token=SurfaceTokens.allocate()
	var batch:=PackedVector3Array()
	if surfaces:
		for page_offset in range(offset,mini(offset+SCAN_LIMIT,surface_total),512):
			batch.append_array(checked_asset.terrain_surface_samples(checked_target,checked_rotation,page_offset,512,checked_band))
	elif clearance:
		if not model_clearance.is_empty():batch=model_clearance.slice(offset,mini(offset+SCAN_LIMIT,clearance_total))
		else:
			for page_offset in range(offset,mini(offset+SCAN_LIMIT,clearance_total),512):
				batch.append_array(checked_asset.clearance_samples(checked_target,checked_rotation,page_offset,512,checked_band))
	else: batch=points.slice(offset,mini(offset+SCAN_LIMIT,points.size()))
	# Native column maximum checks every layer through the bounded fill depth.
	var support_depth: int=mini(8,maxi(0,checked_target.y-4)) if deep_support and not clearance else 0
	waiting=terrain.request_density_scan(batch,token,support_depth,clearance or surfaces)
func receive(result: Dictionary) -> void:
	if status!="checking" or not waiting or result.token!=token: return
	waiting=false
	if result.status!="ok" or result.epoch!=epoch or result.revision!=revision:
		status="Terrain changed; place again";return
	var values: PackedFloat32Array=result.values
	if values.size()!=mini(SCAN_LIMIT,(surface_total if surfaces else clearance_total if clearance else points.size())-offset): status="Invalid terrain check";return
	for index in values.size():
		var value:float=values[index]
		if not is_finite(value): status="Invalid terrain check";return
		if surfaces and value<0:
			failure_point=checked_asset.terrain_surface_samples(checked_target,checked_rotation,offset+index,1,checked_band)[0]
			status="Terrain intersects exposed block surface at "+str(failure_point);return
		if clearance and value<0: status="Terrain inside building; clear or grade site first";return
		if not clearance and not surfaces and value>=0:
			status="Fill lacks support through grading depth; choose a lower site" if deep_support else "Unsupported foundation; grade terrain first"
			return
	offset+=values.size()
	if surfaces:
		if offset==surface_total:status="supported"
	elif clearance:
		if offset==clearance_total:_begin_surfaces()
	elif offset==points.size():
		if not deep_support:
			deep_support=true;offset=0;return
		clearance=true;offset=0
		if clearance_total==0:_begin_surfaces()

func _begin_surfaces()->void:
	surfaces=true;offset=0
	if surface_total==0:status="supported"
