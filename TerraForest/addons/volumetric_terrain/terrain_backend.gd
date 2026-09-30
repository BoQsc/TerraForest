# SPDX-License-Identifier: 0BSD
# One persistent sleeping worker. It owns the native world; scene nodes stay on the main thread.
extends RefCounted
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
var thread := Thread.new()
var mutex := Mutex.new()
var semaphore := Semaphore.new()
var jobs: Array[Dictionary] = []
var results: Array[Dictionary] = []
var _density_pending: int = 0 # Accepted queries, including unconsumed results.
var stopping: bool = false
var temporary: bool = false
var native: Object
var collision_recipes: RefCounted
var _collision_piece_triangles := 1024

func configure_collision_piece_size(triangles: int) -> bool:
	# Configuration is immutable while the native-world worker is running.
	if thread.is_started() or triangles<256 or triangles>1024:
		return false
	_collision_piece_triangles=triangles
	return true
var world_seed: int = 1703
var build_epoch: int = 0
var active_kind: String = "idle"
var write_allowed: bool = true
var save_path: String = "user://world.trw"
var surface_style: int = 0
const DiskCache = preload("res://addons/volumetric_terrain/derived_cache.gd")
var disk_cache = DiskCache.new()
var snapshot_id: String = ""
var cache_valid: bool = true
var readonly_snapshot: bool = false
var cache_path: String = "user://derived_046"
var latest_packets: Dictionary = {}
var latest_packet_bytes: int = 0
var active_input: bool = false
var snapshot_codec: RefCounted
var snapshot_capture: Callable
var snapshot_validators: Dictionary = {}
var components: Dictionary = {} # Worker-owned; unknown addon sections survive round trips.
var component_epoch: int = 0
var component_generation: int = -1
var _component_capture_valid: bool = true # Worker-owned; invalid live captures do not poison disk state.
var _capture_generation: int = 0 # Main-thread only.
var _shutdown_snapshot: Dictionary = {}
var _snapshot_writes_blocked: bool = false

func disable_snapshot_writes() -> void:
	mutex.lock()
	_snapshot_writes_blocked = true
	mutex.unlock()

func _snapshot_writable() -> bool:
	mutex.lock()
	var allowed: bool = not _snapshot_writes_blocked
	mutex.unlock()
	return allowed

func _capture_snapshot() -> Dictionary:
	if snapshot_codec == null or not snapshot_capture.is_valid():
		return {}
	_capture_generation += 1
	var state: Dictionary = snapshot_capture.call()
	state["generation"] = _capture_generation
	return state

func _apply_components(state: Dictionary) -> void:
	if state.is_empty() or int(state.get("epoch", -1)) != component_epoch or int(state.get("generation", -1)) <= component_generation:
		return
	var selected: Dictionary = state.get("sections", {})
	component_generation = int(state["generation"])
	for key: String in selected:
		if snapshot_validators.has(key) and not snapshot_validators[key].validate_snapshot(selected[key]):
			_component_capture_valid = false
			return
	for key: String in selected:
		components[key] = selected[key]
	_component_capture_valid = true

func set_input_active(value: bool) -> void:
	mutex.lock()
	active_input = value
	mutex.unlock()

func _input_active() -> bool:
	mutex.lock()
	var value: bool = active_input
	mutex.unlock()
	return value

func _compatibility() -> String:
	var library: String = "res://addons/volumetric_terrain/bin/terrain_core.windows.x86_64.dll" if OS.get_name() == "Windows" else "res://addons/volumetric_terrain/bin/libterrain_core.linux.x86_64.so"
	if OS.get_name() == "Windows" and native != null and native.has_method("build_variant") and native.build_variant() == "template_release":
		library = "res://addons/volumetric_terrain/bin/terrain_core.windows.template_release.x86_64.dll"
	var codec_path: String = "res://addons/volumetric_terrain/mesh_codec.gd"
	# Exported scripts become bytecode. Hash the remapped payload rather than an
	# absent source file, otherwise every future exported codec shares an empty hash.
	if not FileAccess.file_exists(codec_path):
		var remap := ConfigFile.new()
		if remap.load(codec_path + ".remap") == OK:
			codec_path = str(remap.get_value("remap", "path", ""))
	var library_hash: String = FileAccess.get_sha256(library)
	var codec_hash: String = FileAccess.get_sha256(codec_path) if not codec_path.is_empty() else ""
	if library_hash.is_empty() or codec_hash.is_empty():
		disk_cache.enabled = false
		push_warning("Derived cache disabled: binary/codec fingerprint unavailable")
	return library_hash + ":" + codec_hash

