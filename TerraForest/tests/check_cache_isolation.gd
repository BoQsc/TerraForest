# SPDX-License-Identifier: 0BSD
extends SceneTree

func _initialize() -> void:
	var path: String=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--derived-cache="):path=arg.trim_prefix("--derived-cache=")
	var cache=load("res://addons/volumetric_terrain/derived_cache.gd").new()
	if not path.begins_with("user://check_cache_isolation_") or not cache._safe_component(path.trim_prefix("user://")) or DirAccess.dir_exists_absolute(path):
		push_error("A fresh launcher-owned cache argument is required");quit(2);return
	if not ClassDB.class_exists("NativeDerivedCacheIndex"):
		GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	cache.configure("fixture","snapshot",0,path)
	var stats: Dictionary=cache.counters()
	var ok: bool=cache.base_path==path and stats.lease_owned and stats.accounting_complete
	print("CACHE_ISOLATION actual_path=",ProjectSettings.globalize_path(cache.base_path))
	cache=null
	if ok:print("PASS CACHE_ISOLATION fresh owned directory")
	else:push_error("Isolated cache ownership/accounting failed")
	quit(0 if ok else 1)
