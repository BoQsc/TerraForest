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
var _partition_pending: int = 0 # One bounded source/result, including unconsumed output.
var _lake_pending: int = 0 # One builder reservation through completion consumption.
var stopping: bool = false
var temporary: bool = false
var native: Object
var collision_recipes: RefCounted
var _collision_piece_triangles := 1024
var snapshot_terrain: bool = "--snapshot-terrain" in OS.get_cmdline_user_args()
var brick_terrain: bool = "--brick-terrain" in OS.get_cmdline_user_args()
var region_terrain: bool = "--region-terrain" in OS.get_cmdline_user_args()
var profile_regions: bool = "--profile-owned-regions" in OS.get_cmdline_user_args()
var _snapshot_token: int = 0

func configure_collision_piece_size(triangles: int) -> bool:
	# Configuration is immutable while the native-world worker is running.
	if thread.is_started() or triangles<256 or triangles>1024:
		return false
	_collision_piece_triangles=triangles
	return true
var world_seed: int = 1703
var world_generator: int = 1
var build_epoch: int = 0
var active_kind: String = "idle"
var diagnostic_active: Dictionary = {}
var diagnostic_enabled:=false

func enable_diagnostics() -> void:
	mutex.lock();diagnostic_enabled=true;mutex.unlock()

func diagnostic_queue_snapshot() -> Dictionary:
	# Opt-in observer: never copy mesh buffers or native world data.
	mutex.lock()
	var queued_jobs: Array=[]
	for job: Dictionary in jobs:
		queued_jobs.append({"kind":job.get("kind",""),"key":str(job.get("key","")),"submitted_us":job.get("submitted_us",0)})
	var snapshot: Dictionary={"active":diagnostic_active.duplicate(),"queued":queued_jobs}
	mutex.unlock()
	return snapshot
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

var _site_pending:=0
func submit(job: Dictionary, priority: bool = false) -> bool:
	if job.get("kind","")=="density_batch":
		var paged: Variant=job.get("paged",false)
		if typeof(paged)!=TYPE_BOOL: return false
		if typeof(job.get("points"))!=TYPE_PACKED_VECTOR3_ARRAY or job.points.is_empty() or job.points.size()>(4096 if paged else 512): return false
		for field in ["token","epoch","revision"]:
			if typeof(job.get(field))!=TYPE_INT or job[field]<0: return false
		var depth: Variant=job.get("support_depth",0)
		if typeof(depth)!=TYPE_INT or depth<0 or depth>8: return false
		job={"kind":"density_batch","points":job.points.duplicate(),"token":job.token,"epoch":job.epoch,"revision":job.revision,"support_depth":depth}
		priority=false
	if job.get("kind","")=="lake_slice":
		if not is_instance_valid(job.get("builder")) or job.builder.get_class()!="NativeLakeVolume": return false
		# RefCounted instance IDs may use the signed integer's high bit.
		if typeof(job.get("token"))!=TYPE_INT: return false
		for field in ["epoch","revision","density_revision"]:
			if typeof(job.get(field))!=TYPE_INT or int(job[field])<0: return false
		job={"kind":"lake_slice","builder":job.builder,"token":job.token,"epoch":job.epoch,"revision":job.revision,"density_revision":job.density_revision}
		priority=false
	if job.get("interaction_mesh",false):
		if job.get("kind","")!="mesh" or typeof(job.get("key"))!=TYPE_VECTOR3I or job.key.z!=16: return false
		priority=false # Only the cooperative reader may bypass read-only work.
	if job.get("kind","")=="partition":
		if typeof(job.get("packet"))!=TYPE_PACKED_BYTE_ARRAY or job.packet.size()<36 or job.packet.size()>64*1024*1024: return false
		for field in ["token","epoch","stamp"]:
			if typeof(job.get(field))!=TYPE_INT or int(job[field])<0: return false
		job={"kind":"partition","packet":job.packet,"token":job.token,"epoch":job.epoch,"stamp":job.stamp}
		priority=false
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
	if job.get("kind","")=="lake_slice" and _lake_pending>=1:
		mutex.unlock();return false
	if job.get("kind","")=="density_batch" and _site_pending>=1:
		mutex.unlock();return false
	if job.get("interaction_mesh",false):
		var waiting:=0
		for queued_job: Dictionary in jobs:
			if queued_job.get("interaction_mesh",false): waiting+=1
		if waiting>=2:
			mutex.unlock();return false
	if job.get("kind","")=="partition" and _partition_pending>=1:
		mutex.unlock()
		return false
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
	if job.get("kind","")=="partition": _partition_pending+=1
	if job.get("kind","")=="lake_slice": _lake_pending+=1
	if job.get("kind","")=="density_batch": _site_pending+=1
	if priority:
		var insertion:=0
		if str(job.get("kind","")) in ["edit","load","reset"]:
			# Captured addon snapshots belong to their accepted world order.
			# Prioritize over background work, never over a save or mutation.
			for index in range(jobs.size()):
				if str(jobs[index].get("kind","")) in ["save","edit","load","reset"]:
					insertion=index+1
		jobs.insert(insertion,job)
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
		if result.get("kind","")=="density_batch": _site_pending-=1
		if result.get("kind","")=="density_ray": _density_pending-=1
		if result.get("kind","")=="partition": _partition_pending-=1
		if result.get("kind","")=="lake_slice": _lake_pending-=1
	results = []
	mutex.unlock()
	return ready

