# SPDX-License-Identifier: 0BSD
extends RefCounted
const SCAN_LIMIT:=4096
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
func begin(terrain: Node,asset: Resource,target: Vector3i,rotation: int) -> bool:
	if status=="checking" or not terrain.world_ready or terrain.pending_edit: return false
	points=asset.foundation_samples(target,rotation,0)
	if points.is_empty(): status="No foundation probes";return false
	checked_asset=asset;checked_target=target;checked_rotation=rotation
	clearance=false;deep_support=false;clearance_total=asset.clearance_sample_count()
	epoch=terrain.epoch;revision=terrain.density_revision
	offset=0;waiting=false;status="checking";deadline=Time.get_ticks_msec()+10000
	return true
func tick(terrain: Node) -> void:
	if status!="checking": return
	if terrain.epoch!=epoch or terrain.density_revision!=revision or terrain.pending_edit or terrain.stopping:
		status="Terrain changed; place again";return
	if Time.get_ticks_msec()>deadline: status="Terrain check timed out; place again";return
	if waiting: return
	token+=1
	var batch:=PackedVector3Array()
	if clearance:
		for page_offset in range(offset,mini(offset+SCAN_LIMIT,clearance_total),512):
			batch.append_array(checked_asset.clearance_samples(checked_target,checked_rotation,page_offset,512))
	else: batch=points.slice(offset,mini(offset+SCAN_LIMIT,points.size()))
	# Native column maximum checks every layer through the bounded fill depth.
	var support_depth: int=mini(8,maxi(0,checked_target.y-4)) if deep_support and not clearance else 0
	waiting=terrain.request_density_scan(batch,token,support_depth)
func receive(result: Dictionary) -> void:
	if status!="checking" or not waiting or result.token!=token: return
	waiting=false
	if result.status!="ok" or result.epoch!=epoch or result.revision!=revision:
		status="Terrain changed; place again";return
	var values: PackedFloat32Array=result.values
	if values.size()!=mini(SCAN_LIMIT,(clearance_total if clearance else points.size())-offset): status="Invalid terrain check";return
	for value in values:
		if not is_finite(value): status="Invalid terrain check";return
		if clearance and value<0: status="Terrain inside building; clear or grade site first";return
		if not clearance and value>=0:
			status="Fill lacks support through grading depth; choose a lower site" if deep_support else "Unsupported foundation; grade terrain first"
			return
	offset+=values.size()
	if clearance:
		if offset==clearance_total: status="supported"
	elif offset==points.size():
		if not deep_support:
			deep_support=true;offset=0;return
		clearance=true;offset=0
		if clearance_total==0: status="supported"
