# SPDX-License-Identifier: 0BSD
extends RefCounted
signal changed
const Catalog=preload("res://addons/world_ecosystem/ground_catalog.gd")
const ITEMS=Catalog.COSTS
const LARGE_REWARD=24
var cover: Node3D
# The normal scene ray must include terrain, buildings, trunks and vehicles.
var scene_ray: Callable
var busy:=false
const MAX_REACH=8.0

func reach(gameplay:bool)->float:
	return 3.5 if gameplay else MAX_REACH

func available() -> bool:
	return not busy and is_instance_valid(cover) and cover.terrain.world_ready and not cover.terrain.pending_edit and not cover.terrain.stopping and cover.removed.bind_world(cover.seed,1)

func collection_probe(from: Vector3,to: Vector3,shared_hit: Variant=null,species_mask:int=(1<<Catalog.COUNT)-1) -> Dictionary:
	if not available() or not scene_ray.is_valid() or not from.is_finite() or not to.is_finite() or from.distance_squared_to(to)>64.01: return {"ok":false,"reason":"World interaction unavailable"}
	var obstruction: Dictionary=scene_ray.call(from,to) if shared_hit==null else shared_hit
	var end: Vector3=obstruction.position if not obstruction.is_empty() and from.distance_squared_to(obstruction.position)<from.distance_squared_to(to) else to
	var hit: Dictionary=cover.picker.pick_filtered(from,end,species_mask)
	if not hit.hit: return {"ok":false,"reason":"No reachable ground cover"}
	var key: Vector2i=hit.cell
	if cover._dirty.has(key) or cover._pending.has(key) or not cover.resident.has(key): return {"ok":false,"reason":"Ground cover updating"}
	return {"ok":true,"hit":hit}

func pickup_probe(from:Vector3,to:Vector3,shared_hit:Variant=null)->Dictionary:
	return collection_probe(from,to,shared_hit,Catalog.PICKUP_SPECIES_MASK)

func collect(from: Vector3,to: Vector3,inventory: RefCounted,gameplay: bool,shared_hit: Variant=null,attack_target: int=0) -> Dictionary:
	var candidate:=pickup_probe(from,to,shared_hit) if gameplay and attack_target==0 else collection_probe(from,to,shared_hit)
	if not candidate.ok:return candidate
	var hit: Dictionary=candidate.hit
	if attack_target!=0 and hit.id!=attack_target:return {"ok":false,"reason":"Target changed"}
	if gameplay and Catalog.HARVEST_ONLY[hit.species] and attack_target!=hit.id:return {"ok":false,"reason":"Strike vegetation to harvest it"}
	if gameplay and hit.get("large",false) and attack_target!=hit.id:return {"ok":false,"reason":"Mine the boulder with a pickaxe"}
	var key: Vector2i=hit.cell
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
		var grant: Dictionary=inventory.grant_items(PackedInt64Array([Catalog.REWARDS[hit.species],LARGE_REWARD if hit.get("large",false) else 1]),before.revision)
		if not grant.ok: busy=false;return {"ok":false,"reason":"Make room in inventory"}
		revision=grant.revision
	var applied: bool=cover.picker.replace_cell(key,next)
	if applied and not hit.get("large",false):applied=cover.batches[hit.species].remove_instances(PackedInt64Array([hit.id]))
	if applied and hit.get("large",false):applied=cover.rock_collision.remove_instances(PackedInt64Array([hit.id]))
	if applied:
		applied=cover.removed.mark(hit.id) if hit.id<4294967296 else cover.removed.erase(hit.id)
	if not applied:
		cover.picker.replace_cell(key,previous)
		cover.restore_render_row(previous[hit.species],hit.species)
		if hit.get("large",false):
			var large:Dictionary=cover.native.boulder_rows(previous[0]);cover.rock_collision.upsert_instances(large.ids,large.transforms)
		if revision>=0 and not inventory.restore(before,revision).ok: push_error("Ground-cover inventory rollback failed")
		busy=false;return {"ok":false,"reason":"Ground cover changed; try again"}
	cover.resident[key]=next
	if hit.get("large",false):
		if gameplay:cover.fractures.finish(hit.id)
		else:cover.fractures.remove_rows(PackedInt64Array([hit.id]))
	changed.emit();busy=false
	return {"ok":true,"reason":"Collected ground cover" if gameplay else "Ground cover removed","id":hit.id}

func placement_probe(species: int,from: Vector3,to: Vector3,inventory: RefCounted,gameplay: bool) -> Dictionary:
	if not scene_ray.is_valid() or species<0 or species>=Catalog.COUNT or not from.is_finite() or not to.is_finite() or from.distance_squared_to(to)>64.01: return {"ok":false,"reason":"World interaction unavailable"}
	var reach_squared:=from.distance_squared_to(to)
	if reach_squared<.0001:return {"ok":false,"reason":"Aim at a supported surface"}
	var hit: Dictionary=scene_ray.call(from,from+(to-from).normalized()*MAX_REACH)
	if hit.is_empty() or not hit.position.is_finite() or not hit.normal.is_finite(): return {"ok":false,"reason":"Aim at a supported surface"}
	var point: Vector3=hit.position+Vector3.UP*0.02
	var key:=Vector2i(floori(point.x/32.0),floori(point.z/32.0))
	var poses: Array[Transform3D]=[Transform3D(Basis.IDENTITY,point)]
	var candidate:={"ok":false,"reason":"","pose":poses[0],"cell":key}
	if from.distance_squared_to(hit.position)>reach_squared+.0001:candidate.reason="Out of reach";return candidate
	if not available() or not cover.resident.has(key) or cover._dirty.has(key) or cover._pending.has(key):candidate.reason="Ground cover updating";return candidate
	if hit.normal.normalized().y<0.82:candidate.reason="Aim at a supported surface";return candidate
	if cover.structures!=null:
		var mask: PackedByteArray=cover.structures.overlap_mask(poses,AABB(Vector3(-0.4,0,-0.4),Vector3(0.8,1.1 if species==8 else 0.8,0.8)))
		if mask.size()!=1 or mask[0]:candidate.reason="Placement overlaps a structure";return candidate
	if cover.water!=null:
		var mask: PackedByteArray=cover.water.placement_mask(poses)
		if mask.size()!=1 or mask[0]:candidate.reason="Placement is underwater";return candidate
	if cover.picker.pick(point+Vector3.UP,point-Vector3.UP*0.3).hit:candidate.reason="Ground cover already occupies this spot";return candidate
	if gameplay:
		var count:=0
		for row: Dictionary in inventory.snapshot().slots:
			if row.item==ITEMS[species]: count+=int(row.count)
		if count<1:candidate.reason="Missing ground-cover item";return candidate
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
