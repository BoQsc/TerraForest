# SPDX-License-Identifier: 0BSD
extends "res://addons/player_runtime/tool_view.gd"
## Install before entering the tree so ordinary attack signal wiring is reused.
func _init()->void:
	human.free()
	human=preload("res://addons/characters/experiments/pickaxe_crosscut_view.gd").new()