func stop() -> void:
	_shutdown_snapshot = _capture_snapshot()
	mutex.lock()
	stopping = true
	if active_kind=="partition": _call(Codec.command(12))
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

func _initialize_generated_components() -> bool:
	components = {}
	if world_generator==4 and snapshot_validators.has("volumetric_water"):
		var definitions: PackedByteArray=_call(Codec.command(27))
		var records: Array=[]
		if not Codec.reply_ok(definitions) or definitions.size()!=192:
			write_allowed=false
			return false
		for i in range(4):
			var offset:=16+i*44
			var origin:=Vector3(definitions.decode_float(offset),definitions.decode_float(offset+4),definitions.decode_float(offset+8))
			var cells:=Vector3i(definitions.decode_u32(offset+12),definitions.decode_u32(offset+16),definitions.decode_u32(offset+20))
			var seed_point:=Vector3(definitions.decode_float(offset+32),definitions.decode_float(offset+36),definitions.decode_float(offset+40))
			records.append({"id":i+1,"origin":origin,"cells":cells,"spacing":definitions.decode_float(offset+24),"level":definitions.decode_float(offset+28),"seed":seed_point})
		components["volumetric_water"]=snapshot_validators["volumetric_water"].encode(records,5)
	return true

func _load() -> String:
	if (temporary and not readonly_snapshot) or not FileAccess.file_exists(save_path):
		if not Codec.reply_ok(_call(Codec.command(6,[world_seed,world_generator]))):
			write_allowed=false
			return "ERROR: unsupported world generator"
		if not _initialize_generated_components():
			return "ERROR: generated lake definitions unavailable"
		snapshot_id = "new_generator_%d_seed_%d"%[world_generator,world_seed]
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
	world_generator=payload.decode_u32(28) if payload.decode_u32(4)==2 else 1
	components = restored
	write_allowed = true
	return "World loaded"

