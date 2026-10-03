# SPDX-License-Identifier: 0BSD
extends RefCounted
# Orchestration only: footprint generation and density sampling are native.
var points:=PackedVector3Array()
var offset:=0
var token:=0
var epoch:=0
var revision:=0
var deadline:=0
var waiting:=false
var status:="idle"
func begin(terrain: Node,asset: Resource,target: Vector3i,rotation: int) -> bool:
	if status=="checking" or not terrain.world_ready or terrain.pending_edit: return false
	points=asset.foundation_samples(target,rotation,0)
	if points.is_empty(): status="No foundation probes";return false
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
	waiting=terrain.request_density_batch(points.slice(offset,mini(offset+512,points.size())),token)
func receive(result: Dictionary) -> void:
	if status!="checking" or not waiting or result.token!=token: return
	waiting=false
	if result.status!="ok" or result.epoch!=epoch or result.revision!=revision:
		status="Terrain changed; place again";return
	var values: PackedFloat32Array=result.values
	if values.size()!=mini(512,points.size()-offset): status="Invalid terrain check";return
	for value in values:
		if not is_finite(value) or value>=0: status="Unsupported foundation; grade terrain first";return
	offset+=values.size()
	if offset==points.size(): status="supported"
