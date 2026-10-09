# SPDX-License-Identifier: 0BSD
extends RefCounted
signal changed
const ITEMS: Array[int]=[201,204,205]
var cover: Node3D
# The normal scene ray must include terrain, buildings, trunks and vehicles.
var scene_ray: Callable
var busy:=false

func available() -> bool:
	return not busy and is_instance_valid(cover) and cover.terrain.world_ready and not cover.terrain.pending_edit and not cover.terrain.stopping and cover.removed.bind_world(cover.seed,1)

func collect(from: Vector3,to: Vector3,inventory: RefCounted,gameplay: bool) -> Dictionary:
	if not available() or not scene_ray.is_valid() or not from.is_finite() or not to.is_finite() or from.distance_squared_to(to)>64.01: return {"ok":false,"reason":"World interaction unavailable"}
	var obstruction: Dictionary=scene_ray.call(from,to)
	var end: Vector3=obstruction.position if not obstruction.is_empty() else to
	var hit: Dictionary=cover.picker.pick(from,end)
	if not hit.hit: return {"ok":false,"reason":"No reachable ground cover"}
	var key: Vector2i=hit.cell
	if cover._dirty.has(key) or cover._pending.has(key) or not cover.resident.has(key): return {"ok":false,"reason":"Ground cover updating"}
	var previous: Array=cover.resident[key]
	var next: Array=previous.duplicate(true)
	var row: Dictionary=next[hit.species]
	var index: int=row.ids.find(hit.id)
	if index<0: return {"ok":false,"reason":"Ground cover unavailable"}
	row.ids.remove_at(index)
	row.transforms=row.transforms.slice(0,index*12)+row.transforms.slice((index+1)*12)
	busy=true
	var before: Dictionary={};var revision: int=-1
	if gameplay:
		before=inventory.snapshot()
		var grant: Dictionary=inventory.grant_items(PackedInt64Array([ITEMS[hit.species],1]),before.revision)
		if not grant.ok: busy=false;return {"ok":false,"reason":"Make room in inventory"}
		revision=grant.revision
	var applied: bool=cover.picker.replace_cell(key,next)
	if applied: applied=cover.batches[hit.species].remove_instances(PackedInt64Array([hit.id]))
	if applied:
		applied=cover.removed.mark(hit.id) if hit.id<4294967296 else cover.removed.erase(hit.id)
	if not applied:
		cover.picker.replace_cell(key,previous)
		cover.batches[hit.species].upsert_instances(previous[hit.species].ids,previous[hit.species].transforms)
		if revision>=0 and not inventory.restore(before,revision).ok: push_error("Ground-cover inventory rollback failed")
		busy=false;return {"ok":false,"reason":"Ground cover changed; try again"}
	cover.resident[key]=next
	changed.emit();busy=false
	return {"ok":true,"reason":"Collected ground cover" if gameplay else "Ground cover removed","id":hit.id}

func placement_probe(species: int,from: Vector3,to: Vector3,inventory: RefCounted,gameplay: bool) -> Dictionary:
	if not available() or not scene_ray.is_valid() or species<0 or species>2 or not from.is_finite() or not to.is_finite() or from.distance_squared_to(to)>64.01: return {"ok":false,"reason":"World interaction unavailable"}
	var hit: Dictionary=scene_ray.call(from,to)
	if hit.is_empty() or not hit.position.is_finite() or not hit.normal.is_finite() or hit.normal.normalized().y<0.82: return {"ok":false,"reason":"Aim at a supported surface"}
	var point: Vector3=hit.position+Vector3.UP*0.02
	var key:=Vector2i(floori(point.x/32.0),floori(point.z/32.0))
	if not cover.resident.has(key) or cover._dirty.has(key) or cover._pending.has(key): return {"ok":false,"reason":"Ground cover updating"}
	var poses: Array[Transform3D]=[Transform3D(Basis.IDENTITY,point)]
	if cover.structures!=null:
		var mask: PackedByteArray=cover.structures.overlap_mask(poses,AABB(Vector3(-0.4,0,-0.4),Vector3(0.8,0.8,0.8)))
		if mask.size()!=1 or mask[0]: return {"ok":false,"reason":"Placement overlaps a structure"}
	if cover.water!=null:
		var mask: PackedByteArray=cover.water.placement_mask(poses)
		if mask.size()!=1 or mask[0]: return {"ok":false,"reason":"Placement is underwater"}
	if cover.picker.pick(point+Vector3.UP,point-Vector3.UP*0.3).hit: return {"ok":false,"reason":"Ground cover already occupies this spot"}
	if gameplay:
		var count:=0
		for row: Dictionary in inventory.snapshot().slots:
			if row.item==ITEMS[species]: count+=int(row.count)
		if count<1: return {"ok":false,"reason":"Missing ground-cover item"}
	return {"ok":true,"reason":"Candidate · final support checked after placement","pose":poses[0],"cell":key}

func place(species: int,from: Vector3,to: Vector3,inventory: RefCounted,gameplay: bool) -> Dictionary:
	# Always probe again on click. A displayed candidate can become stale.
	var candidate:=placement_probe(species,from,to,inventory,gameplay)
	if not candidate.ok: return candidate
	var key: Vector2i=candidate.cell

	busy=true
	var before: Dictionary={};var revision: int=-1
	if gameplay:
		before=inventory.snapshot()
		var debit: Dictionary=inventory.consume_items(PackedInt64Array([ITEMS[species],1]),before.revision)
		if not debit.ok: busy=false;return {"ok":false,"reason":"Missing ground-cover item"}
		revision=debit.revision
	var id: int=cover.removed.add(species,candidate.pose)
	if id==0:
		if revision>=0 and not inventory.restore(before,revision).ok: push_error("Ground-cover inventory rollback failed")
		busy=false;return {"ok":false,"reason":"Ground-cover placement limit reached"}
	# Resampling uses the authoritative surface/exclusion path; authored records
	# persist independently of residency and are merged into its next publication.
	cover._dirty[key]=true
	changed.emit();busy=false
	return {"ok":true,"reason":"Ground cover placed","id":id}
