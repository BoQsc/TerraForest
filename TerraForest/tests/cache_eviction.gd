# SPDX-License-Identifier: 0BSD
extends SceneTree
const Cache=preload("res://addons/volumetric_terrain/derived_cache.gd")
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func packet(key: Vector3i) -> PackedByteArray:
	var data:=PackedByteArray();data.resize(1000)
	data.encode_u32(0,0x324d5254);data.encode_u32(4,5)
	data.encode_s32(8,key.x);data.encode_s32(12,key.y);data.encode_s32(16,key.z)
	return data
func drain(cache: RefCounted) -> void:
	for i in 10000:
		if not cache.accounting_pending():return
		cache.advance_accounting()
	check(false,"idle maintenance terminates within bounded fixture calls")
func _initialize() -> void:run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var path: String="user://cache_eviction_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cache-root="):path=arg.trim_prefix("--cache-root=")
	var cache:=Cache.new();cache.byte_limit=4096
	var snapshot: String="fixture".sha256_text()
	if "--contender" in OS.get_cmdline_user_args():
		cache.configure("fixture",snapshot,0,path)
		check(not cache.counters().lease_owned and not cache.accounting_pending(),"competing process stays read-only without maintenance spin")
		check(cache.load_packet(Vector3i.ZERO)==packet(Vector3i.ZERO),"competing process retains valid cache reads")
		cache.store_packet(Vector3i(999,0,0),packet(Vector3i(999,0,0)))
		check(not FileAccess.file_exists(cache._name(Vector3i(999,0,0))),"competing process cannot write")
		quit(1 if failures else 0);return
	DirAccess.make_dir_recursive_absolute(path)
	var canonical:=FileAccess.open(path.path_join("world.trw"),FileAccess.WRITE);canonical.store_string("canonical fixture");canonical.close()
	var unknown:=FileAccess.open(path.path_join("keep.bin"),FileAccess.WRITE);unknown.store_string("unknown fixture");unknown.close()
	check(FileAccess.set_hidden_attribute(path.path_join("keep.bin"),true)==OK,"hidden unknown file participates in quota fixture")
	cache.configure("fixture",snapshot,0,path);drain(cache)
	check(cache.counters().lease_owned and cache.accounting_complete,"exclusive owner obtains complete initial accounting")
	for i in 3:cache.store_packet(Vector3i(i,0,0),packet(Vector3i(i,0,0)))
	check(cache.writes==3 and cache.total_bytes==3152,"three packets fit with canonical and unknown bytes counted")
	check(cache.load_packet(Vector3i.ZERO)==packet(Vector3i.ZERO),"read touches oldest packet")
	cache.store_packet(Vector3i(3,0,0),packet(Vector3i(3,0,0)))
	check(cache.writes==3 and cache.counters().eviction_pending and cache.evictions==0,"full-quota foreground request schedules eviction without deleting")
	drain(cache)
	check(cache.evictions==1 and FileAccess.file_exists(cache._name(Vector3i.ZERO)) and not FileAccess.file_exists(cache._name(Vector3i(1,0,0))),"idle eviction preserves recently read packet and removes older cold packet")
	cache.store_packet(Vector3i(3,0,0),packet(Vector3i(3,0,0)))
	check(cache.writes==4 and cache.total_bytes==3152,"new cache writes resume after eviction")
	var bounded:=true
	for i in range(4,24):
		cache.load_packet(Vector3i.ZERO)
		cache.store_packet(Vector3i(i,0,0),packet(Vector3i(i,0,0)));drain(cache)
		cache.store_packet(Vector3i(i,0,0),packet(Vector3i(i,0,0)))
		bounded=bounded and cache.total_bytes<=4096 and cache._cache_owner.count()<=3 and cache.load_packet(Vector3i(i,0,0))==packet(Vector3i(i,0,0))
	check(bounded and cache.evictions==21,"continued travel-sized writes maintain byte/index bounds and remain readable")
	var before: int=cache.writes
	cache.store_packet(Vector3i.ZERO,packet(Vector3i.ZERO),"../../outside")
	check(cache.writes==before and cache.load_packet(Vector3i.ZERO,"../../outside").is_empty(),"unsafe cache component is rejected")
	check(FileAccess.get_file_as_string(path.path_join("world.trw"))=="canonical fixture" and FileAccess.get_file_as_string(path.path_join("keep.bin"))=="unknown fixture","canonical and unknown files remain byte-identical")
	var output: Array=[]
	var code:=OS.execute(OS.get_executable_path(),PackedStringArray(["--headless","--path",ProjectSettings.globalize_path("res://"),"--script","res://tests/cache_eviction.gd","--","--contender","--cache-root="+path]),output,true)
	for line in output:print(line)
	check(code==0,"separate-process lease/read-only checks pass")
	# The reader's Windows handle denies delete sharing until close.
	for i in 24:cache._cache_owner.forget(ProjectSettings.globalize_path(cache._name(Vector3i(i,0,0))))
	var held_path: String=cache._name(Vector3i(23,0,0))
	check(cache._cache_owner.track(ProjectSettings.globalize_path(held_path)),"reader-contention candidate indexed")
	var reader:=FileAccess.open(held_path,FileAccess.READ)
	cache._eviction_target=0;cache.advance_accounting()
	check(cache.accounting_complete and FileAccess.file_exists(held_path) and not cache.accounting_pending(),"busy reader preserves packet and accounting without idle spin")
	reader.close()
	cache._eviction_target=0;cache.advance_accounting()
	check(not FileAccess.file_exists(held_path) and cache.accounting_complete,"eviction succeeds after reader closes")
	# Simulate external mutation after inventory: identity/size/stamp must be rechecked.
	for i in 24:cache._cache_owner.forget(ProjectSettings.globalize_path(cache._name(Vector3i(i,0,0))))
	var changed_path: String=cache._name(Vector3i.ZERO)
	check(cache._cache_owner.track(ProjectSettings.globalize_path(changed_path)),"single eviction candidate tracked")
	var file:=FileAccess.open(changed_path,FileAccess.READ_WRITE);file.seek_end();file.store_8(7);file.close()
	cache._eviction_target=0;cache.advance_accounting()
	check(FileAccess.file_exists(changed_path) and not cache.accounting_complete and not cache.accounting_pending(),"changed candidate is retained and accounting fails closed")
	cache._cache_owner.release()
	cache.configure("fixture",snapshot,0,path);drain(cache)
	check(cache.counters().lease_owned and cache.accounting_complete,"released lease can be reacquired and inventory rebuilt")
	# Unknown-only pressure cannot trigger deletion or endlessly retry idle work.
	var other:=Cache.new();other.byte_limit=4096
	var other_path:=path+"_unknown";DirAccess.make_dir_recursive_absolute(other_path)
	file=FileAccess.open(other_path.path_join("world.trw"),FileAccess.WRITE);var bytes:=PackedByteArray();bytes.resize(5000);file.store_buffer(bytes);file.close()
	other.configure("fixture",snapshot,0,other_path);drain(other)
	other.store_packet(Vector3i.ZERO,packet(Vector3i.ZERO))
	check(other.total_bytes==5000 and other.writes==0 and other.evictions==0 and not other.accounting_pending(),"unknown over-quota bytes are preserved without writes or repeated eviction")
	# Recognized packets already exceeding the budget must complete accounting,
	# then retire incrementally instead of disabling caching forever.
	var startup:=Cache.new();startup.byte_limit=4096
	var startup_path:=path+"_startup";startup.configure("fixture",snapshot,0,startup_path)
	for i in 6:
		var key:=Vector3i(i,0,0);var data:=packet(key)
		var head:=PackedByteArray();head.resize(8);head.encode_u32(0,Cache.MAGIC);head.encode_u32(4,data.size());head.append_array(Cache.digest(data))
		file=FileAccess.open(startup._name(key),FileAccess.WRITE);file.store_buffer(head);file.store_buffer(data);file.close()
	startup.configure("fixture",snapshot,0,startup_path)
	check(startup.accounting_complete and startup.total_bytes==6240 and startup.evictions==0,"over-quota startup finishes full accounting before deleting")
	drain(startup)
	check(startup.total_bytes<=4096 and startup.evictions==3 and startup.accounting_complete,"over-quota startup recovers bounded writable cache")
	startup.store_packet(Vector3i(9,0,0),packet(Vector3i(9,0,0)));drain(startup)
	startup.store_packet(Vector3i(9,0,0),packet(Vector3i(9,0,0)))
	check(startup.load_packet(Vector3i(9,0,0))==packet(Vector3i(9,0,0)),"startup recovery accepts new packet")
	startup._cache_owner.release()
	var report:={"checks":checks,"failures":failures,"cache":cache.counters(),"root":ProjectSettings.globalize_path(path),"scope":"Disposable 4KiB quota, real native Windows lease/checked deletion and worker cache adapter. Not a mixed-world latency, disk-pressure or endurance qualification."}
	DirAccess.make_dir_recursive_absolute("res://reports")
	file=FileAccess.open("res://reports/cache_eviction.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	cache._cache_owner.release();other._cache_owner.release();quit(1 if failures else 0)
