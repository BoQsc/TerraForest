@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_custom_type("WorldEcosystem", "Node", preload("res://addons/world_ecosystem/world_ecosystem.gd"), null)

func _exit_tree() -> void:
	remove_custom_type("WorldEcosystem")