func _set_cache_snapshot(id: String) -> void:
	snapshot_id = id
	disk_cache.set_snapshot(snapshot_id)
	cache_valid = true

func _remember_packet(key: Vector3i, data: PackedByteArray) -> void:
	# Only meshes produced from the CURRENT revision are retained. Old lighting
	# is never republished under the hash of a newer saved world.
	if latest_packet_bytes - int(latest_packets.get(key, PackedByteArray()).size()) + data.size() > 64 * 1024 * 1024:
		return
	latest_packet_bytes -= int(latest_packets.get(key, PackedByteArray()).size())
	latest_packets[key] = data
	latest_packet_bytes += data.size()

func _flush_current_packets() -> void:
	if not cache_valid or _input_active():
		return
	for key: Vector3i in latest_packets:
		disk_cache.store_packet(key, latest_packets[key])
	latest_packets.clear()
	latest_packet_bytes = 0


func start(use_temporary: bool) -> Error:
	temporary = use_temporary
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--snapshot-readonly":
			readonly_snapshot = true
			temporary = true
		if arg == "--no-derived-cache":
			disk_cache.enabled = false
		if arg.begins_with("--derived-cache="):
			cache_path = arg.substr(16)
		if arg == "--smooth-surface":
			surface_style = 1
	if snapshot_codec != null and (not temporary or readonly_snapshot):
		if not snapshot_codec.acquire(ProjectSettings.globalize_path(save_path)):
			return ERR_ALREADY_IN_USE
	# Runtime loading works on a fresh ZIP: an editor-generated extension_list.cfg
	# is not required. Do this on the main thread before starting the worker.
	if not ClassDB.class_exists("TerrainCore"):
		var load_status: int = GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
		if load_status != GDExtensionManager.LOAD_STATUS_OK and load_status != GDExtensionManager.LOAD_STATUS_ALREADY_LOADED:
			push_error("TerrainCore could not load (status %d). Check the DLL and launcher preflight log." % load_status)
			return ERR_CANT_OPEN
	if not ClassDB.class_exists("TerrainCore"):
		push_error("The extension loaded but did not register TerrainCore.")
		return ERR_UNAVAILABLE
	native = ClassDB.instantiate("TerrainCore")
	if not ClassDB.class_exists("NativeTerrainCollision"):
		return ERR_UNAVAILABLE
	collision_recipes = ClassDB.instantiate("NativeTerrainCollision")
	if native == null:
		return ERR_CANT_CREATE
	var epoch_reply: PackedByteArray = _call(Codec.command(13))
	if not Codec.reply_ok(epoch_reply) or epoch_reply.size() < 16:
		push_error("Wrong native DLL: v0.4.6 requires the v0.4.5 cancellation protocol 13.")
		return ERR_INVALID_DATA
	build_epoch = epoch_reply.decode_u32(12)
	# One sleeping worker; normal priority prevents foreground edits being starved.
	return thread.start(_run, Thread.PRIORITY_NORMAL)