func _build_bricks(key: Vector3i, expected_build_epoch: int, selected: Array) -> Dictionary:
	var begin := Time.get_ticks_usec()
	var bottoms: Array=selected if not selected.is_empty() else [0,32,64,96,128,160,192,224]
	var parts: Array[Dictionary]=[]
	var bytes:=0
	var triangles:=0
	var revision: int=_call(Codec.command(0)).decode_u32(12)
	for bottom: int in bottoms:
		if _call(Codec.command(13)).decode_u32(12)!=expected_build_epoch: return {"cancelled":true}
		_snapshot_token+=1
		if not native.experimental_snapshot_submit_brick(key.x,key.y,key.z,_snapshot_token,revision,bottom,bottom+32): return {"error":"Brick admission failed"}
		var rows: Array=[]
		while rows.is_empty():
			rows=native.experimental_snapshot_poll()
			if rows.is_empty(): OS.delay_usec(1000)
		if bool(rows[0].get("stale",true)): return {"cancelled":true}
		var envelope: Dictionary=native.experimental_snapshot_encode_brick(rows[0],key.x,key.y,key.z)
		if envelope.is_empty():
			if _call(Codec.command(13)).decode_u32(12)!=expected_build_epoch: return {"cancelled":true}
			return {"error":"Brick conversion failed"}
		var part: Dictionary=Codec.decode_mesh(envelope.packet)
		if part.has("error"): return part
		var recipes: Dictionary=collision_recipes.prepare(part.faces,_collision_piece_triangles)
		if not recipes.ok: return {"error":recipes.error}
		part["collision_pieces"]=recipes.pieces
		part["faces"]=PackedVector3Array()
		part["brick_bottom"]=bottom
		parts.append(part)
		bytes+=int(part.bytes)
		triangles+=int(part.triangles)
	if _call(Codec.command(13)).decode_u32(12)!=expected_build_epoch: return {"cancelled":true}
	return {"key":key,"step":1,"bricks":parts,"brick_partial":not selected.is_empty(),"bytes":bytes,"triangles":triangles,"worker_ms":(Time.get_ticks_usec()-begin)/1000.0}

func _execute_density_query(job: Dictionary) -> void:
	var query_started:=Time.get_ticks_usec()
	var queue_ms: float=(query_started-int(job.get("submitted_us",query_started)))/1000.0
	var reply: PackedByteArray=_call(Codec.density_ray_command(job["from"],job["to"],job["budget"],job["build_epoch"],true))
	var result: Dictionary=Codec.decode_density_ray(reply)
	if result.get("cells",0)>job["budget"]:
		result={"status":"error","error":"Density query exceeded requested budget"}
	if result.has("revision") and result.revision!=job["revision"]:
		result.erase("position");result.erase("fraction");result["status"]="stale"
	result.merge({"kind":"density_ray","token":job["token"],"epoch":job["epoch"],"requested_revision":job["revision"],"build_epoch":job["build_epoch"],"queue_ms":queue_ms,"query_ms":(Time.get_ticks_usec()-query_started)/1000.0,"worker_finished_us":Time.get_ticks_usec()})
	_push(result)

func _execute_lake_slice(job: Dictionary) -> void:
	var started:=Time.get_ticks_usec()
	# Native sampling yields at 2 ms or 2048 points; final flood fill is bounded
	# by the configured volume. Only the terrain worker touches this builder.
	var status: int=job.builder.sample_terrain(native,2048,job.density_revision,job.build_epoch)
	_push({"kind":"lake_slice","status":status,"token":job.token,"epoch":job.epoch,"revision":job.revision,
		"queue_ms":(started-int(job.get("submitted_us",started)))/1000.0,"worker_ms":(Time.get_ticks_usec()-started)/1000.0})

func _service_lake_slice() -> void:
	var selected: Dictionary={}
	mutex.lock()
	if not stopping:
		for index in range(jobs.size()):
			var kind: String=jobs[index].get("kind","")
			if kind=="lake_slice":
				selected=jobs[index];jobs.remove_at(index);break
			if kind not in ["mesh","relight","height","surface_batch","density_ray"]: break
	mutex.unlock()
	if not selected.is_empty(): _execute_lake_slice(selected)

