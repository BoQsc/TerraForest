# SPDX-License-Identifier: 0BSD
extends SceneTree
var task:Node
func _initialize()->void:
 task=preload("res://addons/world_runtime/generate_world_task.gd").new();task.root=root;task.qualification=true
 task.finished.connect(func(code:int):quit(code));root.add_child(task)
