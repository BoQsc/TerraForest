# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:
	var cache=load("res://addons/volumetric_terrain/derived_cache.gd").new()
	var path: String="user://cache_scan_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(path)
	for i in range(2100):
		var f:=FileAccess.open(path.path_join(str(i)),FileAccess.WRITE);f.store_8(7);f.close()
	var start:=Time.get_ticks_usec()
	cache.configure("fixture","snapshot",0,path)
	print("SCAN duration_us=",Time.get_ticks_usec()-start," entries=",cache.scan_entries)
	check(not cache.accounting_complete and cache.scan_entries<=2048 and not cache.geometry_index_complete,"large cache stops within entry budget and uses read-only accounting")
	var packet:=PackedByteArray();packet.resize(36)
	packet.encode_u32(0,preload("res://addons/volumetric_terrain/mesh_codec.gd").MESH_MAGIC)
	packet.encode_u32(4,5)
	cache.store_packet(Vector3i.ZERO,packet)
	check(cache.writes==0 and not FileAccess.file_exists(cache._name(Vector3i.ZERO)),"incomplete accounting never authorizes new disk writes")
	# Reconfiguration after explicit cleanup restores writes only with full usage.
	for i in range(2100): DirAccess.remove_absolute(path.path_join(str(i)))
	cache.configure("fixture","snapshot",0,path)
	check(cache.accounting_complete and cache.total_bytes==0,"small empty cache obtains complete accounting")
	cache.store_packet(Vector3i.ZERO,packet)
	check(cache.writes==1 and cache.total_bytes==76,"complete accounting permits quota-checked writes")
	cache.accounting_complete=false;cache.geometry_index_complete=false
	check(cache.load_packet(Vector3i.ZERO)==packet,"read-only accounting preserves checksum-validated cache reads")
	DirAccess.remove_absolute(cache._name(Vector3i.ZERO))
	DirAccess.remove_absolute(cache.cache_directory)
	DirAccess.remove_absolute(cache.cache_directory.get_base_dir())
	DirAccess.remove_absolute(path)
	print("CACHE_SCAN_BUDGET failures=",failures)
	quit(1 if failures else 0)
