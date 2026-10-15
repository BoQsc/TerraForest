# SPDX-License-Identifier: 0BSD
# Rebuildable data ONLY. Canonical world.trw is never changed by this class.
# Accessed by one terrain worker; headers are checked before native-array decoding.
extends RefCounted
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
const MAGIC: int = 0x36435254
const LIMIT_BYTES: int = 512 * 1024 * 1024
const MAX_PACKET: int = 64 * 1024 * 1024
var base_path: String = "user://derived_046"
var cache_directory: String = ""
var total_bytes: int = 0
var hits: int = 0
var misses: int = 0
var writes: int = 0
var corrupt: int = 0
var write_failures: int = 0
var enabled: bool = true
var signature: String = ""
const INDEX_LIMIT: int = 262144
var geometry_directories: Dictionary = {}
var geometry_index_complete: bool = false
const SCAN_ENTRY_LIMIT := 2048
const SCAN_TIME_US := 50000
var accounting_complete := false
var scan_entries := 0
var _scan_pending: Array[Dictionary]=[]
var _scan_directory: DirAccess
var _scan_path: String=""
var _scan_depth:=0
var _scan_total:=0
var _scan_failed:=false
# Native index owns the cross-process lease and one-file checked eviction.
var _cache_owner: RefCounted
var _lease_owned:=false
var byte_limit: int=LIMIT_BYTES
var _eviction_target: int=-1
var _eviction_exhausted:=false
var evictions:=0
var evicted_bytes:=0
const DEFAULT_FREE_RESERVE: int=1024*1024*1024
var minimum_free_bytes: int=DEFAULT_FREE_RESERVE
var last_available_bytes: int=-1
var reserve_blocked:=false
var reserve_skips:=0
var _space_retry_usec:=0

func _close_scan() -> void:
	if _scan_directory!=null: _scan_directory.list_dir_end()
	_scan_directory=null
	_scan_pending.clear()


static func digest(data: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish()

func configure(compatibility: String, snapshot: String, style: int, path: String = "user://derived_046") -> void:
	_close_scan()
	if _cache_owner!=null:_cache_owner.release()
	_cache_owner=null;_lease_owned=false;_eviction_target=-1;_eviction_exhausted=false
	reserve_blocked=false;last_available_bytes=-1;_space_retry_usec=0
	base_path = path
	signature = ("trm5:046:" + compatibility + ":" + str(style)).sha256_text()
	cache_directory = base_path.path_join(signature).path_join(snapshot) if _safe_component(snapshot) else ""
	geometry_directories.clear()
	geometry_index_complete = false
	total_bytes = 0
	accounting_complete = false
	# A disabled cache must not enumerate historical files or build an index.
	# Re-enabling requires configure() again to restore quota accounting.
	if not enabled: return
	if byte_limit<4096 or byte_limit>LIMIT_BYTES:return
	# Missing native ownership means read-only caching, never unlocked eviction.
	if not ClassDB.class_exists("NativeDerivedCacheIndex"):return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_path))
	_cache_owner=ClassDB.instantiate("NativeDerivedCacheIndex")
	_lease_owned=_cache_owner.acquire(ProjectSettings.globalize_path(base_path))
	if not _lease_owned:return
	set_snapshot(snapshot)
	# Writes require a complete inventory; eviction runs in later idle slices.
	total_bytes = _size(base_path)
	# Unknown usage means read-only cache, never a partial quota estimate.
	if not accounting_complete: return
	if total_bytes>=byte_limit:_request_space(0)
	geometry_index_complete = true
	var index_deadline:=Time.get_ticks_usec()+SCAN_TIME_US
	var directory := DirAccess.open(base_path.path_join(signature).path_join("geometry_v1"))
	if directory != null:
		directory.list_dir_begin()
		var name := directory.get_next()
		while not name.is_empty():
			if Time.get_ticks_usec()>=index_deadline or geometry_directories.size()>=SCAN_ENTRY_LIMIT:
				geometry_index_complete=false
				break
			if directory.current_is_dir() and name != "." and name != "..":
				if geometry_directories.size() >= INDEX_LIMIT:
					geometry_index_complete = false
					break
				geometry_directories[name] = true
			name = directory.get_next()
		directory.list_dir_end()

func _size(path: String) -> int:
	_close_scan()
	scan_entries=0;accounting_complete=false;_scan_total=0;_scan_failed=false
	_scan_pending=[{"path":path,"depth":0}]
	_scan_slice(SCAN_ENTRY_LIMIT,SCAN_TIME_US)
	return _scan_total if accounting_complete else LIMIT_BYTES

func accounting_pending() -> bool:
	return enabled and _lease_owned and ((not accounting_complete and not _scan_failed) or _eviction_target>=0)

