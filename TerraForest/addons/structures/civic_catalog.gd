# SPDX-License-Identifier: 0BSD
extends RefCounted
## Opt-in R1 candidates. Uniform vertical translation preserves reviewed geometry.
const IDS:=["trader_t1","town_hall_t1","church_c1","school_s2","warehouse_w1"]
const TITLES:=["Trader house","Town hall","Church","School","Warehouse"]
const MERCHANT_PLACE:=250
static func asset(index:int)->Resource:
	if index<0 or index>=IDS.size():return null
	var source:Resource=load("res://addons/structures/prefabs/civic_review_"+IDS[index]+".tres")
	return source.duplicate() if source!=null else null

static func recipe(center:Vector3)->Array:
	var result:=[]
	for index in IDS.size():
		var prefab:=asset(index)
		var bounds:AABB=prefab.placement_bounds(Vector3i.ZERO,0)
		var street:float=center.z+[-64,0,64][index/2]
		var target:=Vector3(center.x+(-30 if index%2==0 else 30),0,street-28)
		var origin:=Vector3i(roundi(target.x-bounds.get_center().x),0,roundi(target.z-bounds.get_center().z))
		result.append({"asset":prefab,"origin":origin,"rotation":0,"street_z":street,"label":TITLES[index]})
	return result

static func streets(center:Vector3)->Array:
	return preload("res://addons/structures/city_catalog.gd").streets(center)

static func metadata(site:Dictionary)->Array:
	var result:=[]
	for index in site.lots.size():
		var lot:Dictionary=site.lots[index]
		result.append({"id":251+index,"title":lot.label,"detail":lot.asset.get_meta("description",""),"position":lot.entrance.segment.finish})
		if lot.asset.has_meta("trader_anchor"):
			var anchor:Transform3D=lot.asset.get_meta("trader_anchor")
			result.append({"id":MERCHANT_PLACE,"title":"Resident trader","detail":"Supplies bought and sold for coins. Finite stock and purse.","position":Vector3(lot.origin)+anchor.origin})
	return result

static func prepare_landscape(game:Node,site:Dictionary)->bool:
	# Generation only: retain the forest between lots, but keep mature crowns
	# off civic roofs and the public approach. Native stable exclusions persist.
	for lot:Dictionary in site.lots:
		if not lot.asset.has_meta("civic_id"):continue
		var bounds:AABB=lot.asset.placement_bounds(lot.origin,lot.rotation)
		var footprint:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(2.5)
		var path:Dictionary=lot.entrance.segment
		var low:Vector3=path.start.min(path.finish);var high:Vector3=path.start.max(path.finish)
		var arrival:=Rect2(Vector2(low.x,low.z),Vector2(high.x-low.x,high.z-low.z)).grow(5)
		var envelope:=footprint.merge(arrival)
		for z in range(maxi(0,floori(envelope.position.y/64)),mini(31,floori(envelope.end.y/64))+1):
			for x in range(maxi(0,floori(envelope.position.x/64)),mini(31,floori(envelope.end.x/64))+1):
				var candidates:Dictionary=game.ecosystem._scatter().candidates(Vector2i(x,z),game.terrain.backend.world_seed,game.ecosystem.density,true,game.ecosystem.biome_profile)
				for index in candidates.points.size():
					var point:Vector3=candidates.points[index]
					var id:int=candidates.ids[index]
					if (footprint.has_point(Vector2(point.x,point.z)) or arrival.has_point(Vector2(point.x,point.z))) and not game.ecosystem.harvest_state.contains(id):
						if not game.ecosystem.harvest_state.mark(id):return false
	return true
