# SPDX-License-Identifier: 0BSD
extends RefCounted
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
	return result
