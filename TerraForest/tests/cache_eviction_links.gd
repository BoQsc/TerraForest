# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var args:=OS.get_cmdline_user_args()
	if args.is_empty() or not args[0].is_absolute_path() or not DirAccess.dir_exists_absolute(args[0].path_join("root")):
		push_error("Supply an absolute prepared junction fixture as the first user argument; this test does not use run_godot_check.py.")
		quit(2);return
	var fixture: String=args[0]
	var index: RefCounted=ClassDB.instantiate("NativeDerivedCacheIndex")
	var ok: bool=not index.acquire(fixture.path_join("linked_root"))
	print("LINK root junction rejected=",ok)
	ok=ok and index.acquire(fixture.path_join("root"))
	var candidate: String=fixture.path_join("root").path_join("a".repeat(64)).path_join("b".repeat(64)).path_join("0_0_0.trc")
	ok=ok and not index.track(candidate) and not index.evict_one().ok and FileAccess.file_exists(candidate)
	print("LINK candidate through child junction cannot be tracked/deleted=",ok)
	index.release()
	var cache=load("res://addons/volumetric_terrain/derived_cache.gd").new()
	cache.configure("fixture","snapshot",0,fixture.path_join("root"))
	for i in 100:
		if not cache.accounting_pending():break
		cache.advance_accounting()
	ok=ok and not cache.accounting_complete and not cache.accounting_pending() and cache.writes==0
	print("LINK accounting fails closed without traversing child junction=",ok)
	cache.cache_directory=candidate.get_base_dir()
	var before:=FileAccess.get_file_as_bytes(candidate)
	ok=ok and cache.load_packet(Vector3i.ZERO).is_empty() and FileAccess.get_file_as_bytes(candidate)==before
	print("LINK corrupt-packet cleanup cannot delete through junction=",ok)
	cache._cache_owner.release();quit(0 if ok else 1)
