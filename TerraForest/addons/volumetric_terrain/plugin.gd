@tool
extends EditorPlugin

# Installed only in the editor process that produces a qualification pack.
var _water_export:EditorExportPlugin

func _enter_tree() -> void:
	if not OS.get_environment("TERRAFOREST_WATER_QUALIFICATION_PACK").is_empty():
		_water_export=load("res://tools/water_release_export.gd").new()
		add_export_plugin(_water_export)
	add_custom_type("TerrainWorld", "Node3D", preload("res://addons/volumetric_terrain/terrain_world.gd"), null)

func _exit_tree() -> void:
	if _water_export!=null:remove_export_plugin(_water_export)
	remove_custom_type("TerrainWorld")
