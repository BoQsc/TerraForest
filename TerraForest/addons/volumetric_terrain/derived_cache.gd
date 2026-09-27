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

static func digest(data: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish()

func configure(compatibility: String, snapshot: String, style: int, path: String = "user://derived_046") -> void:
	base_path = path
	signature = ("trm5:046:" + compatibility + ":" + str(style)).sha256_text()
	set_snapshot(snapshot)
	# Bounded derived disk use; reaching the cap disables writes, not gameplay.
	total_bytes = _size(base_path)

func _size(path: String) -> int:
	var d := DirAccess.open(path)
	if d == null:
		return 0
	var n: int = 0
	for name: String in d.get_files():
		var f := FileAccess.open(path.path_join(name), FileAccess.READ)
		if f != null:
			n += f.get_length()
			f.close()
	for name: String in d.get_directories():
		n += _size(path.path_join(name))
	return n

func set_snapshot(snapshot: String) -> void:
	cache_directory = base_path.path_join(signature).path_join(snapshot)
	if enabled:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_directory))

func _name(key: Vector3i) -> String:
	return cache_directory.path_join("%d_%d_%d.trc" % [key.x, key.y, key.z])

func _reject(key: Vector3i, bytes: int) -> PackedByteArray:
	corrupt += 1
	if DirAccess.remove_absolute(ProjectSettings.globalize_path(_name(key))) == OK:
		total_bytes = maxi(0, total_bytes - bytes)
	return PackedByteArray()

func load_packet(key: Vector3i) -> PackedByteArray:
	if not enabled:
		return PackedByteArray()
	var f := FileAccess.open(_name(key), FileAccess.READ)
	if f == null:
		misses += 1
		return PackedByteArray()
	var length: int = f.get_length()
	if length < 76 or length > MAX_PACKET + 40:
		f.close()
		return _reject(key, length)
	var header: PackedByteArray = f.get_buffer(40)
	var data: PackedByteArray = f.get_buffer(length - 40)
	f.close()
	if header.size() != 40 or header.decode_u32(0) != MAGIC or header.decode_u32(4) != data.size() or digest(data) != header.slice(8, 40):
		return _reject(key, length)
	if data.size() < 36 or data.decode_u32(0) != Codec.MESH_MAGIC or data.decode_u32(4) != 5 or Vector3i(data.decode_u32(8), data.decode_u32(12), data.decode_u32(16)) != key:
		return _reject(key, length)
	hits += 1
	return data

func store_packet(key: Vector3i, data: PackedByteArray) -> void:
	if not enabled or data.size() < 36 or data.size() > MAX_PACKET:
		return
	var path: String = _name(key)
	if FileAccess.file_exists(path):
		return
	if total_bytes + data.size() + 40 > LIMIT_BYTES:
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
	else:
		write_failures += 1
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))

func counters() -> Dictionary:
	return {"hits": hits, "misses": misses, "writes": writes, "corrupt": corrupt,
		"write_failures": write_failures, "disk_bytes": total_bytes, "enabled": enabled}
