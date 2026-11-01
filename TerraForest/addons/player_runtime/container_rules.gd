# SPDX-License-Identifier: 0BSD
extends RefCounted
const PICK_ITEM:=213
const LOCKED_HEALTH_MULTIPLIER:=2
const LOCK_ONE_IN:=5
const CAPACITY:=4096

static func seed_generated(storage:Node,seed_value:int)->Dictionary:
	var ids:PackedInt64Array=storage.collection.get_ids()
	if ids.size()>CAPACITY:return {"ok":false,"reason":"Generated storage capacity exceeded"}
	var locked:=PackedInt64Array()
	for identity in ids:
		var random:=RandomNumberGenerator.new();random.seed=seed_value^identity^0x3e29c45b
		if random.randi_range(1,LOCK_ONE_IN)!=1:continue
		if not storage.store.has_contents(identity):
			var stock:=PackedInt64Array([102,random.randi_range(3,7),202,random.randi_range(2,5),601,random.randi_range(8,20)])
			if not storage.store.seed_contents(identity,stock):return {"ok":false,"reason":"Locked supply admission failed"}
		var health:int=preload("res://addons/player_runtime/durability_catalog.gd").MODELS["storage/wooden_chest/v1"].health*LOCKED_HEALTH_MULTIPLIER
		if not storage.store.seed_lock(identity,health,seed_value&0x7fffffffffffffff) or not storage.protect(identity,true):return {"ok":false,"reason":"Generated lock admission failed"}
		locked.append(identity)
	return {"ok":true,"containers":ids.size(),"locked":locked}
