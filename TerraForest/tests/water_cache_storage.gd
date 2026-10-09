# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:
	var cache=preload("res://addons/volumetric_terrain/derived_cache.gd").new()
	var path:="user://water_cache_test_%d"%Time.get_ticks_usec()
	cache.configure("test","test",0,path)
	var key: PackedByteArray="test".sha256_buffer();var data:=PackedByteArray();data.resize(104)
	cache.accounting_complete=false
	check(not cache.store_lake(key,data) and cache._pending_lakes.size()==1 and not FileAccess.file_exists(cache._lake_name(key)),"incomplete accounting defers write")
	cache.store_lake(key,data)
	check(cache._pending_lakes.size()==1 and cache._pending_lake_bytes==104,"duplicate deferred bake does not grow queue")
	cache.accounting_complete=true;cache.advance_accounting()
	check(cache._pending_lakes.is_empty() and cache.load_lake(key)==data and cache.total_bytes==144,"one deferred write flushes with exact quota accounting")
	cache.total_bytes=cache.LIMIT_BYTES
	check(not cache.store_lake("over-quota".sha256_buffer(),data),"shared disk quota prevents writes")
	cache.accounting_complete=false
	for i in 40:cache.store_lake(str(i).sha256_buffer(),data)
	check(cache._pending_lakes.size()==16 and cache._pending_lake_bytes==1664,"deferred queue bounded to sixteen entries")
	cache.enabled=false;cache.advance_accounting()
	check(cache._pending_lakes.is_empty() and cache._pending_lake_bytes==0,"disabled cache releases deferred buffers")
	var f:=FileAccess.open("res://reports/water_cache_storage.json",FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));f.close();quit(1 if failures else 0)
