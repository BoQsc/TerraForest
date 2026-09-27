@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_custom_type("VegetationWorld", "Node3D", preload("res://addons/vegetation/vegetation_world.gd"), null)

func _exit_tree() -> void:
	remove_custom_type("VegetationWorld")