func submit(job: Dictionary, priority: bool = false) -> bool:
	if job.get("kind","")=="density_ray":
		if typeof(job.get("from"))!=TYPE_VECTOR3 or typeof(job.get("to"))!=TYPE_VECTOR3:
			return false
		var from: Vector3=job["from"]
		var to: Vector3=job["to"]
		if not from.is_finite() or not to.is_finite() or from==to:
			return false
		for field in ["token","epoch","revision","budget"]:
			if typeof(job.get(field))!=TYPE_INT or int(job[field])<0: return false
		if job.budget<1 or job.budget>8192:
			return false
		for axis in range(3):
			if abs(from[axis])>10000 or abs(to[axis])>10000: return false
		# Snapshot only the bounded request fields, not a caller-owned dictionary.
		job={"kind":"density_ray","from":from,"to":to,"token":job.token,"epoch":job.epoch,"revision":job.revision,"budget":job.budget}
		priority=false # Queries cannot jump ahead of already queued mutations.
	job["submitted_us"] = Time.get_ticks_usec()
	if str(job.get("kind", "")) in ["edit", "save"]:
		job["component_snapshot"] = _capture_snapshot()
	mutex.lock()
	if job.get("kind","")=="density_ray" and _density_pending>=8:
		mutex.unlock()
		return false
	if stopping or jobs.size() >= 96 or jobs.size() + results.size() >= 128:
		mutex.unlock()
		return false
	if priority and str(job.get("kind", "")) in ["edit", "reset", "load"]:
		for index in range(jobs.size() - 1, -1, -1):
			if str(job.get("kind", "")) == "edit" and str(jobs[index].get("kind", "")) == "mesh":
				var queued: Dictionary = jobs[index]
				var key: Vector3i = queued["key"]
				var low: Vector3 = job.get("geometry_lo", Vector3(-INF,-INF,-INF))
				var high: Vector3 = job.get("geometry_hi", Vector3.INF)
				if key.x <= high.x and key.x + key.z >= low.x and key.y <= high.z and key.y + key.z >= low.z:
					results.push_back({"kind":"mesh", "cancelled":true, "key":key, "epoch":queued["epoch"], "stamp":queued["stamp"]})
					jobs.remove_at(index)
				else:
					# Geometry may remain valid while edited roofs change lighting.
					# Re-evaluate cached visibility against the current worker world.
					queued["relight_cache"] = true
				continue
			if str(jobs[index].get("kind", "")) == "relight":
				var old: Dictionary = jobs[index]
				results.push_back({"kind": "relight", "cancelled": true, "key": old["key"], "epoch": old["epoch"], "stamp": old["stamp"], "light_ticket": old["light_ticket"]})
				jobs.remove_at(index)
		# The native command touches only an atomic token. Running mesh work checks
		# it cooperatively and releases its own data; never terminate a thread.
		var cancellation: PackedByteArray = _call(Codec.command(12))
		if Codec.reply_ok(cancellation) and cancellation.size() >= 16:
			build_epoch = cancellation.decode_u32(12)
	job["build_epoch"] = build_epoch
	if job.get("kind","")=="density_ray": _density_pending+=1
	if priority:
		jobs.push_front(job)
	else:
		jobs.push_back(job)
	mutex.unlock()
	semaphore.post()
	return true

func cancel_stale_meshes(wanted: Dictionary, current_epoch: int, versions: Dictionary) -> Array[Dictionary]:
	var cancelled: Array[Dictionary] = []
	mutex.lock()
	for index in range(jobs.size() - 1, -1, -1):
		var job: Dictionary = jobs[index]
		if str(job.get("kind", "")) != "mesh":
			continue
		var key: Vector3i = job["key"]
		if int(job["epoch"]) != current_epoch or not wanted.has(key) or int(job["stamp"]) != int(versions.get(key, 0)):
			cancelled.push_back(job)
			jobs.remove_at(index)
	mutex.unlock()
	return cancelled

func queued() -> int:
	mutex.lock()
	var n: int = jobs.size()
	mutex.unlock()
	return n

func status() -> String:
	mutex.lock()
	var value: String = active_kind
	mutex.unlock()
	return value

func poll() -> Array[Dictionary]:
	mutex.lock()
	var ready: Array[Dictionary] = results
	for result: Dictionary in ready:
		if result.get("kind","")=="density_ray": _density_pending-=1
	results = []
	mutex.unlock()
	return ready

func stop() -> void:
	_shutdown_snapshot = _capture_snapshot()
	mutex.lock()
	stopping = true
	mutex.unlock()
	semaphore.post()
	if thread.is_started():
		thread.wait_to_finish()
	native = null
	if snapshot_codec != null:
		snapshot_codec.release()

