# SPDX-License-Identifier: 0BSD
extends RefCounted

const Catalog=preload("res://addons/structures/expansion_catalog.gd")
const HOMES={"cottage_a2":Vector3(1.1,2.002,2.8),"house_c1":Vector3(2,5.002,1)}
const CHURCH=[Vector3(6.5,5.002,14),Vector3(6.5,5.002,19),Vector3(6.5,5.002,24),Vector3(6.5,5.002,30),Vector3(2,5.002,12),Vector3(10.5,5.002,12),Vector3(7,1.002,10),Vector3(3.5,1.002,10),Vector3(17,5.002,3),Vector3(17,5.002,10)]

static func key(origin:Vector3i,rotation:int,slot:int=1)->int:
	return (origin.x+1)|((origin.z+1)<<11)|((origin.y+256)<<22)|(rotation<<32)|(slot<<34)

static func plan(lots:Array,seed_value:int)->Dictionary:
	var anchors:Array=[]
	var church_anchors:Array=[]
	var checked:Dictionary={}
	for lot:Dictionary in lots:
		var asset:Resource=lot.asset
		var id:String=asset.get_meta("expansion_id","")
		if not HOMES.has(id) and id!="church_c1":continue
		if not checked.has(asset):
			var reference:Resource=Catalog.asset(id)
			if reference==null or asset.get_records()!=reference.get_records() or asset.get_model_attachments()!=reference.get_model_attachments():return {"ok":false,"reason":"Sleeper anchors require the reviewed house geometry: "+id}
			checked[asset]=true
		var origin:Vector3i=lot.origin
		var rotation:int=lot.rotation
		if origin.x<0 or origin.x>2000 or origin.z<0 or origin.z>2000 or origin.y < -256 or origin.y>512 or rotation<0 or rotation>3:return {"ok":false,"reason":"Invalid authored house transform"}
		if id=="church_c1":
			for index in CHURCH.size():
				var position:Vector3=CHURCH[index]
				for turn in rotation:position=Vector3(1-position.z,position.y,position.x)
				church_anchors.append({"key":key(origin,rotation,100+index),"position":Vector3(origin)+position,"yaw":-rotation*PI*.5,"pose":1+index%2})
			continue
		var identity:=key(origin,rotation)
		var random:=RandomNumberGenerator.new();random.seed=seed_value^identity
		var rank:=random.randf()
		var position:Vector3=HOMES[id]
		for turn in rotation:position=Vector3(1-position.z,position.y,position.x)
		anchors.append({"key":identity,"position":Vector3(origin)+position,"yaw":-rotation*PI*.5,"pose":random.randi_range(1,2),"rank":rank})
	anchors.sort_custom(func(first:Dictionary,second:Dictionary):return first.key<second.key if first.rank==second.rank else first.rank<second.rank)
	anchors=anchors.slice(0,(anchors.size()+1)/2)
	for anchor:Dictionary in anchors:anchor.erase("rank")
	anchors.append_array(church_anchors)
	anchors.sort_custom(func(first:Dictionary,second:Dictionary):return first.key<second.key)
	return {"ok":true,"anchors":anchors}

static func populate(game:Node,lots:Array)->Dictionary:
	var planned:=plan(lots,game.terrain.backend.world_seed)
	if not planned.ok:return planned
	var store:RefCounted=game.zombies.population.store
	if not store.initialize(game.terrain.backend.world_seed,game._initial_generation_spawn):return {"ok":false,"reason":"Sleeper population identity mismatch"}
	var result:Dictionary=store.register_sleepers(planned.anchors)
	if result.ok:game.terrain.changed_since_save=true;game.zombies.population.reset_stream()
	return result
