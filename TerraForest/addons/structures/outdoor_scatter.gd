# SPDX-License-Identifier: 0BSD
extends RefCounted
## Explicit authoring operation, never an ambient refill or per-frame scatter loop.
const Packs=preload("res://addons/structures/pack_registry.gd")
var busy:=false
var last_result: Dictionary={}

static func proposals(seed_value: int, center: Vector3, radius: float, count: int, exclusions: Array[AABB]=[]) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	if not Packs.discover() or not center.is_finite() or radius<1 or radius>24 or count<1 or count>64: return result
	var rows:=Packs.objects_for_pack("terraforest.outdoor_01")
	if rows.is_empty(): return result
	var random:=RandomNumberGenerator.new(); random.seed=seed_value
	var occupied: Array[AABB]=exclusions.duplicate()
	for attempt in 1024:
		if result.size()>=count: break
		var row: Dictionary=rows[result.size()%rows.size()]
		var mesh: Mesh=load(row.directory+"/models/"+row.id+".tres")
		var angle:=random.randf()*TAU; var distance:=sqrt(random.randf())*radius
		var point:=center+Vector3(cos(angle)*distance,0,sin(angle)*distance)
		var pose:=Transform3D(Basis(Vector3.UP,random.randf()*TAU),point)
		var bounds: AABB=pose*mesh.get_aabb(); var clear:=true
		for box: AABB in occupied:
			if bounds.grow(.35).intersects(box): clear=false; break
		if not clear: continue
		occupied.append(bounds); result.append({"item":row.item,"key":row.key,"transform":pose,"bounds":bounds})
	return result

static func near_road(point: Vector3, margin: float, roads: Array) -> bool:
	for road: Dictionary in roads:
		var a: Vector3=road.get("a",road.get("start",Vector3.INF)); var b: Vector3=road.get("b",road.get("finish",Vector3.INF))
		if not a.is_finite() or not b.is_finite(): continue
		var delta:=Vector2(b.x-a.x,b.z-a.z); var offset:=Vector2(point.x-a.x,point.z-a.z)
		var t:=clampf(offset.dot(delta)/maxf(.0001,delta.length_squared()),0,1)
		if (offset-delta*t).length()<float(road.get("width",8))*.5+margin: return true
	return false

func scatter_at_aim(game: Node) -> void:
	if busy or not game.session_menu.developer or game.loading_active or game.shutdown_requested or game.terrain.pending_edit: return
	var hit: Dictionary=game.model_tool.ray()
	if hit.is_empty() or hit.normal.y<.94: game._show_lake_notice("Aim at a clear, nearly level outdoor patch."); return
	busy=true
	var center: Vector3=hit.position
	var seed_value: int=game.terrain.backend.world_seed ^ int(floor(center.x))*73856093 ^ int(floor(center.z))*19349663
	var proposed:=proposals(seed_value,center,6,20)
	var roads: Array=game.generated_region.store.get_plan().get("roads",[]).duplicate()
	for street: Dictionary in game.road_palette.prepared_streets:
		if street.ends.size()==2: roads.append({"a":street.ends[0],"b":street.ends[1],"width":street.width})
	var placed:=0; var skipped:=0; var epoch: int=game.terrain.epoch
	for candidate: Dictionary in proposed:
		await game.get_tree().physics_frame
		if game.shutdown_requested or game.loading_active or game.terrain.epoch!=epoch or not game.session_menu.developer: break
		var point: Vector3=candidate.transform.origin
		var ground: Dictionary=game.structures.blocks.raycast_scene(point+Vector3.UP*4,point-Vector3.UP*4,7,[game.player.get_rid()])
		if ground.is_empty() or ground.normal.y<.94 or ground.collider==game.structures.blocks or game.structures.model_collections().values().has(ground.collider): skipped+=1; continue
		var row: Dictionary=Packs.by_item[candidate.item]; var mesh: Mesh=load(row.directory+"/models/"+row.id+".tres")
		var pose: Transform3D=candidate.transform; pose.origin.y=ground.position.y
		var bounds: AABB=pose*mesh.get_aabb()
		if near_road(point,maxf(bounds.size.x,bounds.size.z)*.5+1.2,roads) or bounds.grow(1).intersects(game.model_tool.protection()) or not game._placement_collision_ready(bounds.grow(.3)) or game.lakes.water.depth_at(ground.position)>.02: skipped+=1; continue
		var support: Dictionary=game.structures.blocks.placement_support(bounds,ground.position,false,false,[game.player.get_rid()])
		if not support.get("ok",false): skipped+=1; continue
		pose.origin.y+=float(support.offset_y)
		var probes: Array[Transform3D]=[pose]
		var prototype:=mesh.get_aabb(); prototype.position.y+=.02; prototype.size.y=maxf(.005,prototype.size.y-.02)
		var overlaps: PackedByteArray=game.structures.overlap_mask(probes,prototype.grow(.02))
		if overlaps.size()!=1 or overlaps[0]!=0: skipped+=1; continue
		var batch: Node3D=game.structures.model(candidate.key)
		if game.model_tool.history.insert(batch,game.model_tool.records(pose,batch),game.model_tool.protection())>0: placed+=1; game.terrain.changed_since_save=true
		else: skipped+=1
	busy=false; last_result={"placed":placed,"skipped":skipped,"seed":seed_value}
	game._show_lake_notice("Outdoor scatter: %d placed, %d skipped · Ctrl+Z removes each placement"%[placed,skipped])