func _push(result: Dictionary) -> void:
	mutex.lock()
	results.push_back(result)
	mutex.unlock()

func _call(data: PackedByteArray) -> PackedByteArray:
	return native.call("execute", data)

func _save() -> String:
	if temporary:
		return "Temporary test world: save skipped"
	if not write_allowed or not _snapshot_writable():
		return "ERROR: save disabled after corrupt snapshot; original file protected"
	if not _component_capture_valid:
		return "ERROR: invalid addon capture; previous canonical snapshot retained"
	var response: PackedByteArray = _call(Codec.command(4))
	if not Codec.reply_ok(response):
		return "ERROR: native save failed; previous save retained"
	var payload: PackedByteArray = response.slice(12)
	if snapshot_codec != null:
		var sections: Dictionary = components.duplicate()
		sections["terrain"] = payload
		var packed: PackedByteArray = snapshot_codec.encode(sections)
		if packed.is_empty() or snapshot_codec.publish(ProjectSettings.globalize_path(save_path), packed) != OK:
			return "ERROR: compound save failed; previous canonical snapshot retained"
		_set_cache_snapshot(DiskCache.digest(payload).hex_encode())
		_flush_current_packets()
		return "World saved and verified; terrain and addon state published together"
	var tmp: String = save_path + ".tmp.%d" % OS.get_process_id()
	var file: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if file == null or not file.is_open():
		return "ERROR: cannot open save temporary (%d); previous save retained" % FileAccess.get_open_error()
	file.store_buffer(payload)
	file.flush()
	var write_error: Error = file.get_error()
	var written: int = file.get_length()
	file.close()
	file = null
	if write_error != OK or written != payload.size():
		return "ERROR: save write/flush failed (%d, %d/%d bytes); original retained" % [write_error, written, payload.size()]
	# Read-back checks happen on the worker BEFORE rotating the old save.
	var verify: PackedByteArray = FileAccess.get_file_as_bytes(tmp)
	if verify != payload:
		return "ERROR: save read-back mismatch; original retained"
	var path: String = ProjectSettings.globalize_path(save_path)
	var temp_path: String = ProjectSettings.globalize_path(tmp)
	var had_original: bool = FileAccess.file_exists(save_path)
	if had_original:
		if FileAccess.file_exists(save_path + ".bak"):
			var remove_error: Error = DirAccess.remove_absolute(path + ".bak")
			if remove_error != OK:
				return "ERROR: cannot rotate backup (%d); original retained" % remove_error
		var backup_error: Error = DirAccess.rename_absolute(path, path + ".bak")
		if backup_error != OK:
			return "ERROR: cannot rotate save backup (%d); original retained" % backup_error
	var publish_error: Error = DirAccess.rename_absolute(temp_path, path)
	if publish_error != OK:
		if had_original:
			var restore_error: Error = DirAccess.rename_absolute(path + ".bak", path)
			if restore_error != OK:
				return "ERROR: save publish %d / restore %d; recover retained .bak" % [publish_error, restore_error]
		return "ERROR: cannot publish save (%d); original restored" % publish_error
	_set_cache_snapshot(DiskCache.digest(payload).hex_encode())
	_flush_current_packets()
	return "World saved and verified; previous snapshot retained as .bak"

