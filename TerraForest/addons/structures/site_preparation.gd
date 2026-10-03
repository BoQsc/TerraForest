# SPDX-License-Identifier: 0BSD
extends RefCounted
# One accepted terrain edit at a time; stopping never pretends to undo it.
var plan: Dictionary={}
var epoch:=0
var revision:=0
var completed:=0
var waiting:=false
var ticket:=-1
var stop_requested:=false
var status:="idle"
var reason:=""
func begin(value: Dictionary,terrain: Node,guard: Callable) -> bool:
	reason="Preparation unavailable; wait for terrain or survey again"
	if status=="running" or not value.get("ok",false) or value.get("segments",[]).is_empty() or value.segments.size()>256 or terrain.pending_edit or not terrain.world_ready: return false
	var error: String=guard.call(value.bounds)
	if not error.is_empty(): reason=error;return false
	plan=value.duplicate(true);epoch=terrain.epoch;revision=terrain.density_revision
	completed=0;waiting=false;stop_requested=false;reason="";status="running"
	return true
func cancel() -> void:
	if status=="running": stop_requested=true
func resume(terrain: Node,guard: Callable) -> bool:
	reason="Cannot resume after terrain changes; survey again"
	if status!="stopped" or terrain.pending_edit or terrain.epoch!=epoch or terrain.density_revision!=revision or not terrain.world_ready: return false
	var error: String=guard.call(plan.bounds)
	if not error.is_empty(): reason=error;return false
	stop_requested=false;reason="";status="running";return true
func tick(terrain: Node,guard: Callable) -> void:
	if status!="running": return
	if terrain.stopping or terrain.epoch!=epoch:
		status="failed";reason="World changed during preparation";return
	if waiting:
		if terrain.pending_edit: return
		waiting=false
		var outcome: Dictionary=terrain.last_edit_outcome
		if outcome.get("epoch",-1)!=epoch or outcome.get("ticket",-1)!=ticket or outcome.get("status","") not in ["published","unchanged"]:
			status="failed";reason="Terrain section failed or did not publish; survey again";return
		var expected: int=revision+(1 if outcome.status=="published" else 0)
		if terrain.density_revision!=expected or outcome.get("revision",-1)!=expected:
			status="failed";reason="Unexpected terrain revision; survey again";return
		revision=terrain.density_revision;completed+=1
	if completed==plan.segments.size(): status="complete";return
	if stop_requested: status="stopped";reason="Stopped; completed terrain edits remain";return
	if terrain.pending_edit or terrain.density_revision!=revision or not terrain.world_ready:
		status="failed";reason="Terrain changed during preparation; survey again";return
	var error: String=guard.call(plan.bounds)
	if not error.is_empty(): status="stopped";reason=error;return
	var segment: Dictionary=plan.segments[completed]
	waiting=terrain.construct_graded_bed(segment.start,segment.finish,segment.half_width,segment.depth,segment.clearance,segment.material,segment.shoulder)
	if waiting: ticket=terrain.edit_ticket
	if not waiting: status="stopped";reason="Terrain edit not accepted; retry when terrain is ready"
