# SPDX-License-Identifier: 0BSD
extends RefCounted
static func salvage_recipes() -> Dictionary:
	var result: Dictionary=preload("res://addons/structures/furniture_catalog.gd").salvage_recipes()
	# Partial recovery, below construction cost; glass is not a separate item yet.
	result[preload("res://addons/structures/window_catalog.gd").KEY]=PackedInt64Array([102,2])
	result[preload("res://addons/structures/door_catalog.gd").KEY]=PackedInt64Array([102,3])
	result[preload("res://addons/structures/guardrail_catalog.gd").KEY]=PackedInt64Array([104,2])
	return result
# Recipes for model attachments use the same definitions as individual placement.
static func recipes() -> Dictionary:
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
	return result