func _load() -> String:
	if (temporary and not readonly_snapshot) or not FileAccess.file_exists(save_path):
		components = {}
		snapshot_id = "new_seed_1703"
		return "New world"
	var payload: PackedByteArray = snapshot_codec.read(ProjectSettings.globalize_path(save_path)) if snapshot_codec != null else FileAccess.get_file_as_bytes(save_path)
	var restored: Dictionary = {}
	if snapshot_codec != null and (payload.size() < 4 or payload.decode_u32(0) != 0x32575254):
		var decoded: Dictionary = snapshot_codec.decode(payload)
		if not decoded.get("ok", false):
			write_allowed = false
			return "ERROR: invalid compound snapshot; original file protected"
		restored = decoded["sections"]
		for key: String in snapshot_validators:
			if restored.has(key) and not snapshot_validators[key].validate_snapshot(restored[key]):
				write_allowed = false
				return "ERROR: invalid addon snapshot; original file protected"
		payload = restored["terrain"]
		restored.erase("terrain")
	snapshot_id = DiskCache.digest(payload).hex_encode()
	var data := Codec.command(5)
	data.append_array(payload)
	var reply: PackedByteArray = _call(data)
	if not Codec.reply_ok(reply):
		write_allowed = false
		return "ERROR: invalid world snapshot; original file left untouched"
	var info: PackedByteArray = _call(Codec.command(0))
	if info.size() >= 36:
		world_seed = info.decode_u32(32)
	components = restored
	write_allowed = true
	return "World loaded"

func _build(key: Vector3i, allow_base_cache: bool, expected_build_epoch: int, relight_cache: bool = false) -> Dictionary:
	var begin: int = Time.get_ticks_usec()
	var step: int = maxi(1, key.z / 32)
	var path: String = "res://addons/volumetric_terrain/base_cache/%d_%d_%d.trm" % [key.x, key.y, key.z]
	var data := PackedByteArray()
	var derived: bool = false
	var cached: bool = false
	var base_available: bool = allow_base_cache and world_seed == 1703 and FileAccess.file_exists(path)
	if cache_valid and (not base_available or relight_cache):
		data = disk_cache.load_packet(key)
		derived = not data.is_empty()
		cached = derived
	if not derived and base_available:
		data = FileAccess.get_file_as_bytes(path)
		cached = data.size() >= 36 and data.decode_u32(4) == 5
	if not cached:
		var reply: PackedByteArray = _call(Codec.command(1, [key.x, key.y, key.z, step, expected_build_epoch]))
		if not Codec.reply_ok(reply):
			if reply.size() >= 12 and reply.decode_u32(8) == 4:
				return {"cancelled": true}
			return {"error": "Native mesh build failed: %s" % key}
		data = reply.slice(16)
	var result: Dictionary = Codec.decode_mesh(data)
	if cached and not derived and relight_cache and not result.has("error"):
		var updated: Dictionary = _refresh_visibility(result["arrays"], expected_build_epoch)
		if updated.has("error") or bool(updated.get("cancelled", false)):
			return updated
		result["arrays"] = updated["arrays"]
		result["cavity_visibility"] = updated["cavity_visibility"]
	if not result.has("error") and not derived and (not cached or relight_cache):
		# A relit base packet is not equal to its original encoded bytes.
		if cached and relight_cache:
			data = Codec.encode_decoded_mesh(result)
		_remember_packet(key, data)
		if cache_valid and not _input_active():
			disk_cache.store_packet(key, data)
	if not result.has("error"):
		var epoch_reply: PackedByteArray = _call(Codec.command(13))
		if epoch_reply.decode_u32(12) != expected_build_epoch:
			return {"cancelled": true}
		var recipes: Dictionary = collision_recipes.prepare(result["faces"], _collision_piece_triangles)
		if not recipes.ok:
			return {"error": recipes.error}
		epoch_reply = _call(Codec.command(13))
		if epoch_reply.decode_u32(12) != expected_build_epoch:
			return {"cancelled": true}
		result["collision_pieces"] = recipes.pieces
		result["collision_prepare_ms"] = recipes.prepare_ms
		# The pieces own the exact faces; release the now redundant full array.
		result["faces"] = PackedVector3Array()
	result["worker_ms"] = float(Time.get_ticks_usec() - begin) / 1000.0
	result["derived_cached"] = derived
	result["cache_stats"] = disk_cache.counters()
	result["cached"] = cached
	result["light_stats"] = _call(Codec.command(15))
	return result

