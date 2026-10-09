# SPDX-License-Identifier: 0BSD
extends RefCounted
# Infrequent authoring coordinator; density/surface evaluation stays native.
const SurfaceTokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
var busy:=false
var token:=0
var reply: Dictionary={}
func _receive(id: int,points: PackedVector3Array,normals: PackedVector3Array,epoch: int,revision: int) -> void:
	if id==token: reply={"points":points,"normals":normals,"epoch":epoch,"revision":revision}
func assess(terrain: Node,asset: Resource,origin: Vector3i,rotation: int,fill_depth: float=8.0,cut_height: float=12.0) -> Dictionary:
	if busy or not is_instance_valid(terrain) or asset==null or not asset.is_class("NativeBlockPrefab") or not terrain.world_ready or terrain.pending_edit or not is_finite(fill_depth) or not is_finite(cut_height) or fill_depth<1 or fill_depth>8 or cut_height<0 or cut_height>16:
		return {"ok":false,"reason":"Site survey unavailable"}
	var points: PackedVector3Array=asset.foundation_samples(origin,rotation,0)
	if points.is_empty(): return {"ok":false,"reason":"No foundation footprint"}
	busy=true;terrain.surface_batch_ready.connect(_receive)
	var epoch: int=terrain.epoch;var revision: int=terrain.published_revision
	var deadline:=Time.get_ticks_msec()+15000
	var low:=INF;var high:=-INF;var count:=0;var failure:=""
	for offset in range(0,points.size(),64):
		token=SurfaceTokens.allocate();reply={}
		var batch:=points.slice(offset,mini(offset+64,points.size()))
		var submitted:=false
		while Time.get_ticks_msec()<deadline:
			if not is_instance_valid(terrain): failure="Terrain closed during survey";break
			if terrain.stopping or terrain.pending_edit or terrain.epoch!=epoch or terrain.published_revision!=revision:
				failure="Terrain changed during site survey";break
			if not submitted: submitted=terrain.request_surface_batch(batch,token)
			if not reply.is_empty(): break
			await terrain.get_tree().process_frame
		if not failure.is_empty(): break
		if reply.is_empty(): failure="Site survey timed out";break
		if reply.epoch!=epoch or reply.revision!=revision or reply.points.size()!=batch.size() or reply.normals.size()!=batch.size():
			failure="Invalid or stale terrain survey";break
		for i in batch.size():
			var p: Vector3=reply.points[i];var normal: Vector3=reply.normals[i]
			if not p.is_finite() or not normal.is_finite() or normal.length_squared()<0.5:
				failure="Site requires edited-terrain survey; natural surface unavailable";break
			low=minf(low,p.y);high=maxf(high,p.y);count+=1
		if not failure.is_empty(): break
	if is_instance_valid(terrain): terrain.surface_batch_ready.disconnect(_receive)
	busy=false
	if not failure.is_empty(): return {"ok":false,"reason":failure}
	# Leave one metre of solid overlap/clearance at the limits. A feasible grade
	# is a proposal only; post-edit column and interior checks still gate placement.
	var minimum:=maxi(ceili(high-cut_height+1.0),ceili(fill_depth+4.0))
	var maximum:=mini(floori(low+fill_depth-1.0),floori(250.0-cut_height))
	var result:={"ok":minimum<=maximum,"min_height":low,"max_height":high,"samples":count,"epoch":epoch,"revision":revision,"minimum_grade":minimum,"maximum_grade":maximum}
	if minimum>maximum: result["reason"]="Site relief exceeds bounded grading; use terraces or another site"
	else: result["grade"]=clampi(roundi((low+high)*0.5),minimum,maximum)
	return result
