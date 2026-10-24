# SPDX-License-Identifier: 0BSD
extends SceneTree
# CLI compatibility; the game hosts the same task in its persistent window.
var task:Node
func _initialize()->void:
 task=preload("res://addons/world_runtime/generation_coordinator.gd").new();task.root=root
 task.external_stages=DisplayServer.get_name()=="headless"
 task.finished.connect(func(code:int):quit(code));root.add_child(task)