func _execute_density_batch(job: Dictionary) -> void:
	var started:=Time.get_ticks_usec()
	var values:=PackedFloat32Array()
	var status: String="ok"
	# At most eight native pages per reservation. No mutation executes between
	# pages; every reply must still match the captured revision. Never publish
	# partial values if a later page is malformed or stale.
	for offset in range(0,job.points.size(),512):
		var page: PackedVector3Array=job.points.slice(offset,mini(offset+512,job.points.size()))
		var packet:=Codec.command(29,[job.revision,page.size()])
		if job.support_depth>0: packet=Codec.command(30,[job.revision,page.size(),job.support_depth])
		packet.append_array(page.to_byte_array())
		var reply: PackedByteArray=_call(packet)
		if Codec.reply_ok(reply) and reply.size()==20+page.size()*4 and reply.decode_u32(12)==job.revision and reply.decode_u32(16)==page.size():
			values.append_array(reply.slice(20).to_float32_array())
		else:
			status="stale" if reply.size()>=12 and reply.decode_u32(8)==4 else "error"
			values.clear();break
	_push({"kind":"density_batch","token":job.token,"epoch":job.epoch,"revision":job.revision,"status":status,"values":values,"worker_us":Time.get_ticks_usec()-started})

func _service_density_query() -> void:
	# Worker-only cooperative read point. Keep the current mesh's completed
	# regions; never cancel/restart its work merely to answer a target query.
	var query: Dictionary={}
	mutex.lock()
	if not stopping:
		for index in range(jobs.size()):
			var kind: String=jobs[index].get("kind","")
			if kind in ["density_ray","density_batch"]:
				query=jobs[index];jobs.remove_at(index);break
			# Never cross mutations, saves, or unknown future job types.
			if kind not in ["mesh","relight","height","surface_batch"]: break
	mutex.unlock()
	if not query.is_empty():
		if query.kind=="density_batch": _execute_density_batch(query)
		else: _execute_density_query(query)

func _execute_mesh(job: Dictionary, interactive: bool=false) -> void:
	var result: Dictionary=_build(job.key,bool(job.get("base",false)),int(job.build_epoch),bool(job.get("relight_cache",false)),[],interactive)
	result["kind"]="mesh"
	result["key"]=job.key
	result["stamp"]=job.stamp
	result["epoch"]=job.epoch
	_push(result)

func _service_interaction_mesh() -> void:
	# One bounded 16m read-only build between background owners. The nested
	# build disables cooperative servicing, so this cannot recurse or starve
	# a queued mutation. Retain the interrupted container's completed owners.
	var selected: Dictionary={}
	var prior_diagnostic: Dictionary={}
	mutex.lock()
	if not stopping:
		for index in range(jobs.size()):
			var job: Dictionary=jobs[index]
			var kind: String=job.get("kind","")
			if kind=="mesh" and job.get("interaction_mesh",false):
				selected=job;selected["build_epoch"]=build_epoch
				jobs.remove_at(index)
				if diagnostic_enabled:
					prior_diagnostic=diagnostic_active
					diagnostic_active={"kind":"interactive_mesh","key":str(job.key),"started_us":Time.get_ticks_usec(),"submitted_us":job.get("submitted_us",0)}
				break
			if kind not in ["mesh","relight","height","surface_batch","density_ray"]: break
	mutex.unlock()
	if not selected.is_empty():
		_execute_mesh(selected,true)
		mutex.lock()
		if diagnostic_enabled: diagnostic_active=prior_diagnostic
		mutex.unlock()

