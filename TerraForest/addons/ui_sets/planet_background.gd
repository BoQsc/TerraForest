# SPDX-License-Identifier: 0BSD
extends "res://addons/ui_sets/themed_background.gd"
func _ready()->void:
	super._ready()
	var planet:Control=preload("res://demo/world_screens/planet.gd").new()
	planet.radius_px=180.;planet.tree_count=900
	planet.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	planet.position=Vector2(20,80)
	planet.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(planet);move_child(planet,2)