func _refresh_visibility(source_arrays: Array, expected_build_epoch: int) -> Dictionary:
	var arrays: Array = source_arrays.duplicate()
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var exact: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var classes := PackedFloat32Array()
	classes.resize(exact.size())
	for i in range(exact.size()):
		classes[i] = exact[i].x
	var request: PackedByteArray = Codec.command(11, [expected_build_epoch, positions.size()])
	request.append_array(positions.to_byte_array())
	request.append_array(normals.to_byte_array())
	request.append_array(classes.to_byte_array())
	var reply: PackedByteArray = _call(request)
	if not Codec.reply_ok(reply) or reply.size() != 16 + positions.size() * 8:
		if reply.size() >= 12 and reply.decode_u32(8) == 4:
			return {"cancelled": true}
		return {"error": "Visibility-only update failed"}
	var visibility: PackedVector2Array = Codec._packed_channel(reply, 16, positions.size(), 8, TYPE_PACKED_VECTOR2_ARRAY)
	arrays[Mesh.ARRAY_TEX_UV] = visibility
	var cavity: bool = false
	for sample: Vector2 in visibility:
		if sample.x < 0.999:
			cavity = true
			break
	return {"arrays": arrays, "cavity_visibility": cavity}

func _relight(item: Dictionary, expected_build_epoch: int) -> Dictionary:
	# Reuse geometry and colliders. Pack GPU attributes natively on this worker.
	var begin: int = Time.get_ticks_usec()
	var result: Dictionary = _refresh_visibility(item["arrays"], expected_build_epoch)
	if result.has("error") or bool(result.get("cancelled", false)):
		return result
	var arrays: Array = result["arrays"]
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var layout: Dictionary = item["attribute_layout"]
	if layout.is_empty():
		return {"cancelled": true}
	if bool(layout.get("compressed", true)) or int(layout["count"]) != positions.size():
		return {"error": "Unsupported mesh attribute layout; no GPU write performed"}
	var pack: PackedByteArray = Codec.command(16, [positions.size(), layout["stride"], layout["uv"], layout["uv2"], layout["color"]])
	var visibility: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var exact: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	pack.append_array(visibility.to_byte_array())
	pack.append_array(exact.to_byte_array())
	pack.append_array(colors.to_byte_array())
	var packed: PackedByteArray = _call(pack)
	if not Codec.reply_ok(packed) or packed.size() != 20 + positions.size() * int(layout["stride"]):
		return {"error": "Native attribute packing failed; no GPU write performed"}
	result["attribute_data"] = packed.slice(20)
	result["key"] = item["key"]
	result["faces"] = PackedVector3Array()
	result["triangles"] = item["triangles"]
	result["bytes"] = item["bytes"]
	result["lighting_only"] = true
	result["light_stats"] = _call(Codec.command(15))
	result["worker_ms"] = float(Time.get_ticks_usec() - begin) / 1000.0
	return result

