# SPDX-License-Identifier: 0BSD
extends SceneTree
# CLI compatibility; the game hosts the same task in its persistent window.
var task:Node
func _initialize()->void:
 task=preload("res://addons/world_runtime/capture_world_previews_task.gd").new();task.root=root
 task.finished.connect(func(code:int):quit(code));root.add_child(task)
