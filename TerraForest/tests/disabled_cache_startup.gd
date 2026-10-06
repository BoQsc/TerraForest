# SPDX-License-Identifier: 0BSD
extends SceneTree
class ProbeCache extends "res://addons/volumetric_terrain/derived_cache.gd":
	var scans:=0
	func _size(_path: String) -> int:
		scans+=1
		accounting_complete=true
		return 12345
func _initialize() -> void:
	var cache:=ProbeCache.new()
	cache.enabled=false
	cache.total_bytes=900
	cache.geometry_directories["old"]=true
	cache.geometry_index_complete=true
	cache.configure("fixture","snapshot",0,"user://disabled_cache_probe")
	var ok:=cache.scans==0 and cache.total_bytes==0 and cache.geometry_directories.is_empty() and not cache.geometry_index_complete
	print("DISABLED_CACHE no_scan_and_no_stale_index=",ok)
	cache.enabled=true
	cache.configure("fixture","snapshot",0,"user://disabled_cache_probe")
	ok=ok and cache.scans==1 and cache.total_bytes==12345 and cache.geometry_index_complete
	print("DISABLED_CACHE explicit_reconfigure_restores_accounting=",ok)
	DirAccess.remove_absolute(cache.cache_directory)
	DirAccess.remove_absolute(cache.cache_directory.get_base_dir())
	DirAccess.remove_absolute(cache.base_path)
	quit(0 if ok else 1)
