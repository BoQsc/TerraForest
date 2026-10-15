# SPDX-License-Identifier: 0BSD
extends SceneTree
const Cache=preload("res://addons/volumetric_terrain/derived_cache.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func packet(key: Vector3i) -> PackedByteArray:
	var bytes:=PackedByteArray();bytes.resize(1000)
	bytes.encode_u32(0,0x324d5254);bytes.encode_u32(4,5)
	bytes.encode_s32(8,key.x);bytes.encode_s32(12,key.y);bytes.encode_s32(16,key.z)
	return bytes
func _initialize() -> void:run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var native: RefCounted=ClassDB.instantiate("NativeDerivedCacheIndex")
	check(native.available_bytes()==-1,"unowned free space is unknown, never unlimited")
	var path: String="user://cache_free_reserve_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var cache:=Cache.new();cache.configure("reserve_test","snapshot",0,path)
	check(cache._lease_owned and cache.accounting_complete,"isolated cache obtains ownership and accounting")
	var actual: int=cache._cache_owner.available_bytes()
	check(actual>0,"native volume query returns caller-available bytes")
	check(cache.minimum_free_bytes==1073741824,"default reserve is one GiB")
	# Small test writes only. Simulate pressure by raising the threshold, never
	# by filling the user's drive or altering unrelated files.
	cache.minimum_free_bytes=0
	cache.store_packet(Vector3i.ZERO,packet(Vector3i.ZERO))
	check(cache.writes==1,"ample-space cache packet publishes")
	var before:=cache.total_bytes
	var canonical:=path.path_join("world.trw")
	var file:=FileAccess.open(canonical,FileAccess.WRITE);file.store_string("untouched canonical sentinel");file.close()
	cache.minimum_free_bytes=4611686018427387904
	cache.store_packet(Vector3i.ONE,packet(Vector3i.ONE))
	check(cache.reserve_blocked and cache.reserve_skips==1 and cache.counters().cache_read_only,"insufficient reserve makes derived writes read-only")
	check(not FileAccess.file_exists(cache._name(Vector3i.ONE)) and cache.total_bytes==before and cache.writes==1 and cache.evictions==0,"reserve rejection creates no packet or eviction")
	check(cache.load_packet(Vector3i.ZERO)==packet(Vector3i.ZERO),"existing cache remains readable under reserve pressure")
	check(FileAccess.get_file_as_string(canonical)=="untouched canonical sentinel","canonical sentinel is untouched")
	cache.minimum_free_bytes=0
	cache.store_packet(Vector3i.ONE,packet(Vector3i.ONE))
	check(cache.reserve_skips==2 and cache.writes==1,"pressure retry is throttled rather than polling per packet")
	await create_timer(2.1).timeout
	cache.store_packet(Vector3i.ONE,packet(Vector3i.ONE))
	check(cache.writes==2 and not cache.reserve_blocked and cache.load_packet(Vector3i.ONE)==packet(Vector3i.ONE),"writes recover after retry when space is sufficient")
	cache._cache_owner.release()
	cache.store_packet(Vector3i(2,0,0),packet(Vector3i(2,0,0)))
	check(cache.reserve_blocked and cache.last_available_bytes==-1 and cache.writes==2,"unknown query fails closed")
	DirAccess.make_dir_recursive_absolute("res://reports/cache_free_reserve")
	FileAccess.open("res://reports/cache_free_reserve/result.json",FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"initial_available_bytes":actual,"cache":cache.counters(),"scope":"Native free-space query plus threshold simulation; no real disk exhaustion or canonical-save qualification"},"  "))
	print("CACHE_FREE_RESERVE failures=",failures);quit(1 if failures else 0)
