# SPDX-License-Identifier: 0BSD
extends RefCounted
const Tokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
const SIZE:=Vector3i(32,32,32)
var game:Node
var combat:Node
var regions:Array[Vector3]=[]
var work:Dictionary={}
var falling:=PackedInt32Array()
var suppress:=false
var collapse_revision:=-1
var collapse_terrain_revision:=-1
var collapse_center:=Vector3.ZERO
var status:="disabled"
func attach(host:Node,owner:Node)->void:
	game=host;combat=owner
	game.structures.blocks.cells_changed.connect(func(bounds:AABB):
		if not suppress:changed(bounds))
	game.terrain.region_changed.connect(func(bounds:AABB,_revision:int):changed(bounds))
	game.terrain.density_batch_ready.connect(receive)
func changed(bounds:AABB)->void:
	if not combat.state.integrity_enabled():return
	var center:=bounds.get_center()
	for queued in regions:
		if queued.distance_squared_to(center)<16:return
	if regions.size()<32:regions.append(center)
	status="queued"
func reset()->void:
	regions.clear();work={};falling.clear();status="idle" if combat.state.integrity_enabled() else "disabled"
func step()->void:
	if not combat.state.integrity_enabled():reset();return
	if game.terrain.pending_edit:return
	if not falling.is_empty():
		if collapse_revision!=game.structures.blocks.survey_content_revision_id() or collapse_terrain_revision!=game.terrain.density_revision:
			falling.clear();regions.push_front(collapse_center);status="changed; retrying";return
		var next:=falling.slice(0,mini(48,falling.size()))
		var expected:=PackedInt32Array()
		for i in range(0,next.size(),4):
			var cell:=Vector3i(next[i],next[i+1],next[i+2])
			if game.structures.blocks.get_cell(cell)==next[i+3]:expected.append_array(next.slice(i,i+4))
		suppress=true
		if not expected.is_empty() and not game.structures.blocks.erase_cells(expected,game.structures.blocks.survey_revision_id()):
			suppress=false;status="edit admission unavailable";return
		falling=falling.slice(next.size())
		for i in range(0,expected.size(),4):
			var cell:=Vector3i(expected[i],expected[i+1],expected[i+2])
			combat._demolished(cell,expected[i+3],Vector3(cell)-Vector3.UP,0)
		suppress=false;collapse_revision=game.structures.blocks.survey_content_revision_id();status="collapsing";return
	if not work.is_empty():
		if work.epoch!=game.terrain.epoch or work.revision!=game.terrain.density_revision or work.blocks!=game.structures.blocks.survey_content_revision_id():
			regions.push_front(work.center);work={};status="changed; retrying";return
		if work.waiting:
			if Time.get_ticks_msec()>work.deadline:regions.push_front(work.center);work={};status="support unavailable"
			return
		var batch:PackedVector3Array=work.points.slice(work.offset,mini(work.offset+128,work.points.size()))
		work.waiting=game.terrain.request_interpolated_density_batch(batch,work.token)
		return
	if regions.is_empty():status="idle";return
	var center:=regions.pop_front();var origin:=Vector3i(center.floor())-SIZE/2
	var bounds:=AABB(Vector3(origin),Vector3(SIZE))
	if not game._actor_collision_ready(bounds):regions.append(center);status="world unavailable";return
	var prefab:Resource=game.structures.blocks.capture_prefab(origin,SIZE)
	if prefab==null:status="no resident blocks";return
	var records:PackedInt32Array=prefab.get_records()
	var points:PackedVector3Array=combat.state.support_probes(records,origin)
	if points.is_empty():return
	work={"center":center,"origin":origin,"records":records,"points":points,"values":PackedFloat32Array(),"offset":0,"token":Tokens.allocate(),"waiting":false,"epoch":game.terrain.epoch,"revision":game.terrain.density_revision,"blocks":game.structures.blocks.survey_content_revision_id(),"deadline":Time.get_ticks_msec()+10000}
	status="checking support"
func receive(reply:Dictionary)->void:
	if work.is_empty() or reply.token!=work.token:return
	work.waiting=false
	if reply.status!="ok" or reply.epoch!=work.epoch or reply.revision!=work.revision:
		regions.push_front(work.center);work={};status="support unavailable";return
	var values:PackedFloat32Array=reply.values
	if values.size()!=mini(128,work.points.size()-work.offset):work={};status="invalid support reply";return
	work.values.append_array(values);work.offset+=values.size()
	if work.offset<work.points.size():return
	if work.blocks==game.structures.blocks.survey_content_revision_id():
		falling=combat.state.unsupported(work.records,work.origin,SIZE,work.values)
		collapse_revision=work.blocks;collapse_terrain_revision=work.revision;collapse_center=work.center
	else:regions.push_front(work.center)
	work={}