func advance_accounting() -> void:
	# Called by the owning worker between non-interactive mesh jobs. A slice
	# never authorizes writes from a partial total and never restarts at root.
	if not enabled or not _lease_owned or _scan_failed:
		return
	if accounting_complete:
		if _eviction_target>=0:
			if total_bytes<=_eviction_target:_eviction_target=-1;return
			var result: Dictionary=_cache_owner.evict_one()
			if result.ok:
				total_bytes-=int(result.bytes);evictions+=1;evicted_bytes+=int(result.bytes)
			elif result.reason=="empty":_eviction_target=-1;_eviction_exhausted=true
			elif result.reason=="busy":
				# Another reader can temporarily deny delete sharing. Retry on the
				# next space request, not in a hot idle loop; accounting is intact.
				_eviction_target=-1
			else:
				# External changes invalidate accounting. Stop writes and eviction.
				_eviction_target=-1;_scan_failed=true;accounting_complete=false
			return
		return
	_scan_slice(32,2000)
	if accounting_complete:
		total_bytes=_scan_total
		if total_bytes>=byte_limit:_request_space(0)

func _scan_slice(entry_budget: int,time_budget_us: int) -> void:
	var deadline:=Time.get_ticks_usec()+time_budget_us
	var limit:=scan_entries+entry_budget
	while scan_entries<limit and Time.get_ticks_usec()<deadline:
		if _scan_directory==null:
			if _scan_pending.is_empty(): accounting_complete=true;return
			var entry: Dictionary=_scan_pending.pop_back()
			_scan_path=entry.path;_scan_depth=entry.depth
			if _scan_depth>32: _scan_failed=true;_close_scan();return
			_scan_directory=DirAccess.open(_scan_path)
			if _scan_directory!=null:_scan_directory.include_hidden=true
			if _scan_directory==null or _scan_directory.list_dir_begin()!=OK:
				_scan_failed=true;_close_scan();return
		var name:=_scan_directory.get_next()
		if name.is_empty():
			_scan_directory.list_dir_end();_scan_directory=null;continue
		if name=="." or name=="..":continue
		if _scan_path==base_path and name==".terraforest-derived.lock":continue
		scan_entries+=1
		if scan_entries>INDEX_LIMIT:_scan_failed=true;_close_scan();return
		if _scan_directory.is_link(name):_scan_failed=true;_close_scan();return
		var child:=_scan_path.path_join(name)
		if _scan_directory.current_is_dir():
			if not _cache_owner.safe_directory(ProjectSettings.globalize_path(child)):_scan_failed=true;_close_scan();return
			if _scan_pending.size()>=INDEX_LIMIT: _scan_failed=true;_close_scan();return
			_scan_pending.append({"path":child,"depth":_scan_depth+1})
		else:
			var file:=FileAccess.open(child,FileAccess.READ)
			if file==null: _scan_failed=true;_close_scan();return
			_scan_total+=file.get_length();file.close()
			_cache_owner.track(ProjectSettings.globalize_path(child))

static func _safe_component(value: String) -> bool:
	if value.is_empty() or value.length()>128:return false
	for i in value.length():
		var c:=value.unicode_at(i)
		if not ((c>=48 and c<=57) or (c>=65 and c<=90) or (c>=97 and c<=122) or c==95 or c==45):return false
	return true

func _writable_parent(path: String) -> bool:
	if not _lease_owned or path.is_empty():return false
	var parent:=ProjectSettings.globalize_path(path).get_base_dir()
	while not DirAccess.dir_exists_absolute(parent):
		var next:=parent.get_base_dir()
		if next==parent or next.is_empty():return false
		parent=next
	return _cache_owner.safe_directory(parent)

func set_snapshot(snapshot: String) -> void:
	cache_directory = base_path.path_join(signature).path_join(snapshot) if _safe_component(snapshot) else ""
	if cache_directory.is_empty():return
	if enabled and _lease_owned and _writable_parent(cache_directory.path_join("packet")):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_directory))

func _name(key: Vector3i, content: String = "") -> String:
	if (content.is_empty() and cache_directory.is_empty()) or (not content.is_empty() and not _safe_component(content)):return ""
	if not content.is_empty():
		return base_path.path_join(signature).path_join("geometry_v1").path_join(content).path_join("%d_%d_%d.trc" % [key.x, key.y, key.z])
	return cache_directory.path_join("%d_%d_%d.trc" % [key.x, key.y, key.z])

func _reject(key: Vector3i, bytes: int, content: String = "") -> PackedByteArray:
	corrupt += 1
	if accounting_complete and not _scan_failed and _writable_parent(_name(key,content)) and DirAccess.remove_absolute(ProjectSettings.globalize_path(_name(key, content))) == OK:
		_cache_owner.forget(ProjectSettings.globalize_path(_name(key, content)))
		total_bytes = maxi(0, total_bytes - bytes)
	return PackedByteArray()

