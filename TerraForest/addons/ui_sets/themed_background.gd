# SPDX-License-Identifier: 0BSD
extends "res://addons/world_runtime/loading_background.gd"
func _ready()->void:
	super._ready()
	var set:Resource=get_meta("ui_set")
	get_child(0).color=set.background