func _build_regions(key: Vector3i, expected_build_epoch: int, selected: Array, foreground: bool=false) -> Dictionary:
	var begin:=Time.get_ticks_usec()
	var size:=mini(32,key.z)
	var step:=maxi(1,key.z/32)
	var parts: Array[Dictionary]=[]
	var bytes:=0
	var triangles:=0
	var hits:=0
	var stages: Dictionary={"key_us":0,"read_us":0,"build_us":0,"decode_us":0,"light_us":0,"write_us":0,"recipes_us":0,"native_ms":[0.0,0.0,0.0,0.0]}
	for z in range(key.y,key.y+key.z,size):
		for x in range(key.x,key.x+key.z,size):
			var dependency: String=""
			for bottom in range(0,256,32):
				var id: int=bottom+256*((x-key.x)/size+8*((z-key.y)/size))
				if not selected.is_empty() and not selected.has(id): continue
				if not foreground:
					_service_density_query()
					_service_interaction_mesh()
					_service_lake_slice()
				if _call(Codec.command(13)).decode_u32(12)!=expected_build_epoch: return {"cancelled":true}
				if dependency.is_empty() and disk_cache.enabled:
					var mark:=Time.get_ticks_usec()
					dependency=str(native.geometry_cache_key(x,z,size,step).get("key",""))
					stages.key_us+=Time.get_ticks_usec()-mark
				var content: String=("owned-region-v1:%s:%d" % [dependency,bottom]).sha256_text() if not dependency.is_empty() else ""
				var owner:=Vector3i(x,z,size)
				var packet:=PackedByteArray()
				var mark:=Time.get_ticks_usec()
				if not content.is_empty(): packet=disk_cache.load_packet(owner,content)
				stages.read_us+=Time.get_ticks_usec()-mark
				var cached:=not packet.is_empty()
				mark=Time.get_ticks_usec()
				if not cached: packet=native.build_owned_region(x,z,size,step,bottom,bottom+32,expected_build_epoch)
				stages.build_us+=Time.get_ticks_usec()-mark
				if profile_regions and not cached:
					var native_stages: PackedByteArray=_call(Codec.command(19))
					for index in range(4): stages.native_ms[index]+=native_stages.decode_float(12+index*4)
				if packet.is_empty():
					if _call(Codec.command(13)).decode_u32(12)!=expected_build_epoch: return {"cancelled":true}
					return {"error":"Owned terrain reconstruction failed"}
				mark=Time.get_ticks_usec()
				var part: Dictionary=Codec.decode_mesh(packet)
				stages.decode_us+=Time.get_ticks_usec()-mark
				if part.has("error"): return part
				if cached:
					mark=Time.get_ticks_usec()
					var refreshed: Dictionary=_refresh_visibility(part.arrays,expected_build_epoch)
					if refreshed.has("error") or refreshed.get("cancelled",false): return refreshed
					part.arrays=refreshed.arrays
					part.cavity_visibility=refreshed.cavity_visibility
					hits+=1
					stages.light_us+=Time.get_ticks_usec()-mark
				elif not foreground and not content.is_empty() and not _input_active():
					mark=Time.get_ticks_usec()
					disk_cache.store_packet(owner,packet,content)
					stages.write_us+=Time.get_ticks_usec()-mark
				mark=Time.get_ticks_usec()
				var recipes: Dictionary=collision_recipes.prepare(part.faces,_collision_piece_triangles)
				stages.recipes_us+=Time.get_ticks_usec()-mark
				if not recipes.ok: return {"error":recipes.error}
				part["collision_pieces"]=recipes.pieces
				part["faces"]=PackedVector3Array()
				part["key"]=key
				part["brick_bottom"]=id
				part["region_bounds"]=AABB(Vector3(x,bottom,z),Vector3(size,32,size))
				parts.append(part)
				bytes+=int(part.bytes)
				triangles+=int(part.triangles)
	if _call(Codec.command(13)).decode_u32(12)!=expected_build_epoch: return {"cancelled":true}
	return {"key":key,"step":step,"bricks":parts,"brick_partial":not selected.is_empty(),"bytes":bytes,"triangles":triangles,"worker_ms":(Time.get_ticks_usec()-begin)/1000.0,"region_parts":parts.size(),"geometry_cache_hits":hits,"region_stages":stages}

