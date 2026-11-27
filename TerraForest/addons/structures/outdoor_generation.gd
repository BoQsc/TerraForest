# SPDX-License-Identifier: 0BSD
extends RefCounted
## Scene bridge only. NativeOutdoorGeneration owns all generation loops and state.
const Packs=preload("res://addons/structures/pack_registry.gd")
const Tokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
const ATTEMPTS:=48
const ITEMS:=[828,827,822,823,824,825,821,826,829,798,799,736,735]

static func candidates(lot:Dictionary,world_seed:int,roads:Array=[])->Array:
	var job:RefCounted=ClassDB.instantiate("NativeOutdoorGeneration")
	return job.propose(lot,world_seed,roads,Packs.by_item)

static func support_probes(bounds:AABB)->PackedVector3Array:
	var job:RefCounted=ClassDB.instantiate("NativeOutdoorGeneration")
	return job.support_probes(bounds)

static func _support(terrain:Node,bounds:Array[AABB])->Dictionary:
	var job:RefCounted=ClassDB.instantiate("NativeOutdoorGeneration")
	if not job.start_support(terrain,bounds,Tokens.allocate()):return {"ok":false}
	while not job.advance():await terrain.get_tree().process_frame
	return job.get_result()

static func publish(game:Node,lots:Array,roads:Array,world_seed:int)->Dictionary:
	var job:RefCounted=ClassDB.instantiate("NativeOutdoorGeneration")
	if not job.start(game,lots,roads,world_seed,Packs.by_item,Tokens.allocate()):return {"ok":false,"reason":"Native outdoor generation admission failed"}
	while not job.advance():await game.get_tree().process_frame
	return job.get_result()
