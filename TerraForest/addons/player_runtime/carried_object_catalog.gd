# SPDX-License-Identifier: 0BSD
extends RefCounted
## Stable inventory IDs; existing model collections remain the world/save owners.
static var ITEMS: Dictionary=_items()
static var TITLES: Dictionary=_titles()
static func supports(item:int)->bool:return item==222 or ITEMS.has(item)

static func _items() -> Dictionary:
	var result: Dictionary={701:"Wooden table",702:"Wooden chair",703:"Wooden shelf",704:"Wooden storage chest",705:"Wooden ladder",706:"Wooden fence",707:"Wood framed window"}
	result.merge(preload("res://addons/structures/pack_registry.gd").item_names())
	return result

static func _titles() -> Dictionary:
	var result: Dictionary={701:"Wooden table",702:"Wooden chair",703:"Wooden shelf",704:"Wooden storage chest (E open)",705:"Wooden ladder (W/S climb, Space jump off)",706:"Wooden fence",707:"Wood framed window"}
	result.merge(preload("res://addons/structures/pack_registry.gd").item_names(true))
	return result
