# SPDX-License-Identifier: 0BSD
extends RefCounted
static func salvage_recipes(objects: Dictionary = {}) -> Dictionary:
	var result: Dictionary=preload("res://addons/structures/furniture_catalog.gd").salvage_recipes()
	# Partial recovery, below construction cost; glass is not a separate item yet.
	result[preload("res://addons/structures/window_catalog.gd").KEY]=PackedInt64Array([102,2])
	var door=preload("res://addons/structures/door_catalog.gd")
	result[door.KEY]=door.salvage()
	result[preload("res://addons/structures/guardrail_catalog.gd").KEY]=PackedInt64Array([104,2])
	result[preload("res://addons/structures/guardrail_catalog.gd").STAIR_KEY]=PackedInt64Array([104,2])
	result[preload("res://addons/structures/fence_catalog.gd").KEY]=PackedInt64Array([102,2])
	for id: String in objects:
		if objects[id].salvage.is_empty():result.erase(id)
		else:result[id]=preload("res://addons/structures/object_catalog.gd").recipe(objects[id].salvage)
	return result
# Recipes for model attachments use the same definitions as individual placement.
static func recipes(objects: Dictionary = {}) -> Dictionary:
	var result: Dictionary=preload("res://addons/structures/furniture_catalog.gd").recipes()
	var ladder=preload("res://addons/structures/ladder_catalog.gd")
	var chest=preload("res://addons/structures/storage_catalog.gd")
	result[ladder.KEY]=ladder.recipe()
	result[chest.KEY]=chest.recipe()
	var window=preload("res://addons/structures/window_catalog.gd")
	result[window.KEY]=window.recipe()
	var door=preload("res://addons/structures/door_catalog.gd")
	result[door.KEY]=door.recipe()
	var guardrail=preload("res://addons/structures/guardrail_catalog.gd")
	result[guardrail.KEY]=guardrail.recipe()
	result[guardrail.STAIR_KEY]=guardrail.recipe()
	var fence=preload("res://addons/structures/fence_catalog.gd")
	result[fence.KEY]=fence.recipe()
	for id: String in objects:
		result[id]=preload("res://addons/structures/object_catalog.gd").recipe(objects[id].recipe)
	return result
