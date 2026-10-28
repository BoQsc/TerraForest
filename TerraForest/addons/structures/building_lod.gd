extends RefCounted

static func apply(blocks: Node3D) -> void:
	var settings := ConfigFile.new()
	var path: String = preload("res://addons/presentation/fullscreen_policy.gd").settings_path()
	var enabled := true
	if not path.is_empty() and settings.load(path) == OK:
		enabled = bool(settings.get_value("graphics", "building_lod", true))
	blocks.set_geometry_lod_enabled(enabled)

static func set_enabled(blocks: Node3D, enabled: bool, persist: bool) -> void:
	blocks.set_geometry_lod_enabled(enabled)
	var path: String = preload("res://addons/presentation/fullscreen_policy.gd").settings_path()
	if persist and not path.is_empty():
		var settings := ConfigFile.new()
		settings.load(path)
		settings.set_value("graphics", "building_lod", enabled)
		settings.save(path)
