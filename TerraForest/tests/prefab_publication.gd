# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var library=preload("res://addons/structures/prefab_library.gd").new()
	library.directory="user://tests/prefab_publication_%d"%Time.get_ticks_usec()
	var asset: Resource=ClassDB.instantiate("NativeBlockPrefab")
	asset.configure(PackedInt32Array([0,0,0,1]))
	asset.set_meta("authoring_notes","x".repeat(9*1024*1024))
	var result: Dictionary=library._save_asset(asset,"Oversized metadata")
	check(not result.ok and library.assets.is_empty(),"unreadable oversized save is not reported as published")
	check(DirAccess.get_files_at(library.directory).is_empty() and DirAccess.get_directories_at(library.directory).is_empty(),"failed publication leaves no final or pending asset")
	asset.remove_meta("authoring_notes")
	asset.set_meta("street_lines",PackedVector3Array([Vector3.ZERO,Vector3(20,0,0)]))
	result=library._save_asset(asset,"Valid layout")
	check(result.ok,"valid layout publishes")
	var reopened=preload("res://addons/structures/prefab_library.gd").new();reopened.directory=library.directory;reopened.load_library()
	check(reopened.assets.size()==1 and reopened.assets[0].get_records()==asset.get_records() and reopened.assets[0].get_meta("street_lines")==asset.get_meta("street_lines"),"published asset reopens with exact geometry and road metadata")
	for file in DirAccess.get_files_at(library.directory):DirAccess.remove_absolute(library.directory.path_join(file))
	DirAccess.remove_absolute(library.directory)
	print("PREFAB_PUBLICATION failures=",failures);quit(1 if failures else 0)
