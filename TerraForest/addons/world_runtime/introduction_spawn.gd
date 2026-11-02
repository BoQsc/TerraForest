# SPDX-License-Identifier: 0BSD
extends RefCounted

const Catalog=preload("res://addons/structures/expansion_catalog.gd")
const LOCAL=Vector3(.5,9.02,2)
const EXIT=[LOCAL,Vector3(2.5,9.02,.8),Vector3(2.5,5.02,-5.2),Vector3(.5,5.02,-5.2),Vector3(.5,5.02,8.5)]

static func point(lot:Dictionary,local:Vector3)->Vector3:
	for turn in int(lot.rotation):local=Vector3(1-local.z,local.y,local.x)
	return Vector3(lot.origin)+local

static func select(sites:Array)->Dictionary:
	var trader:=Vector3.INF
	var houses:Array=[]
	for site:Dictionary in sites:
		for lot:Dictionary in site.get("lots",[]):
			if lot.asset.has_meta("trader_anchor") and not trader.is_finite():trader=point(lot,lot.asset.get_meta("trader_anchor").origin)
			if lot.asset.get_meta("expansion_id","")=="house_c1":houses.append(lot)
	if not trader.is_finite():return {"ok":false,"reason":"No trader for the upstairs introduction"}
	var selected:Dictionary={};var distance:=200.0
	for lot:Dictionary in houses:
		var candidate:float=point(lot,LOCAL).distance_to(trader)
		if candidate<distance:distance=candidate;selected=lot
	if selected.is_empty():return {"ok":false,"reason":"No approved two-storey house within 200 m of the trader"}
	var reference:Resource=Catalog.asset("house_c1")
	if selected.asset.get_records()!=reference.get_records() or selected.asset.get_model_attachments()!=reference.get_model_attachments():return {"ok":false,"reason":"Upstairs spawn requires the approved house geometry"}
	var route:=PackedVector3Array()
	for local:Vector3 in EXIT:route.append(point(selected,local))
	return {"ok":true,"position":route[0],"exit":route,"lot":selected,"trader":trader,"distance":distance}

static func clear(game:Node,position:Vector3)->bool:
	var space:PhysicsDirectSpaceState3D=game.get_world_3d().direct_space_state
	var floor_hit:=space.intersect_ray(PhysicsRayQueryParameters3D.create(position+Vector3.UP*.2,position-Vector3.UP*.25,7,[game.player.get_rid()]))
	if floor_hit.is_empty() or floor_hit.normal.y<.85 or absf(floor_hit.position.y-position.y)>.08:return false
	var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,position+Vector3.UP*.9);query.collision_mask=7;query.exclude=[game.player.get_rid()]
	return space.intersect_shape(query,1).is_empty()