func _build(key: Vector3i, allow_base_cache: bool, expected_build_epoch: int, relight_cache: bool = false, brick_bottoms: Array = [], foreground: bool=false) -> Dictionary:
	if region_terrain: return _build_regions(key,expected_build_epoch,brick_bottoms,foreground)
	if brick_terrain and key.z<=32 and key.x+key.z<=2000 and key.y+key.z<=2000:
		return _build_bricks(key,expected_build_epoch,brick_bottoms)
	var begin: int = Time.get_ticks_usec()
	var step: int = maxi(1, key.z / 32)
	var path: String = "res://addons/volumetric_terrain/base_cache/%d_%d_%d.trm" % [key.x, key.y, key.z]
	var data := PackedByteArray()
	var derived: bool = false
	var geometry_cached: bool = false
	var content: String = ""
	var cached: bool = false
	var base_available: bool = allow_base_cache and world_generator == 1 and world_seed == 1703 and FileAccess.file_exists(path)
	var snapshot_build: bool = snapshot_terrain and key.z<=32 and key.x+key.z<=2000 and key.y+key.z<=2000
	# Geometry validity survives unrelated edits and save-snapshot changes. Its
	# visibility is deliberately not trusted: distant edits can change sky rays.
	if not snapshot_build and disk_cache.enabled and native.has_method("geometry_cache_key"):
		var dependency: Dictionary = native.geometry_cache_key(key.x,key.y,key.z,step)
		content = str(dependency.get("key", ""))
		if not content.is_empty():
			data = disk_cache.load_packet(key, content)
			geometry_cached = not data.is_empty()
			cached = geometry_cached
	if snapshot_build:
		var revision_reply: PackedByteArray = _call(Codec.command(0))
		_snapshot_token+=1
		if not native.experimental_snapshot_submit(key.x,key.y,key.z,_snapshot_token,revision_reply.decode_u32(12)):
			return {"error":"Snapshot terrain admission failed"}
		var rows: Array=[]
		while rows.is_empty():
			rows=native.experimental_snapshot_poll()
			if rows.is_empty(): OS.delay_usec(1000)
		var packet: Dictionary=rows[0]
		if bool(packet.get("stale",true)): return {"cancelled":true}
		data=native.experimental_snapshot_encode(packet,key.x,key.y,key.z)
		if data.is_empty():
			if _call(Codec.command(13)).decode_u32(12)!=expected_build_epoch: return {"cancelled":true}
			return {"error":"Snapshot terrain conversion failed"}
	elif not geometry_cached and cache_valid and (not base_available or relight_cache):
		data = disk_cache.load_packet(key)
		derived = not data.is_empty()
		cached = derived
	if not snapshot_build and not geometry_cached and not derived and base_available:
		data = FileAccess.get_file_as_bytes(path)
		cached = data.size() >= 36 and data.decode_u32(4) == 5
	if not snapshot_build and not cached:
		var reply: PackedByteArray = _call(Codec.command(1, [key.x, key.y, key.z, step, expected_build_epoch]))
		if not Codec.reply_ok(reply):
			if reply.size() >= 12 and reply.decode_u32(8) == 4:
				return {"cancelled": true}
			return {"error": "Native mesh build failed: %s" % key}
		data = reply.slice(16)
	var result: Dictionary = Codec.decode_mesh(data)
	if (geometry_cached or (cached and not derived and relight_cache)) and not result.has("error"):
		var updated: Dictionary = _refresh_visibility(result["arrays"], expected_build_epoch)
		if updated.has("error") or bool(updated.get("cancelled", false)):
			return updated
		result["arrays"] = updated["arrays"]
		result["cavity_visibility"] = updated["cavity_visibility"]
	if not snapshot_build and not geometry_cached and not result.has("error") and not derived and (not cached or relight_cache):
		# A relit base packet is not equal to its original encoded bytes.
		if cached and relight_cache:
			data = Codec.encode_decoded_mesh(result)
		_remember_packet(key, data)
		if not foreground and cache_valid and not _input_active():
			disk_cache.store_packet(key, data)
	# Bundled base packets were not built against this dependency signature.
	# Only freshly reconstructed or exact-snapshot packets may seed this cache.
	if not foreground and not snapshot_build and not geometry_cached and (not cached or derived) and not content.is_empty() and not result.has("error") and not _input_active():
		disk_cache.store_packet(key, data, content)
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
	result["geometry_cached"] = geometry_cached
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
	if int(item.get("brick_bottom",-1))>=0: result["brick_bottom"]=item.brick_bottom
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
	if profile_regions: _call(Codec.command(18,[1]))
	_push({"kind": "startup", "message": load_message,
		"components": components.duplicate(), "modified": _call(Codec.command(10)), "stats": _call(Codec.command(0))})
	while true:
		semaphore.wait()
		# All meshing modes serve bounded queries before taking another background
		# job. The selector cannot cross an already queued mutation or save.
		_service_density_query()
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
		if diagnostic_enabled:
			diagnostic_active={"kind":active_kind,"key":str(job.get("key","")),"started_us":Time.get_ticks_usec(),"submitted_us":job.get("submitted_us",0)}
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
				elif remaining_kind == "density_batch":
					_push({"kind":"density_batch","token":remaining.token,"epoch":remaining.epoch,"revision":remaining.revision,"status":"cancelled","values":PackedFloat32Array()})
				elif remaining_kind == "density_ray":
					_push({"kind":"density_ray","status":"cancelled","cancelled":true,"token":remaining["token"],"epoch":remaining["epoch"],"requested_revision":remaining["revision"],"build_epoch":remaining["build_epoch"]})
				elif remaining_kind == "partition":
					_push({"kind":"partition","packets":[],"cancelled":true,"token":remaining.token,"epoch":remaining.epoch,"stamp":remaining.stamp})
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
						_call(Codec.command(6, [world_seed,world_generator]))
						write_allowed = _initialize_generated_components()
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
		if kind == "partition":
			var partition: Dictionary=native.experimental_partition_mesh_budgeted(job.packet,128*1024*1024,128*1024*1024,job.build_epoch)
			var chunks: Array[Dictionary]=[]
			for packet: PackedByteArray in partition.packets:
				var decoded: Dictionary=Codec.decode_mesh(packet)
				if decoded.has("error"): chunks.clear();break
				var prepared: Dictionary=collision_recipes.prepare(decoded.faces,_collision_piece_triangles)
				if not prepared.ok: chunks.clear();break
				decoded["collision_pieces"]=prepared.pieces
				decoded["faces"]=PackedVector3Array()
				decoded["worker_ms"]=0.0
				chunks.append(decoded)
			partition["chunks"]=chunks
			partition["kind"]="partition"
			partition["token"]=job.token
			partition["epoch"]=job.epoch
			partition["stamp"]=job.stamp
			partition["queue_ms"]=queue_ms
			_push(partition)
		elif kind == "mesh":
			_execute_mesh(job,bool(job.get("interaction_mesh",false)))
		elif kind == "edit":
			_apply_components(job.get("component_snapshot", {}))
			var before_stats: PackedByteArray = _call(Codec.command(0))
			var begin: int = Time.get_ticks_usec()
			var reply := PackedByteArray()
			var commands: Array = job.get("commands", [job["command"]])
			var member_changed: Array[bool] = []
			var removed_samples:=PackedInt64Array();removed_samples.resize(16)
			var revision_before: int = before_stats.decode_u32(12)
			for command: PackedByteArray in commands:
				reply = _call(command)
				var removed:=Codec.excavation_samples(reply)
				for material in range(16): removed_samples[material]+=removed[material]
				var member_stats: PackedByteArray = _call(Codec.command(0))
				var revision_after: int = member_stats.decode_u32(12)
				member_changed.push_back(revision_after != revision_before)
				revision_before = revision_after
				if not Codec.reply_ok(reply):
					# A failed multi-command group is not claimed rollback-atomic.
					# Stop publishing/saving rather than overwrite the last valid save.
					write_allowed = false
					cache_valid = false
					removed_samples.fill(0)
					break
			var edit_ms: float = float(Time.get_ticks_usec() - begin) / 1000.0
			var after_stats: PackedByteArray = _call(Codec.command(0))
			var no_change: bool = Codec.reply_ok(reply) and before_stats.decode_u32(12) == after_stats.decode_u32(12)
			if not Codec.reply_ok(reply) or no_change:
				_push({"kind": "edit", "chunks": [], "reply": reply, "epoch": job["epoch"],
					"ticket": job["ticket"], "edit_ms": edit_ms, "stats": after_stats,
					"queue_ms": queue_ms, "no_change": no_change, "member_changed": member_changed, "removed_samples":removed_samples, "worker_finished_us": Time.get_ticks_usec()})
			else:
				cache_valid = false
				latest_packets.clear()
				latest_packet_bytes = 0
				_push({"kind": "edit_begin", "epoch": job["epoch"], "ticket": job["ticket"],
					"count": job["tiles"].size(), "edit_ms": edit_ms, "queue_ms": queue_ms, "stats": after_stats, "member_changed": member_changed, "removed_samples":removed_samples})
				# Stream finished patches to main-thread staging immediately. Worker
				# builds and resource preparation OVERLAP instead of running in series.
				var build_total: float = 0.0
				for item: Dictionary in job["tiles"]:
					var selected: Array=item.get("brick_bottoms",[])
					var retain_geometry:=false
					# The 17m halo protects changes to the simplifier's page-presence
					# mask. Existing pages never disappear during an edit. If none were
					# allocated, only the actual field/normal support can change.
					if region_terrain and not selected.is_empty() and before_stats.decode_u32(20)==after_stats.decode_u32(20):
						var key: Vector3i=item.key
						var owner_size:=mini(32,key.z)
						var local: Array=[]
						var bounds:=AABB(job.geometry_lo,job.geometry_hi-job.geometry_lo)
						for id: int in selected:
							var column: int=id/256
							var owner:=AABB(Vector3(key.x+(column%8)*owner_size,id%256,key.y+(column/8)*owner_size),Vector3(owner_size,32,owner_size))
							if owner.grow(1.0).intersects(bounds): local.append(id)
						selected=local
						retain_geometry=selected.is_empty()
					var chunk: Dictionary = {"retain_geometry":true,"worker_ms":0.0} if retain_geometry else _build(item["key"], false, int(job["build_epoch"]), false, selected, true)
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
				_call(Codec.command(6, [world_seed,world_generator]))
				write_allowed = _initialize_generated_components()
				if not write_allowed: message = "ERROR: generated lake definitions unavailable"
			else:
				message = _load()
			_call(Codec.command(14, [surface_style]))
			latest_packets.clear()
			latest_packet_bytes = 0
			if kind == "reset":
				snapshot_id = "new_generator_%d_seed_%d"%[world_generator,world_seed]
			_set_cache_snapshot(snapshot_id)
			_push({"kind": "reload", "epoch": job["epoch"], "message": message,
				"components": components.duplicate(), "modified": _call(Codec.command(10)), "stats": _call(Codec.command(0))})
		elif kind == "density_batch":
			_execute_density_batch(job)
		elif kind == "lake_slice":
			_execute_lake_slice(job)
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
			_execute_density_query(job)
		elif kind == "height":
			var reply: PackedByteArray = _call(Codec.point_command(job["point"]))
			_push({"kind": "height", "reply": reply, "point": job["point"], "token": job["token"]})
		mutex.lock()
		active_kind = "idle"
		diagnostic_active={}
		mutex.unlock()