func load_packet(key: Vector3i, content: String = "") -> PackedByteArray:
	if not enabled or _name(key,content).is_empty():
		return PackedByteArray()
	# Only positive directory entries are retained. Unbounded edit history must
	# not grow a negative cache; a miss here is still safe to reconstruct.
	if not content.is_empty() and geometry_index_complete and not geometry_directories.has(content):
		misses += 1
		return PackedByteArray()
	var f := FileAccess.open(_name(key, content), FileAccess.READ)
	if f == null:
		misses += 1
		return PackedByteArray()
	var length: int = f.get_length()
	if length < 76 or length > MAX_PACKET + 40:
		f.close()
		return _reject(key, length, content)
	var header: PackedByteArray = f.get_buffer(40)
	var data: PackedByteArray = f.get_buffer(length - 40)
	f.close()
	if header.size() != 40 or header.decode_u32(0) != MAGIC or header.decode_u32(4) != data.size() or digest(data) != header.slice(8, 40):
		return _reject(key, length, content)
	if data.size() < 36 or data.decode_u32(0) != Codec.MESH_MAGIC or data.decode_u32(4) != 5 or Vector3i(data.decode_u32(8), data.decode_u32(12), data.decode_u32(16)) != key:
		return _reject(key, length, content)
	hits += 1
	if _lease_owned:_cache_owner.touch(ProjectSettings.globalize_path(_name(key, content)))
	return data

func store_packet(key: Vector3i, data: PackedByteArray, content: String = "") -> void:
	if not enabled or data.size() < 36 or data.size() > MAX_PACKET:
		return
	var path: String = _name(key, content)
	if path.is_empty():return
	if FileAccess.file_exists(path):return
	if not _request_space(data.size()+40):return
	if not _drive_has_space(data.size()+40):return
	if not _writable_parent(path):return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
		write_failures += 1
		return
	var head := PackedByteArray()
	head.resize(8)
	head.encode_u32(0, MAGIC)
	head.encode_u32(4, data.size())
	head.append_array(digest(data))
	var temp: String = path + ".tmp.%d" % OS.get_process_id()
	if FileAccess.file_exists(temp) or DirAccess.open(temp.get_base_dir()).is_link(temp.get_file()):write_failures+=1;return
	var f := FileAccess.open(temp, FileAccess.WRITE)
	if f == null:
		write_failures += 1
		return
	f.store_buffer(head)
	f.store_buffer(data)
	f.flush()
	var ok: bool = f.get_error() == OK and f.get_length() == data.size() + 40
	f.close()
	if ok and DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path)) == OK:
		total_bytes += data.size() + 40
		writes += 1
		_cache_owner.track(ProjectSettings.globalize_path(path));_eviction_exhausted=false
		if not content.is_empty():
			if geometry_directories.size() < INDEX_LIMIT: geometry_directories[content] = true
			else: geometry_index_complete = false
	else:
		write_failures += 1
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))

func _drive_has_space(bytes: int) -> bool:
	# Optional derived writes only. Do not treat this as a reservation against
	# other processes or as protection for canonical-save writes.
	if reserve_blocked and Time.get_ticks_usec()<_space_retry_usec:
		reserve_skips+=1;return false
	last_available_bytes=_cache_owner.available_bytes() if _cache_owner!=null else -1
	reserve_blocked=minimum_free_bytes<0 or last_available_bytes<bytes or last_available_bytes-bytes<minimum_free_bytes
	if reserve_blocked:
		reserve_skips+=1;_space_retry_usec=Time.get_ticks_usec()+2000000
	return not reserve_blocked

func _request_space(bytes: int) -> bool:
	if not _lease_owned or not accounting_complete or _scan_failed or bytes>byte_limit:return false
	if total_bytes+bytes<=byte_limit and total_bytes<byte_limit:return true
	if not _eviction_exhausted:
		var target:=maxi(0,byte_limit-maxi(bytes,byte_limit/8))
		_eviction_target=target if _eviction_target<0 else mini(target,_eviction_target)
	return false

func counters() -> Dictionary:
	return {"hits": hits, "misses": misses, "writes": writes, "corrupt": corrupt,
		"write_failures": write_failures, "disk_bytes": total_bytes, "enabled": enabled,
		"accounting_complete":accounting_complete,"scan_entries":scan_entries,"cache_read_only":enabled and (not accounting_complete or not _lease_owned or total_bytes>=byte_limit or reserve_blocked),
		"minimum_free_bytes":minimum_free_bytes,"last_available_bytes":last_available_bytes,"reserve_blocked":reserve_blocked,"reserve_skips":reserve_skips,
		"lease_owned":_lease_owned,"evictions":evictions,"evicted_bytes":evicted_bytes,"eviction_pending":_eviction_target>=0,"byte_limit":byte_limit}
