# SPDX-License-Identifier: 0BSD
# Compatibility entry for developer generation/reopen review scripts.
extends "res://addons/world_runtime/generate_world.gd"
func _initialize()->void:
 qualification=true
 run.call_deferred()
