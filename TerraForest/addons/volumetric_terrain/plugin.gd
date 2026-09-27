@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_custom_type("TerrainWorld", "Node3D", preload("res://addons/volumetric_terrain/terrain_world.gd"), null)

func _exit_tree() -> void:
	remove_custom_type("TerrainWorld")
