# SPDX-License-Identifier: 0BSD
extends RefCounted
const Layouts=preload("res://addons/exploration/cave_layouts.gd")
const Watchtowers=preload("res://addons/exploration/watchtower_sites.gd")

static func check_models(game:Node,asset:Resource,origin:Vector3i,rotation:int)->bool:
	var foundation:RefCounted=game.foundation_check
	if not foundation.begin_ground_models(game.terrain,asset,origin,rotation,game.structures.model_collections()):return false
	while foundation.status=="checking" and not game.shutdown_requested:
		foundation.tick(game.terrain);await game.get_tree().process_frame
	return foundation.status=="supported"

static func publish(game:Node,sites:Array)->Dictionary:
	var layouts:=Layouts.load_catalog();var anchors:Array=[];var published:Array=[]
	if layouts.is_empty():return {"ok":false,"reason":"Exploration catalog unavailable"}
	for site:Dictionary in sites:
		var tower:bool=site.id=="watchtower_w1"
		var matching:=layouts.filter(func(value:Dictionary):return value.id==site.id)
		if not tower and matching.size()!=1:return {"ok":false,"reason":"Unknown exploration layout"}
		var layout:Dictionary={"id":site.id,"crates":[Vector3(1.8,7,6.3)]} if tower else matching[0]
		var asset:Resource=Watchtowers.asset() if tower else Layouts.prefab(layout)
		if asset==null:return {"ok":false,"reason":"Invalid exploration prefab"}
		if asset.get_cell_count()>0:
			if not game.foundation_check.begin(game.terrain,asset,site.origin,site.rotation):return {"ok":false,"reason":game.foundation_check.status}
			while game.foundation_check.status=="checking" and not game.shutdown_requested:
				game.foundation_check.tick(game.terrain);await game.get_tree().process_frame
			if game.foundation_check.status!="supported":return {"ok":false,"reason":game.foundation_check.status}
		if not tower and not await check_models(game,asset,site.origin,site.rotation):return {"ok":false,"reason":game.foundation_check.status}
		var placer:RefCounted=ClassDB.instantiate("NativePrefabPlacement")
		var result:Dictionary=placer.place(game.structures.blocks,asset,site.origin,site.rotation,game.structures.model_collections(),[])
		if not result.get("ok",false):return result
		if tower:
			var support:Dictionary=preload("res://addons/structures/foundation_check.gd").block_model_support(game.structures.blocks,asset,site.origin,site.rotation,game.structures.model_collections())
			if not support.get("ok",false):return support
		var ids:PackedInt64Array=result.placements.get("storage/wooden_chest/v1",PackedInt64Array())
		if ids.size()!=layout.crates.size():return {"ok":false,"reason":"Supply publication mismatch"}
		var residents:=Watchtowers.sleepers(site) if tower else Layouts.sleepers(layout,site.origin,site.rotation)
		var random:=RandomNumberGenerator.new();random.seed=site.origin.x^(site.origin.z<<11)^(site.origin.y<<22)^layout.id.hash()^game.terrain.backend.world_seed
		for identity in ids:
			var stock:=PackedInt64Array([102,random.randi_range(3,7),202 if layout.id=="survey_mine" else 203,random.randi_range(2,5),6,1])
			if not game.storage.store.seed_contents(identity,stock) or not game.storage.collection.set_removal_protected(identity,true):return {"ok":false,"reason":"Supply storage rejected"}
		anchors.append_array(residents)
		published.append({"id":site.id,"origin":site.origin,"rotation":site.rotation,"chests":ids,"sleepers":residents})
	var store:RefCounted=game.zombies.population.store
	if not store.initialize(game.terrain.backend.world_seed,game._initial_generation_spawn):return {"ok":false,"reason":"Exploration population mismatch"}
	var registered:Dictionary=store.register_sleepers(anchors)
	if not registered.get("ok",false):return registered
	game.terrain.changed_since_save=true;game.zombies.population.reset_stream()
	return {"ok":true,"sites":published,"population":registered}
