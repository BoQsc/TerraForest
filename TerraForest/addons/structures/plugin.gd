@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_custom_type("PrimitivePreset","Resource",preload("res://addons/structures/primitive_preset.gd"),null)

func _exit_tree() -> void:
	remove_custom_type("PrimitivePreset")