func _run() -> void:
	var load_message: String = _load()
	disk_cache.configure(_compatibility(), snapshot_id, surface_style, cache_path)
	_call(Codec.command(14, [surface_style]))
	_push({"kind": "startup", "message": load_message,
		"components": components.duplicate(), "modified": _call(Codec.command(10)), "stats": _call(Codec.command(0))})
	while true:
		semaphore.wait()
		mutex.lock()
		var should_stop: bool = stopping
		var job: Dictionary = {}
		if not should_stop and not jobs.is_empty():
			job = jobs.pop_front()
			# Cancellation epochs belong to execution, not time spent queued.
			# Edits prune intersecting queued jobs; unaffected work may survive many
			# edits. Snapshot the token under the same lock used by submit so a new
			# priority mutation can still cancel this job after it starts.
			if str(job.get("kind", "")) == "mesh":
				job["build_epoch"] = build_epoch
		active_kind = str(job.get("kind", "idle"))
		mutex.unlock()
		if should_stop:
			# Preserve accepted mutations even if their render jobs have not run.
			# No new submissions are admitted after stopping was set under mutex.
			for remaining: Dictionary in jobs:
				var remaining_kind: String = str(remaining.get("kind", ""))
				if remaining_kind == "edit":
					latest_packets.clear()
					latest_packet_bytes = 0
					cache_valid = false
					for packet: PackedByteArray in remaining.get("commands", [remaining["command"]]):
						if not Codec.reply_ok(_call(packet)):
							write_allowed = false
					_apply_components(remaining.get("component_snapshot", {}))
				elif remaining_kind == "save":
					_apply_components(remaining.get("component_snapshot", {}))
				elif remaining_kind == "density_ray":
					_push({"kind":"density_ray","status":"cancelled","cancelled":true,"token":remaining["token"],"epoch":remaining["epoch"],"requested_revision":remaining["revision"],"build_epoch":remaining["build_epoch"]})
				elif remaining_kind in ["load", "reset"]:
					latest_packets.clear()
					latest_packet_bytes = 0
					cache_valid = false
					component_epoch = int(remaining["epoch"])
					component_generation = -1
					_component_capture_valid = true
					if remaining_kind == "load":
						_load()
					else:
						_call(Codec.command(6, [1703]))
						components = {}
						world_seed = 1703
						write_allowed = true
			jobs.clear()
			_apply_components(_shutdown_snapshot)
			set_input_active(false)
			_flush_current_packets()
			print("[TerrainRewrite] ", _save())
			return
		if job.is_empty():
			continue
		var kind: String = str(job.get("kind", ""))
		var queue_ms: float = float(Time.get_ticks_usec() - int(job.get("submitted_us", Time.get_ticks_usec()))) / 1000.0
		if kind == "mesh":
			var mesh_result: Dictionary = _build(job["key"], bool(job.get("base", false)), int(job["build_epoch"]), bool(job.get("relight_cache", false)))
			mesh_result["kind"] = "mesh"
			mesh_result["key"] = job["key"]
			mesh_result["stamp"] = job["stamp"]
			mesh_result["epoch"] = job["epoch"]
			_push(mesh_result)
		elif kind == "edit":
			_apply_components(job.get("component_snapshot", {}))
			var before_stats: PackedByteArray = _call(Codec.command(0))
			var begin: int = Time.get_ticks_usec()
			var reply := PackedByteArray()
			var commands: Array = job.get("commands", [job["command"]])
			var member_changed: Array[bool] = []
			var revision_before: int = before_stats.decode_u32(12)
			for command: PackedByteArray in commands:
				reply = _call(command)
				var member_stats: PackedByteArray = _call(Codec.command(0))
				var revision_after: int = member_stats.decode_u32(12)
				member_changed.push_back(revision_after != revision_before)
				revision_before = revision_after
				if not Codec.reply_ok(reply):
					# A failed multi-command group is not claimed rollback-atomic.
					# Stop publishing/saving rather than overwrite the last valid save.
					write_allowed = false
					cache_valid = false
					break
			var edit_ms: float = float(Time.get_ticks_usec() - begin) / 1000.0
			var after_stats: PackedByteArray = _call(Codec.command(0))
			var no_change: bool = Codec.reply_ok(reply) and before_stats.decode_u32(12) == after_stats.decode_u32(12)
			if not Codec.reply_ok(reply) or no_change:
				_push({"kind": "edit", "chunks": [], "reply": reply, "epoch": job["epoch"],
					"ticket": job["ticket"], "edit_ms": edit_ms, "stats": after_stats,
					"queue_ms": queue_ms, "no_change": no_change, "member_changed": member_changed, "worker_finished_us": Time.get_ticks_usec()})
			else:
				cache_valid = false
				latest_packets.clear()
				latest_packet_bytes = 0
				_push({"kind": "edit_begin", "epoch": job["epoch"], "ticket": job["ticket"],
					"count": job["tiles"].size(), "edit_ms": edit_ms, "queue_ms": queue_ms, "stats": after_stats, "member_changed": member_changed})
				# Stream finished patches to main-thread staging immediately. Worker
				# builds and resource preparation OVERLAP instead of running in series.
				var build_total: float = 0.0
				for item: Dictionary in job["tiles"]:
					var chunk: Dictionary = _build(item["key"], false, int(job["build_epoch"]))
					if bool(chunk.get("cancelled", false)):
						chunk = {"error": "Edit build cancelled; reload before further editing"}
					build_total += float(chunk.get("worker_ms", 0.0))
					chunk["stamp"] = item["stamp"]
					chunk["key"] = item["key"]
					chunk["kind"] = "edit_chunk"
					chunk["epoch"] = job["epoch"]
					chunk["ticket"] = job["ticket"]
					_push(chunk)
				_push({"kind": "edit_done", "epoch": job["epoch"], "ticket": job["ticket"],
					"stats": after_stats, "build_total_ms": build_total, "worker_finished_us": Time.get_ticks_usec()})
		elif kind == "relight":
			var update: Dictionary = _relight(job, int(job["build_epoch"]))
			update["key"] = job["key"]
			update["kind"] = "relight"
			update["epoch"] = job["epoch"]
			update["stamp"] = job["stamp"]
			update["light_ticket"] = job["light_ticket"]
			_push(update)
		elif kind == "save":
			_apply_components(job.get("component_snapshot", {}))
			_push({"kind": "message", "message": _save()})
		elif kind == "load" or kind == "reset":
			component_epoch = int(job["epoch"])
			component_generation = -1
			_component_capture_valid = true
			var message: String = "World reset (previous disk save retained until next save)"
			if kind == "reset":
				_call(Codec.command(6, [1703]))
				world_seed = 1703
				write_allowed = true
				components = {}
			else:
				message = _load()
			_call(Codec.command(14, [surface_style]))
			latest_packets.clear()
			latest_packet_bytes = 0
			if kind == "reset":
				snapshot_id = "new_seed_1703"
			_set_cache_snapshot(snapshot_id)
			_push({"kind": "reload", "epoch": job["epoch"], "message": message,
				"components": components.duplicate(), "modified": _call(Codec.command(10)), "stats": _call(Codec.command(0))})
		elif kind == "lake_slice":
			# Worker exclusively owns terrain; the native builder is not read by the
			# main thread until this slice completes. Sampling yields after ~2 ms.
			var status: int = job["builder"].sample_terrain(native, 512, job["density_revision"], job["build_epoch"])
			_push({"kind": "lake_slice", "status": status, "token": job["token"], "epoch": job["epoch"], "revision": job["revision"]})
		elif kind == "surface_batch":
			var points: PackedVector3Array = job["points"]
			var normals := PackedVector3Array()
			normals.resize(points.size())
			var packet: PackedByteArray = Codec.command(17, [points.size()])
			packet.append_array(points.to_byte_array())
			var reply: PackedByteArray = _call(packet)
			if Codec.reply_ok(reply) and reply.size() == 16 + points.size() * 24 and reply.decode_u32(12) == points.size():
				var count: int = points.size()
				points = Codec._packed_channel(reply, 16, count, 12, TYPE_PACKED_VECTOR3_ARRAY)
				normals = Codec._packed_channel(reply, 16 + count * 12, count, 12, TYPE_PACKED_VECTOR3_ARRAY)
			else:
				# Failed sampling must not publish a valid-looking empty forest.
				points = PackedVector3Array()
				normals = PackedVector3Array()
			_push({"kind": "surface_batch", "points": points, "normals": normals, "token": job["token"], "epoch": job["epoch"], "revision": job["revision"]})
		elif kind == "density_ray":
			var reply: PackedByteArray=_call(Codec.density_ray_command(job["from"],job["to"],job["budget"],job["build_epoch"]))
			var result: Dictionary=Codec.decode_density_ray(reply)
			if result.get("cells",0)>job["budget"]:
				result={"status":"error","error":"Density query exceeded requested budget"}
			if result.has("revision") and result.revision!=job["revision"]:
				result.erase("position");result.erase("fraction");result["status"]="stale"
			result.merge({"kind":"density_ray","token":job["token"],"epoch":job["epoch"],"requested_revision":job["revision"],"build_epoch":job["build_epoch"],"queue_ms":queue_ms})
			_push(result)
		elif kind == "height":
			var reply: PackedByteArray = _call(Codec.point_command(job["point"]))
			_push({"kind": "height", "reply": reply, "point": job["point"], "token": job["token"]})
		mutex.lock()
		active_kind = "idle"
		mutex.unlock()
