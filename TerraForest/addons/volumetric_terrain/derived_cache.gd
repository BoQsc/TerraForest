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
var _pending_lakes: Dictionary={}
var _pending_lake_bytes:=0

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
	_pending_lakes.clear();_pending_lake_bytes=0
	base_path = path
	signature = ("trm5:046:" + compatibility + ":" + str(style)).sha256_text()
	set_snapshot(snapshot)
	geometry_directories.clear()
	geometry_index_complete = false
	total_bytes = 0
	accounting_complete = false
	# A disabled cache must not enumerate historical files or build an index.
	# Re-enabling requires configure() again to restore quota accounting.
	if not enabled: return
	# Bounded derived disk use; reaching the cap disables writes, not gameplay.
	total_bytes = _size(base_path)
	# Unknown usage means read-only cache, never a partial quota estimate.
	if not accounting_complete: return
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
	return enabled and ((not accounting_complete and not _scan_failed) or not _pending_lakes.is_empty())

func advance_accounting() -> void:
	# Called by the owning worker between non-interactive mesh jobs. A slice
	# never authorizes writes from a partial total and never restarts at root.
	if not enabled or _scan_failed:
		_pending_lakes.clear();_pending_lake_bytes=0;return
	if accounting_complete:
		if not _pending_lakes.is_empty():
			var key: String=_pending_lakes.keys()[0]
			var data: PackedByteArray=_pending_lakes[key]
			_pending_lakes.erase(key);_pending_lake_bytes-=data.size()
			store_lake(key.hex_decode(),data)
		return
	_scan_slice(32,2000)
	if accounting_complete: total_bytes=_scan_total

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
			if _scan_directory==null or _scan_directory.list_dir_begin()!=OK:
				_scan_failed=true;_close_scan();return
		var name:=_scan_directory.get_next()
		if name.is_empty():
			_scan_directory.list_dir_end();_scan_directory=null;continue
		if name=="." or name=="..":continue
		scan_entries+=1
		var child:=_scan_path.path_join(name)
		if _scan_directory.current_is_dir():
			if _scan_pending.size()>=INDEX_LIMIT: _scan_failed=true;_close_scan();return
			_scan_pending.append({"path":child,"depth":_scan_depth+1})
		else:
			var file:=FileAccess.open(child,FileAccess.READ)
			if file==null: _scan_failed=true;_close_scan();return
			_scan_total+=file.get_length();file.close()
			if _scan_total>=LIMIT_BYTES: _scan_failed=true;_close_scan();return

func set_snapshot(snapshot: String) -> void:
	cache_directory = base_path.path_join(signature).path_join(snapshot)
	if enabled:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_directory))

func _name(key: Vector3i, content: String = "") -> String:
	if not content.is_empty():
		return base_path.path_join(signature).path_join("geometry_v1").path_join(content).path_join("%d_%d_%d.trc" % [key.x, key.y, key.z])
	return cache_directory.path_join("%d_%d_%d.trc" % [key.x, key.y, key.z])

func _reject(key: Vector3i, bytes: int, content: String = "") -> PackedByteArray:
	corrupt += 1
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(_name(key, content))) == OK:
		total_bytes = maxi(0, total_bytes - bytes)
	return PackedByteArray()

func load_packet(key: Vector3i, content: String = "") -> PackedByteArray:
	if not enabled:
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
	return data

func store_packet(key: Vector3i, data: PackedByteArray, content: String = "") -> void:
	if not enabled or data.size() < 36 or data.size() > MAX_PACKET:
		return
	var path: String = _name(key, content)
	if not accounting_complete or total_bytes + data.size() + 40 > LIMIT_BYTES:
		return
	if FileAccess.file_exists(path):
		return
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir())) != OK:
		write_failures += 1
		return
	var head := PackedByteArray()
	head.resize(8)
	head.encode_u32(0, MAGIC)
	head.encode_u32(4, data.size())
	head.append_array(digest(data))
	var temp: String = path + ".tmp.%d" % OS.get_process_id()
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
		if not content.is_empty():
			if geometry_directories.size() < INDEX_LIMIT: geometry_directories[content] = true
			else: geometry_index_complete = false
	else:
		write_failures += 1
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))

func counters() -> Dictionary:
	return {"hits": hits, "misses": misses, "writes": writes, "corrupt": corrupt,
		"write_failures": write_failures, "disk_bytes": total_bytes, "enabled": enabled,
		"accounting_complete":accounting_complete,"scan_entries":scan_entries,"cache_read_only":enabled and not accounting_complete}

# Lake payloads share the existing worker-owned quota/accounting and atomic writes.
func _lake_name(identity: PackedByteArray) -> String:
	return base_path.path_join(signature).path_join("lakes_v1").path_join(identity.hex_encode()+".trl")
func reject_lake(identity: PackedByteArray) -> void:
	if identity.size()!=32:return
	var path:=_lake_name(identity)
	var file:=FileAccess.open(path,FileAccess.READ)
	var length:=file.get_length() if file!=null else 0
	if file!=null:file.close()
	corrupt+=1
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(path))==OK:total_bytes=maxi(0,total_bytes-length)
func load_lake(identity: PackedByteArray) -> PackedByteArray:
	if not enabled or identity.size()!=32:return PackedByteArray()
	var file:=FileAccess.open(_lake_name(identity),FileAccess.READ)
	if file==null:misses+=1;return PackedByteArray()
	var length:=file.get_length()
	if length<144 or length>6*1024*1024+40:
		file.close();reject_lake(identity);return PackedByteArray()
	var header:=file.get_buffer(40);var data:=file.get_buffer(length-40);file.close()
	if header.size()!=40 or header.decode_u32(0)!=0x31434c54 or header.decode_u32(4)!=data.size() or digest(data)!=header.slice(8,40):
		reject_lake(identity);return PackedByteArray()
	return data
func store_lake(identity: PackedByteArray,data: PackedByteArray) -> bool:
	if not enabled or identity.size()!=32 or data.size()<104 or data.size()>6*1024*1024:return false
	if not accounting_complete:
		var key:=identity.hex_encode()
		if not _scan_failed and not _pending_lakes.has(key) and _pending_lakes.size()<16 and _pending_lake_bytes+data.size()<=16*1024*1024:
			_pending_lakes[key]=data;_pending_lake_bytes+=data.size()
		return false
	if total_bytes+data.size()+40>LIMIT_BYTES:return false
	var path:=_lake_name(identity)
	if FileAccess.file_exists(path):return true
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))!=OK:write_failures+=1;return false
	var header:=PackedByteArray();header.resize(8);header.encode_u32(0,0x31434c54);header.encode_u32(4,data.size());header.append_array(digest(data))
	var temp:=path+".tmp.%d"%OS.get_process_id()
	var file:=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:write_failures+=1;return false
	file.store_buffer(header);file.store_buffer(data);file.flush()
	var ok:=file.get_error()==OK and file.get_length()==data.size()+40;file.close()
	if ok and DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))==OK:
		total_bytes+=data.size()+40;writes+=1;return true
	write_failures+=1;DirAccess.remove_absolute(ProjectSettings.globalize_path(temp));return false
