# SPDX-License-Identifier: 0BSD
extends RefCounted
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Turns=preload("res://addons/exploration/cave_layouts.gd")
const MAX_ATTEMPTS:=192
const MAX_SITES:=2

static func asset()->Resource:return load("res://addons/exploration/watchtower_w1.tres")

static func sleepers(site:Dictionary)->Array:
	var origin:Vector3i=site.origin;var rotation:int=site.rotation
	var identity:int=(1<<41)|(origin.x+1)|((origin.z+1)<<11)|(rotation<<22)|(1<<24)|(origin.y<<29)
	return [{"key":identity,"position":Vector3(origin)+Turns.turn(asset().get_meta("sleeper"),rotation),"yaw":-rotation*PI*.5,"pose":1+((origin.x+origin.z)%2)}]

static func clear(bounds:AABB,reservations:Array)->bool:
	return Planner.footprint_clear(bounds,reservations)

static func build(core:RefCounted,roads:Array,reservations:Array,seed_value:int)->Dictionary:
	var began:=Time.get_ticks_usec()
	if roads.size()>8192 or reservations.size()>2048:return {"ok":false,"reason":"Watchtower plan exceeds bounded input limits"}
	var prefab:=asset()
	if prefab==null:return {"ok":false,"reason":"Watchtower resource unavailable"}
	var protected:Dictionary=Planner.reservations(core,Vector3(1000,0,1000))
	if not protected.get("ok",false):return protected
	var exclusions:Array=reservations.duplicate();exclusions.append_array(protected.areas)
	var result:={"ok":true,"sites":[],"segments":[],"attempts":0,"fitted_candidates":0,"height_samples":0,"worker_ms":0.0}
	if roads.is_empty():return result
	var tried:=PackedVector3Array()
	for attempt in MAX_ATTEMPTS:
		if result.sites.size()>=MAX_SITES:break
		result.attempts=attempt+1
		var index:=(absi(seed_value)+attempt/4*maxi(1,roads.size()/48))%roads.size()
		var road:Dictionary=roads[index]
		var span:Vector3=road.finish-road.start;span.y=0
		if span.length_squared()<4:continue
		var tangent:=span.normalized()
		var normal:=Vector3(-tangent.z,0,tangent.x)*(-1 if attempt%2 else 1)
		var station:Vector3=road.start.lerp(road.finish,.5)
		var center:=station+normal*(24 if attempt%4<2 else 44)+tangent*18
		if center.x<48 or center.x>1952 or center.z<48 or center.z>1952:continue
		var near:=false
		for previous:Vector3 in tried:
			if Vector2(center.x-previous.x,center.z-previous.z).length_squared()<144:near=true;break
		if near:continue
		tried.append(center)
		for previous:Dictionary in result.sites:
			if Vector2(center.x-previous.origin.x,center.z-previous.origin.z).length_squared()<122500:near=true;break
		if near:continue
		var rotation:=0;var best:=-INF
		for turn in 4:
			var facing:=Turns.turn(Vector3(.5,0,-.5),turn)-Vector3(.5,0,.5)
			var alignment:float=facing.dot(-normal)
			if alignment>best:best=alignment;rotation=turn
		var origin:=Vector3i((center-Turns.turn(Vector3(3.5,0,4.5),rotation)).floor());origin.y=0
		var bounds:AABB=prefab.placement_bounds(origin,rotation)
		if not clear(bounds.grow(8),exclusions):continue
		var nearby:Array=[]
		for candidate:Dictionary in roads:
			var low:Vector3=candidate.start.min(candidate.finish)-Vector3(80,0,80)
			var high:Vector3=candidate.start.max(candidate.finish)+Vector3(80,0,80)
			if center.x>=low.x and center.x<=high.x and center.z>=low.z and center.z<=high.z:nearby.append(candidate)
		var plan:=Planner.plan(core,station,nearby,0,[{"asset":prefab,"origin":origin,"rotation":rotation,"street_z":station.z,"label":"Wilderness lookout","general_access":true}])
		result.height_samples+=int(plan.get("height_samples",0))
		if not plan.get("ok",false):continue
		result.fitted_candidates+=1
		var lot:Dictionary=plan.lots[0]
		if not clear(lot.bounds.grow(8),exclusions):continue
		plan.roads=[]
		var works:=Planner.earthworks(plan)
		if not works.get("ok",false):return works
		if not clear(works.bounds,exclusions):continue
		lot=lot.duplicate();lot.erase("asset")
		lot["id"]="watchtower_w1";lot["title"]="Wilderness lookout"
		result.sites.append(lot);result.segments.append_array(works.segments)
		exclusions.append(Rect2(Vector2(works.bounds.position.x,works.bounds.position.z),Vector2(works.bounds.size.x,works.bounds.size.z)).grow(8))
	result.worker_ms=(Time.get_ticks_usec()-began)/1000.
	return result
