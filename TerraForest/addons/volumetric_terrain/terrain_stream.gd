# SPDX-License-Identifier: 0BSD
# Cached, ordinary Godot meshes. NO full-screen field shader, no per-frame terrain meshing.
extends Node3D
signal initialized(message: String)
signal message_changed(message: String)
signal height_received(point: Vector3, height: float, token: int)
signal density_ray_received(result: Dictionary)
signal placement_target_received(result: Dictionary)
var native_revision: int = 0
var _density_serial: int = 0
var _density_requests: Dictionary = {}
signal edit_published(latency_ms: float)
signal edit_measured(record: Dictionary)
signal work_measured(record: Dictionary)
signal stage_measured(label: String, milliseconds: float)
signal collision_piece_measured(sample: Dictionary, faces: PackedVector3Array)
var profile_collision_pieces := false
var committed_measurements: Array[Dictionary] = []
var published_revision: int = 0
var derived_metrics: Dictionary = {}
var foreground_brush: bool = false
var foreground_attack: bool = false
var diagnostics_pause_streaming: bool = false
# Offline generation validates only arrival collision; gameplay keeps full coverage.
var generation_collision_only: bool = false
var latest_edit_descriptor: Dictionary = {}
var latest_edit_members: Array[Dictionary] = []
var latest_member_changes: Array = []
var edit_accepted_us: int = 0
var _edit_support_providers:Array[Dictionary]=[]
var _edit_support_snapshots:Array[Dictionary]=[]
var _edit_support_result:Array=[]
var last_support_worker_ms:=0.0
var last_support_publish_ms:=0.0
var last_support_capture_ms:=0.0
var last_support_instances:=0

func register_edit_support(capture:Callable,apply:Callable)->void:
	_edit_support_providers.append({"capture":capture,"apply":apply})

func _capture_edit_support(bounds:AABB)->Array[PackedVector3Array]:
	var began:=Time.get_ticks_usec()
	_edit_support_snapshots.clear();_edit_support_result.clear();last_support_instances=0;last_support_worker_ms=0;last_support_publish_ms=0
	var points:Array[PackedVector3Array]=[]
	for provider:Dictionary in _edit_support_providers:
		if not provider.capture.is_valid() or not provider.apply.is_valid():continue
		var snapshots:Array=provider.capture.call(bounds)
		for snapshot:Dictionary in snapshots:
			_edit_support_snapshots.append({"apply":provider.apply,"snapshot":snapshot})
			points.append(snapshot.points)
			last_support_instances+=snapshot.ids.size()
	last_support_capture_ms=(Time.get_ticks_usec()-began)/1000.0
	return points

func set_brush_active(active: bool) -> void:
	foreground_brush = active
	backend.set_input_active(active or foreground_attack)
	if active:
		note_interaction()

func set_attack_active(active: bool) -> void:
	foreground_attack = active
	backend.set_input_active(active or foreground_brush)
	if active:
		note_interaction()
signal reload_started
signal save_completed(success: bool)
var lifecycle_ready: Callable
var _reload_requested := false
var _reload_reset := false
const Backend = preload("res://addons/volumetric_terrain/terrain_backend.gd")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
const ROOT_SIZE: int = 256
const FINE_SIZE: int = 16
@export_range(100, 10000, 1) var retire_budget_us: int = 500
@export_range(16777216, 1073741824, 1) var cache_byte_limit: int = 192 * 1024 * 1024
@export_range(64, 4096, 1) var cache_entry_limit: int = 512
@export_range(100, 16000, 1) var main_build_budget_us: int = 2500
const LIGHT_UPLOAD_BYTES: int = 256 * 1024
const SURFACE_RECEIVE_BUDGET_US: int = 1000
var _surface_replies: Array[Dictionary] = []
var backend = Backend.new()
var partition_request: Dictionary = {}
var _partition_serial: int = 0
var planner: RefCounted
var material: Material
var focus := Vector3(960, 110, 1310)
var travel_velocity := Vector3.ZERO
var epoch: int = 0
var world_ready: bool = false
var require_collision: bool = true
var tiles: Dictionary = {}
var stamps: Dictionary = {}
var in_flight: Dictionary = {}
var modified_columns: Dictionary = {}
var split_state: Dictionary = {}
var requested_keys: Dictionary = {}
var activation_keys: Dictionary = {}
var interaction_target:=Vector3.INF
var interaction_target_until_us: int=0

func set_interaction_target(point: Vector3) -> void:
	var now:=Time.get_ticks_usec()
	var changed: bool=now>=interaction_target_until_us or not interaction_target.is_finite()
	if point.is_finite() and interaction_target.is_finite():
		changed=changed or Vector2i(floori(point.x/16),floori(point.z/16))!=Vector2i(floori(interaction_target.x/16),floori(interaction_target.z/16))
	interaction_target=point
	interaction_target_until_us=now+250000 if point.is_finite() else 0
	if changed: schedule_timer=0.0
var visible_cut: Array[Vector3i] = []
var _cut_dirty := true
var active_leaves: Dictionary = {}
var roots: Array[Vector3i] = []
var staging: Array[Dictionary] = []
var staging_versions: Dictionary = {}
var staged_batch: Dictionary = {}
# Main-thread publication partner for a wet edit. Both halves keep the last
# published scene while their revision-owned replacements are prepared.
var _hand_edit:bool=false
var resident_edit_surface:Dictionary={}
var _joint_ticket:=-1
var _joint_epoch:=-1
var _joint_owners:Dictionary={}
func reserve_joint_edit(ticket:int,areas:Array[AABB])->void:
	if not pending_edit or ticket!=edit_ticket:return
	_joint_owners.clear()
	for key:Vector3i in _edit_visible_owners:
		var tile:=Rect2(key.x,key.y,key.z,key.z)
		for bounds:AABB in areas:
			if tile.intersects(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)),true):
				_joint_owners[key]=true
				break
	if not _joint_owners.is_empty():
		_joint_epoch=epoch
		_joint_ticket=ticket

func joint_edit_pending()->bool:
	return pending_edit and _joint_epoch==epoch and _joint_ticket==edit_ticket

func publish_joint_edit(ticket:int,install_water:Callable)->bool:
	if ticket!=edit_ticket or not joint_edit_pending() or not latest_error.is_empty():return false
	var owners:Dictionary={}
	for key:Vector3i in _joint_owners:
		if owners.has(key):continue
		var group:=_ready_edit_group(key)
		if group.is_empty():return false
		for id:Vector3i in group:owners[id]=true
	if not install_water.call():return false
	_joint_ticket=-1
	_joint_owners.clear()
	_install_ready_edit_group(owners.keys())
	return true

signal edit_field_ready(ticket:int)
# One binary write footprint per command, in commit order. An empty entry
# requires conservative reconstruction for that command.
signal edit_writes_ready(ticket:int,footprints:Array)
signal edit_geometry_installed(ticket:int)
signal edit_region_installed(ticket:int,keys:Array)
# The frozen visible cut can contain several tile sizes along one brush edge.
var _contact_entries:Dictionary={}
var _contact_visible:=false
var _contact_checked:=false
var _contact_accepted_ticket:=-1
var _edit_visible_owners:Dictionary={}
var _edit_owner_cells:Dictionary={}
var batch_remaining: int = 0
var pending_edit: bool = false
var edit_ticket: int = 0
var edit_started_us: int = 0
var last_edit_ms: float = 0.0
var last_mesh_ms: float = 0.0
var last_publish_ms: float = 0.0
var last_latency_ms: float = 0.0
var worker_builds: int = 0
var total_triangles: int = 0
var cache_bytes: int = 0
var sdf_pages: int = 0
var blocks: int = 0
var total_edits: int = 0
var schedule_timer: float = 0.0
var autosave_timer: float = 0.0
var autosave_paused: bool = false
var last_interaction_us: int = 0
var changed_since_save: bool = false
var _manual_save_requested: bool = false
var temporary: bool = false
var stopping: bool = false
var closing: bool = false
var require_published_shutdown: bool = false
var latest_error: String = ""
var preparation: Dictionary = {}
var paused_preparations: Array[Dictionary] = []
var retired_nodes: Array[Node] = []
var retired_payloads: Array[Dictionary] = []
var last_queue_ms: float = 0.0
var last_worker_finished_us: int = 0
var last_prepare_latency_ms: float = 0.0
var last_retire_ms: float = 0.0
var last_receive_ms: float = 0.0
var last_schedule_ms: float = 0.0
var last_collision_piece_ms: float = 0.0
var collision_pieces_reused: int = 0
var collision_pieces_built: int = 0
var last_collision_match_ms: float = 0.0
var last_mesh_upload_ms: float = 0.0
var last_commit_ms: float = 0.0
var last_density_tiles: int = 0
var last_untouched_surface_tiles:int=0
var last_direct_triangle_pages:int=0
var last_worker_packed_surfaces:int=0
var last_page_selection:Dictionary={}
var last_relight_tiles: int = 0
var slowest_stage: String = "none"
var slowest_stage_ms: float = 0.0
var last_total_build_ms: float = 0.0
var last_publish_frame_ms: float = 0.0
var last_draw_latency_ms: float = 0.0
var pending_draw_us: int = 0
var shadow_columns: Dictionary = {}
var edit_rollback: Array[Dictionary] = []
var edit_lo := Vector3.ZERO
var edit_hi := Vector3.ZERO
var shadow_lo := Vector3.ZERO
var shadow_hi := Vector3.ZERO

var edit_worker_done: bool = false
var lighting_dirty: Dictionary = {}
var lighting_in_flight: Dictionary = {}
var lighting_generation: int = 0
var edit_geometry_bounds: Array[AABB] = []
var geometry_lo := Vector3.ZERO
var geometry_hi := Vector3.ZERO
var root_coverage: int = 0
var covered_roots: Dictionary = {}
var initial_loading: bool = true
var last_geometry_done_us: int = 0
var lighting_upload: Dictionary = {}
var lighting_attribute_updates: int = 0
var last_light_upload_ms: float = 0.0
var nearby_first: bool = false
var last_capture_wait_ms: float = 0.0
var unresolved_light_rays: int = 0
var reused_light_probes: int = 0
var slow_edits: Array[Dictionary] = []

func start(terrain_material: Material, temporary_world: bool) -> Error:
	if not ClassDB.class_exists("NativeTerrainPlanner"):
		GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	if not ClassDB.class_exists("NativeTerrainPlanner"):
		push_error("Terrain requires the current native planner build; the legacy terrain binary is not supported.")
		return ERR_UNAVAILABLE
	planner = ClassDB.instantiate("NativeTerrainPlanner")
	backend.edit_results_ready.connect(_receive_edit_notice,CONNECT_DEFERRED)
	if not RenderingServer.frame_pre_draw.is_connected(_before_draw):RenderingServer.frame_pre_draw.connect(_before_draw)
	material = terrain_material
	# Receive completed work before the parent consumes the next pending sample.
	# Does not change physics ordering or increase the per-frame upload budget.
	process_priority = -10
	RenderingServer.frame_post_draw.connect(_post_draw)
	temporary = temporary_world
	for z in range(0, 2048, ROOT_SIZE):
		for x in range(0, 2048, ROOT_SIZE):
			roots.push_back(Vector3i(x, z, ROOT_SIZE))
	return backend.start(temporary_world)

func shutdown_after_edits() -> bool:
	closing=true
	set_attack_active(false)
	set_brush_active(false)
	var deadline:=Time.get_ticks_msec()+30000
	while pending_edit and latest_error.is_empty() and not stopping and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	var settled: bool=not pending_edit and latest_error.is_empty()
	while lifecycle_ready.is_valid() and not lifecycle_ready.call("shutdown") and not stopping and Time.get_ticks_msec()<deadline:
		await get_tree().process_frame
	if lifecycle_ready.is_valid() and not lifecycle_ready.call("shutdown"):
		settled = false
	if not settled:
		backend.disable_snapshot_writes("world state did not settle before shutdown")
		message_changed.emit("Closing without a new save: world state did not settle; previous save retained")
	shutdown()
	return settled and (backend.temporary or backend._last_save_success)

func shutdown() -> void:
	if stopping:
		return
	if lifecycle_ready.is_valid() and not lifecycle_ready.call("shutdown"):
		backend.disable_snapshot_writes("scene teardown interrupted addon transfers")
	if require_published_shutdown and pending_edit:
		# Direct scene teardown cannot run publication callbacks. Keep the last
		# consistent disk snapshot instead of saving unaccounted excavation.
		backend.disable_snapshot_writes("scene teardown interrupted pending edit publication")
	stopping = true
	_cancel_partition()
	_cancel_density_requests("cancelled")
	set_process(false)
	if RenderingServer.frame_post_draw.is_connected(_post_draw):
		RenderingServer.frame_post_draw.disconnect(_post_draw)
	backend.stop()
	if not slow_edits.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://reports"))
		var report: FileAccess = FileAccess.open("user://reports/slow_edits_%d.json" % OS.get_process_id(), FileAccess.WRITE)
		if report != null:
			report.store_string(JSON.stringify(slow_edits, "	"))
			report.close()
	# Preparation nodes need not belong to the scene tree yet. Free these and
	# deferred retired roots explicitly instead of leaking them on shutdown.
	if not preparation.is_empty():
		var prepared: Node = preparation["entry"]["node"]
		if is_instance_valid(prepared) and not preparation.entry.has("resident_swap"):
			prepared.free()
		preparation.clear()
	for paused: Dictionary in paused_preparations:
		var prepared: Node = paused.entry.node
		if is_instance_valid(prepared): prepared.free()
	paused_preparations.clear()
	for retired: Node in retired_nodes:
		if is_instance_valid(retired):
			retired.free()
	retired_nodes.clear()
	retired_payloads.clear()
	staging.clear()
	_surface_replies.clear()

func _exit_tree() -> void:
	if require_published_shutdown and not stopping:
		backend.disable_snapshot_writes("scene removed before graceful shutdown; previous checkpoint retained")
	shutdown()

# Worker completions can arrive after the normal process turn. Share one
# publication allowance across all opportunities in the same process frame.
var _staging_frame:=-1
var _staging_spent_us:=0

func _receive_edit_notice()->void:
	if stopping or (not pending_edit and _density_requests.is_empty()) or not is_inside_tree() or not is_processing() or not can_process():return
	var ready:Array[Dictionary]=backend.poll()
	if not ready.is_empty():_dispatch_results(ready,false)
	if pending_edit:_stage_with_frame_budget()

# Consume an already-finished local edit before the renderer takes this frame.
# The usual deferred notification and process pump also serve headless worlds.
func _before_draw()->void:
	if pending_edit and (_hand_edit or joint_edit_pending()) and OS.get_thread_caller_id()==OS.get_main_thread_id():
		_receive_edit_notice()

func _stage_with_frame_budget()->void:
	var frame:=Engine.get_process_frames()
	if frame!=_staging_frame:
		_staging_frame=frame
		_staging_spent_us=0
	var remaining:=main_build_budget_us-_staging_spent_us
	if remaining<=0:
		last_publish_frame_ms=0
		return
	var started:=Time.get_ticks_usec()
	_drain_staging(remaining)
	_staging_spent_us+=Time.get_ticks_usec()-started

func _process(delta: float) -> void:
	if stopping:
		return
	var receive_begin: int = Time.get_ticks_usec()
	var ready_results: Array[Dictionary]=backend.poll()
	_record_stage("receive poll",(Time.get_ticks_usec()-receive_begin)/1000.0)
	_dispatch_results(ready_results)
	last_receive_ms = float(Time.get_ticks_usec() - receive_begin) / 1000.0
	_record_stage("receive", last_receive_ms)
	_stage_with_frame_budget()
	_record_stage("staging frame", last_publish_frame_ms)
	_retire_some()
	if closing: return # Drain publication, but admit no new background work.
	if _reload_requested:
		reload_world(_reload_reset)
	if not world_ready:
		return
	_flush_manual_save()
	schedule_timer -= delta
	if schedule_timer <= 0.0 and (foreground_brush or generation_collision_only) and not pending_edit and not diagnostics_pause_streaming:
		_schedule_urgent_collision()
	if schedule_timer <= 0.0 and not pending_edit and not foreground_brush and not generation_collision_only and not diagnostics_pause_streaming:
		schedule_timer = 0.025 if initial_loading else 0.10
		var schedule_begin: int = Time.get_ticks_usec()
		var planned_coverage:=_schedule()
		_record_stage("LOD requests",float(Time.get_ticks_usec()-schedule_begin)/1000.0)
		var cut_begin: int = Time.get_ticks_usec()
		_update_cut(planned_coverage)
		_record_stage("LOD coverage",float(Time.get_ticks_usec()-cut_begin)/1000.0)
		var evict_begin: int = Time.get_ticks_usec()
		_evict(_planned_eviction)
		_record_stage("LOD eviction",float(Time.get_ticks_usec()-evict_begin)/1000.0)
		last_schedule_ms = float(Time.get_ticks_usec() - schedule_begin) / 1000.0
		_record_stage("LOD schedule/cut/evict", last_schedule_ms)
	var lighting_begin:=Time.get_ticks_usec()
	_schedule_lighting()
	_record_stage("lighting schedule",(Time.get_ticks_usec()-lighting_begin)/1000.0)
	# Loading time must not consume the playable autosave interval.
	# Otherwise long startup submits a save immediately before first travel.
	if not autosave_paused:autosave_timer += delta
	var quiet: bool = Time.get_ticks_usec() - last_interaction_us >= 3000000
	if not autosave_paused and not temporary and autosave_timer >= 15.0 and changed_since_save and not pending_edit and quiet and backend.status() == "idle" and backend.queued() == 0:
		var save_begin:=Time.get_ticks_usec()
		if backend.submit({"kind": "save"}):
			autosave_timer = 0.0
			changed_since_save = false
		_record_stage("save capture",(Time.get_ticks_usec()-save_begin)/1000.0)

func _receive_measured(result: Dictionary) -> void:
	var began:=Time.get_ticks_usec()
	_receive(result)
	_record_stage("receive "+str(result.get("kind","unknown")),(Time.get_ticks_usec()-began)/1000.0)

func _dispatch_results(ready: Array[Dictionary],drain_surfaces:bool=true) -> void:
	for result: Dictionary in ready:
		if result.get("kind","")=="surface_batch":_surface_replies.append(result)
		else:_receive_measured(result)
	if not drain_surfaces:return
	var began:=Time.get_ticks_usec()
	var budget_us:=maxi(main_build_budget_us,SURFACE_RECEIVE_BUDGET_US) if initial_loading else SURFACE_RECEIVE_BUDGET_US
	while not _surface_replies.is_empty():
		_receive_measured(_surface_replies.pop_front())
		if Time.get_ticks_usec()-began>=budget_us:break

func note_interaction() -> void:
	last_interaction_us = Time.get_ticks_usec()

func _record_stage(label: String, ms: float) -> void:
	stage_measured.emit(label, ms)
	if ms > slowest_stage_ms:
		slowest_stage_ms = ms
		slowest_stage = label
	if ms > 50.0 and OS.is_stdout_verbose():
		print("[terrain-hitch] ", label, " ", snappedf(ms, 0.01), " ms at ", Time.get_ticks_msec())

func _retire_some() -> void:
	# Free one collision piece at a time, not an entire old collision subtree.
	# Detach from physics only on the main thread; this budget is not preemptive.
	var begin: int = Time.get_ticks_usec()
	# Mesh arrays and collision-cache dictionaries can own substantial CPU data.
	# Release detached entries under the same budget as retired scene nodes.
	while not retired_payloads.is_empty() and Time.get_ticks_usec() - begin < retire_budget_us:
		retired_payloads.pop_back()
	while not retired_nodes.is_empty() and Time.get_ticks_usec() - begin < retire_budget_us:
		var retired: Node = retired_nodes[0]
		if not is_instance_valid(retired):
			retired_nodes.pop_front()
			continue
		if retired.get_child_count() > 0:
			var child: Node = retired.get_child(0)
			if child.get_child_count() > 0:
				child.get_child(0).free()
			else:
				child.free()
		else:
			retired_nodes.pop_front()
			retired.free()
	last_retire_ms = float(Time.get_ticks_usec() - begin) / 1000.0
	_record_stage("retire collision/mesh", last_retire_ms)

func _read_stats(data: PackedByteArray) -> void:
	if Codec.reply_ok(data) and data.size() >= 32:
		native_revision = data.decode_u32(12)
		total_edits = data.decode_u32(16)
		sdf_pages = data.decode_u32(20)
		blocks = data.decode_u32(24)

func _read_modified(data: PackedByteArray) -> void:
	modified_columns.clear()
	shadow_columns.clear()
	if not Codec.reply_ok(data) or data.size() < 16:
		return
	var count: int = data.decode_u32(12)
	if data.size() != 16 + count * 4:
		return
	# Rectangle union by a 2-D difference/prefix grid: O(saved columns + 126^2),
	# not 49*49 Dictionary writes PER saved column during the loading screen.
	const PITCH: int = 127
	var difference := PackedInt32Array()
	difference.resize(PITCH * PITCH)
	for i in range(count):
		var code: int = data.decode_u32(16 + i * 4) - 1
		if code < 0 or code >= 126 * 126:
			continue
		var cell := Vector2i(code % 126, code / 126)
		modified_columns[cell] = true
		var x0: int = maxi(0, cell.x - 88)
		var z0: int = maxi(0, cell.y - 88)
		var x1: int = mini(126, cell.x + 89)
		var z1: int = mini(126, cell.y + 89)
		difference[z0 * PITCH + x0] += 1
		difference[z0 * PITCH + x1] -= 1
		difference[z1 * PITCH + x0] -= 1
		difference[z1 * PITCH + x1] += 1
	for z in range(126):
		var row: int = 0
		for x in range(126):
			var at: int = z * PITCH + x
			row += difference[at]
			var previous: int = difference[at - PITCH] if z > 0 else 0
			difference[at] = row + previous
			if difference[at] > 0:
				shadow_columns[Vector2i(x, z)] = true

func _receive(result: Dictionary) -> void:
	if work_measured.has_connections() and str(result.get("kind", "")) in ["mesh", "edit_chunk", "relight"]:
		var key: Vector3i = result.get("key", Vector3i.ZERO)
		work_measured.emit({"engine_us": Time.get_ticks_usec(), "kind": result.get("kind", ""),
			"key": [key.x, key.y, key.z], "worker_ms": result.get("worker_ms", null),
			"cached": result.get("cached", false), "derived_cached": result.get("derived_cached", false),
			"bytes": result.get("bytes", null), "triangles": result.get("triangles", null),
			"region_parts":result.get("region_parts",0),"geometry_cache_hits":result.get("geometry_cache_hits",0),"region_stages":result.get("region_stages",{}),
			"cancelled": result.get("cancelled", false), "error": result.get("error", "")})
	if result.has("cache_stats"):
		derived_metrics = result["cache_stats"]
	if result.has("light_stats"):
		var light: PackedByteArray = result["light_stats"]
		if Codec.reply_ok(light) and light.size() == 36:
			unresolved_light_rays = light.decode_u32(20)
			reused_light_probes = light.decode_u32(24)
	var kind: String = str(result.get("kind", ""))
	if kind == "partition":
		_receive_partition(result)
	elif kind == "startup" or kind == "reload":
		if kind == "reload" and int(result["epoch"]) != epoch:
			return
		_read_modified(result["modified"])
		_read_stats(result["stats"])
		world_ready = true
		var text: String = str(result["message"])
		if text.begins_with("ERROR:"):
			latest_error = text
			world_ready = false
			message_changed.emit(text)
			return
		if material is ShaderMaterial:
			material.set_shader_parameter("coastal_inlet",backend.world_generator==18)
			material.set_shader_parameter("surrounding_coast",backend.world_generator in [19,21,23,25,27,29,31])
			material.set_shader_parameter("regional_temperate",backend.world_generator in [7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31])
			material.set_shader_parameter("alpine_snow_enabled",backend.world_generator in [7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31])
		message_changed.emit(text)
		initialized.emit(text)
		schedule_timer = 0.0
	elif kind in ["density_ray","placement_target"]:
		var serial: int=int(result.get("token",-1))
		if not _density_requests.has(serial): return
		var request: Dictionary=_density_requests[serial]
		_density_requests.erase(serial)
		var reply := result.duplicate()
		reply["token"]=request.token
		if kind=="placement_target":reply["region"]=request.get("region",false)
		if stopping or not world_ready or pending_edit or request.epoch!=epoch or request.revision!=native_revision or request.ticket!=edit_ticket or int(result.get("epoch",-1))!=request.epoch or int(result.get("requested_revision",-1))!=request.revision:
			reply["status"]="stale"
		elif str(reply.get("status","error")) in ["hit","miss","work_limit"] and int(reply.get("revision",-1))!=native_revision:
			reply["status"]="stale"
		if reply.get("status","")!="hit":
			reply.erase("position");reply.erase("fraction");reply.erase("cell")
		if kind=="placement_target":placement_target_received.emit(reply)
		else:density_ray_received.emit(reply)
	elif kind == "height":
		var reply: PackedByteArray = result["reply"]
		if Codec.reply_ok(reply) and reply.size() >= 16:
			height_received.emit(result["point"], reply.decode_float(12), int(result["token"]))
	elif kind == "message":
		if result.get("operation","")=="save": save_completed.emit(result.get("success",false))
		message_changed.emit(str(result["message"]))
	elif kind == "mesh":
		var key: Vector3i = result.get("key", Vector3i.ZERO)
		if in_flight.has(key) and in_flight[key] == Vector2i(int(result["epoch"]), int(result["stamp"])):
			in_flight.erase(key)
		if int(result["epoch"]) != epoch or int(result["stamp"]) != int(stamps.get(key, 0)):
			return
		if bool(result.get("cancelled", false)):
			return
		if result.has("error"):
			_fail(str(result["error"]))
			return
		staging_versions[key] = Vector2i(epoch, int(result["stamp"]))
		staging.push_back(result)
		if activation_keys.has(key): schedule_timer=0.0
	elif kind == "edit_begin":
		if int(result["epoch"]) != epoch or int(result["ticket"]) != edit_ticket:
			return
		latest_member_changes = result.get("member_changed", [])
		resident_edit_surface=result.get("resident_surface",{})
		last_page_selection=result.get("page_selection",{})
		_contact_accepted_ticket=edit_ticket
		_activate_contact()
		_record_stage("resident cut snapshot and dispatch" if result.get("contact_parallel",false) else "resident cut worker",float(result.get("contact_ms",0)))
		last_edit_ms = float(result["edit_ms"])
		last_queue_ms = float(result["queue_ms"])
		last_total_build_ms = 0.0
		_read_stats(result["stats"])
		_mark_modified_columns()
		batch_remaining = int(result["count"])
		staged_batch.clear()
		edit_worker_done = false
		edit_writes_ready.emit(edit_ticket,result.get("writes",[]))
		edit_field_ready.emit(edit_ticket)
	elif kind == "edit_chunk":
		if int(result["epoch"]) != epoch or int(result["ticket"]) != edit_ticket:
			return
		if result.has("error"):
			_fail(str(result["error"]))
			return
		if result.get("triangle_pages",false) and tiles.get(result.key,{}).get("triangle_pages",false):
			last_direct_triangle_pages+=int(result.get("direct_pages",0))
			var changed:Array=[]
			var bytes:=0
			var triangles:=0
			for page:Dictionary in result.bricks:
				var old:Dictionary=tiles[result.key].bricks.get(page.brick_bottom,{})
				if old.get("arrays",[])==page.arrays:continue
				changed.append(page)
				bytes+=int(page.bytes)
				triangles+=int(page.triangles)
			result.bricks=changed
			result.brick_partial=true
			result.bytes=bytes
			result.triangles=triangles
			result.retain_geometry=changed.is_empty()
		if result.get("retain_geometry",false):
			if result.get("untouched_surface",false):last_untouched_surface_tiles+=1
			staged_batch[result.key]={"retain_geometry":true,"stamp":result.stamp}
			batch_remaining-=1
			if batch_remaining==0 and edit_worker_done: _commit_batch()
			return
		result["kind"] = "batch"
		# Keep interactive tiles ahead of background work in worker priority
		# order. Later arrivals must not push the aimed-at centre to the back.
		var insert_at:=0
		while insert_at<staging.size() and staging[insert_at].get("kind","")=="batch":
			insert_at+=1
		staging.insert(insert_at,result)
	elif kind == "edit_done":
		if not pending_edit or int(result["epoch"]) != epoch or int(result["ticket"]) != edit_ticket:
			return
		last_total_build_ms = float(result["build_total_ms"])
		_edit_support_result=result.get("support",[])
		last_support_worker_ms=result.get("support_ms",0.0)
		last_worker_finished_us = int(result["worker_finished_us"])
		edit_worker_done = true
		if batch_remaining == 0:
			_commit_batch()
	elif kind == "relight":
		var key: Vector3i = result["key"]
		if int(result["epoch"]) != epoch or int(result["stamp"]) != int(stamps.get(key, 0)) or int(result["light_ticket"]) != int(lighting_dirty.get(key, -1)) or bool(result.get("cancelled", false)):
			if int(lighting_in_flight.get(key, -1)) == int(result["light_ticket"]):
				lighting_in_flight.erase(key)
			return
		if result.has("error"):
			_fail(str(result["error"]))
			return
		# Background illumination cannot delay an interactive geometry batch.
		staging.push_back(result)
	elif kind == "edit":
		if int(result["epoch"]) != epoch or int(result["ticket"]) != edit_ticket:
			return
		_retire_contact()
		latest_member_changes = result.get("member_changed", [])
		last_edit_ms = float(result["edit_ms"])
		last_queue_ms = float(result.get("queue_ms", 0.0))
		last_worker_finished_us = int(result.get("worker_finished_us", Time.get_ticks_usec()))
		last_total_build_ms = 0.0
		_read_stats(result["stats"])
		if not Codec.reply_ok(result["reply"]):
			pending_edit = false
			_edit_support_snapshots.clear();_edit_support_result.clear()
			if result.get("recoverable",false):
				_rollback_dirty()
				var record:=_edit_measurement(false)
				record["rejected"]=true
				_emit_member_measurements(record,0)
				schedule_timer=0.0
				message_changed.emit("Terrain stroke rejected: invalid tool bounds or road profile." if result.reply.decode_u32(8)==1 else "Stroke not applied: outside terrain or edit memory limit. Try a smaller in-world brush, or save to release edit memory.")
				return
			_fail("Edit rejected by native core (invalid request, capacity, or allocation failure)")
			return
		if bool(result.get("no_change", false)):
			_edit_support_snapshots.clear();_edit_support_result.clear()
			_rollback_dirty()
			var record: Dictionary = _edit_measurement(false)
			record["draw_ms"] = null
			_emit_member_measurements(record, 0)
			pending_edit = false
			schedule_timer = 0.0
			return
		_mark_modified_columns()
		var chunks: Array = result["chunks"]
		for part: Dictionary in chunks:
			last_total_build_ms += float(part.get("worker_ms", 0.0))
		for chunk: Dictionary in chunks:
			if chunk.has("error"):
				pending_edit = false
				_fail(str(chunk["error"]))
				return
		batch_remaining = chunks.size()
		staged_batch.clear()
		for chunk: Dictionary in chunks:
			if chunk.has("error"):
				pending_edit = false
				_fail(str(chunk["error"]))
				return
			chunk["kind"] = "batch"
			chunk["epoch"] = epoch
			chunk["ticket"] = edit_ticket
			staging.push_front(chunk)
		if batch_remaining == 0:
			_commit_batch()

func _fail(text: String) -> void:
	_retire_contact()
	for key:Vector3i in staged_batch:
		if staged_batch[key].get("local_active",false):
			_set_edit_replacement(key,staged_batch[key],false)
			staged_batch[key].erase("local_active")
	_edit_support_snapshots.clear();_edit_support_result.clear()
	latest_error = text
	world_ready = false
	_cancel_density_requests("cancelled")
	push_error(text)
	message_changed.emit("ERROR: " + text)

func _begin_entry(data: Dictionary) -> Dictionary:
	if data.has("bricks"):
		var parent:=Node3D.new()
		parent.visible=false
		var section:Dictionary={"node":parent,"body":null,"triangle_pages":data.get("triangle_pages",false),"bricks":{},"brick_partial":data.get("brick_partial",false),"dirty":false,"stamp":data.stamp,"step":data.get("step",1),"triangles":data.triangles,"bytes":data.bytes,"used":Time.get_ticks_msec(),"key":data.key,"active":false,"cavity_visibility":true}
		if data.has("rims"):section.rims=data.rims
		elif data.get("triangle_pages",false):
			section.rim_geometry=[data.arrays[Mesh.ARRAY_VERTEX],data.arrays[Mesh.ARRAY_INDEX]]
		return section
	var upload_begin: int = Time.get_ticks_usec()
	var key: Vector3i = data["key"]
	var arrays: Array = data["arrays"]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# Keep the registered owner across topology changes. Slots beyond the
	# committed shape count are empty and can serve the next edit.
	var slot:Dictionary={}
	var old:Dictionary=tiles.get(key,{})
	var page_update:bool=data.get("page_update",false)
	if page_update:old=old.get("bricks",{}).get(data.brick_bottom,{})
	if (data.get("kind","")=="batch" or page_update) and not data.has("contact_count") and (not data.has("brick_bottom") or page_update):
		var previous_body:StaticBody3D=old.get("body")
		if old.get("node") is MeshInstance3D and is_instance_valid(previous_body):
			var colliders:=previous_body.get_children()
			var old_shapes:Array[Shape3D]=[]
			for child:Node in colliders:
				if not child is CollisionShape3D:break
				old_shapes.append((child as CollisionShape3D).shape)
			if old_shapes.size()==colliders.size():
				slot={"colliders":colliders,"old_shapes":old_shapes,"shapes":[],"mesh":null,"old_mesh":old.node.mesh,"applied":false}
	var mesh_node:Node3D
	var body:StaticBody3D
	if slot.is_empty():
		mesh_node=Node3D.new() if indices.is_empty() else MeshInstance3D.new()
		mesh_node.name="Patch_%d_%d_%d" % [key.x,key.y,key.z]
		mesh_node.visible=false
	else:
		mesh_node=old.node
		body=old.body
	var layout: Dictionary = {}
	if not indices.is_empty():
		# Empty owners retain their logical identity without a rendering instance.
		# Two-sided shadows preserve thin roofs.
		mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		var mesh := ArrayMesh.new()
		if data.has("render_surface"):
			mesh.set("_surfaces",[data.render_surface])
			if mesh.get_surface_count()==1:last_worker_packed_surfaces+=1
		if mesh.get_surface_count()==0:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		mesh.surface_set_material(0, material)
		if slot.is_empty():mesh_node.mesh=mesh
		else:slot.mesh=mesh
		var count: int = mesh.surface_get_array_len(0)
		var format: int = mesh.surface_get_format(0)
		layout = {"count": count, "stride": RenderingServer.mesh_surface_get_format_attribute_stride(format, count),
			"uv": RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_TEX_UV),
			"uv2": RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_TEX_UV2),
			"color": RenderingServer.mesh_surface_get_format_offset(format, count, Mesh.ARRAY_COLOR),
			"compressed": (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) != 0}
		if slot.is_empty() and not data["collision_pieces"].is_empty():
			body = StaticBody3D.new()
			body.name = "MatchingCollision"
			body.collision_layer = 0
			body.collision_mask = 0
			body.set_meta("terrain_patch", key)
			mesh_node.add_child(body)
	last_mesh_upload_ms = float(Time.get_ticks_usec() - upload_begin) / 1000.0
	_record_stage("mesh upload/create", last_mesh_upload_ms)
	var result:Dictionary={"node": mesh_node, "body": body, "dirty": false, "stamp": data["stamp"],
		"step": int(data.get("step",maxi(1,key.z/32))),
		"arrays": arrays, "attribute_layout": layout, "collision_shapes": {}, "lighting_only": bool(data.get("lighting_only", false)),
		"triangles": int(data["triangles"]), "bytes": int(data["bytes"]),
		"used": Time.get_ticks_msec(), "key": key, "active": false, "cavity_visibility": bool(data.get("cavity_visibility", true))}

	if data.has("compared_stamp") and old.get("stamp",-1)==data.compared_stamp and old.get("node")==mesh_node:
		result.rims=data.rims
	if not slot.is_empty():result.resident_swap=slot
	return result

func _apply_resident_swap(entry:Dictionary,active:bool)->void:
	var slot:Dictionary=entry.resident_swap
	if slot.applied==active:return
	var started:=Time.get_ticks_usec()
	var shapes:Array=slot.shapes if active else slot.old_shapes
	while slot.colliders.size()<shapes.size():
		var collider:=CollisionShape3D.new()
		entry.body.add_child(collider)
		slot.colliders.append(collider)
	for index in slot.colliders.size():
		var collider:CollisionShape3D=slot.colliders[index]
		var next_shape:Shape3D=shapes[index] if index<shapes.size() else null
		if collider.shape!=next_shape:collider.shape=next_shape
	entry.node.mesh=slot.mesh if active else slot.old_mesh
	slot.applied=active
	_record_stage("resident resource swap",(Time.get_ticks_usec()-started)/1000.0)

func _prepare_piece() -> bool:
	if preparation.data.has("bricks"):
		var parent: Dictionary=preparation
		var parts: Array=parent.data.bricks
		var index: int=parent.get("brick_at",0)
		if index>=parts.size(): return true
		if not parent.has("brick_preparation"):
			var part: Dictionary=parts[index]
			part["stamp"]=parent.data.stamp
			part.page_update=parent.data.get("triangle_pages",false) and parent.data.get("brick_partial",false)
			parent["brick_preparation"]={"data":part,"entry":_begin_entry(part),"piece_at":0}
			var attach_begin:=Time.get_ticks_usec()
			if parent.brick_preparation.entry.has("resident_swap"):return false
			parent.entry.node.add_child(parent.brick_preparation.entry.node)
			_record_stage("prepared subtree attach",(Time.get_ticks_usec()-attach_begin)/1000.0)
			# The hidden parent gates the whole region. Keep child visibility local
			# to the mesh so LOD switches need only one inherited visibility change.
			parent.brick_preparation.entry.node.visible=true
			return false
		preparation=parent.brick_preparation
		var finished:=_prepare_piece()
		preparation=parent
		if finished:
			var child: Dictionary=parent.brick_preparation.entry
			if parts[index].has("region_bounds"): child["region_bounds"]=parts[index].region_bounds
			parent.entry.bricks[parts[index].brick_bottom]=child
			parent.erase("brick_preparation")
			parent["brick_at"]=index+1
		return int(parent.get("brick_at",0))>=parts.size()
	var piece_begin: int = Time.get_ticks_usec()
	var data: Dictionary = preparation["data"]
	var pieces: Array = data["collision_pieces"]
	var at: int = preparation["piece_at"]
	if at < pieces.size():
		var entry: Dictionary = preparation["entry"]
		var old_entry: Dictionary = tiles.get(data["key"], {})
		if data.has("brick_bottom"): old_entry=old_entry.get("bricks",{}).get(data.brick_bottom,{})
		var previous: Dictionary = old_entry.get("collision_shapes", {})
		var current: Dictionary = entry["collision_shapes"]
		var prepared: Dictionary = pieces[at].resolve(previous)
		last_collision_match_ms = prepared.match_ms
		current[prepared.token] = prepared.shape
		_record_stage("collision exact match", prepared.match_ms)
		_record_stage("collision physics cook", prepared.cook_ms)
		if bool(prepared["reused"]):
			collision_pieces_reused += 1
		else:
			collision_pieces_built += 1
		var attach_begin: int = Time.get_ticks_usec()
		if entry.has("resident_swap"):
			entry.resident_swap.shapes.append(prepared.shape)
		else:
			var collision:=CollisionShape3D.new()
			collision.shape=prepared.shape
			var body:StaticBody3D=entry.body
			body.add_child(collision)
		_record_stage("collision node attach", float(Time.get_ticks_usec() - attach_begin) / 1000.0)
		preparation["piece_at"] = at + 1
		if profile_collision_pieces:
			collision_piece_measured.emit({"tile":[data.key.x,data.key.y,data.key.z],"piece":at,"pieces":pieces.size(),"match_ms":prepared.match_ms,"cook_ms":prepared.cook_ms,"reused":prepared.reused,"piece_ms":float(Time.get_ticks_usec()-piece_begin)/1000.0},pieces[at].get_faces())
	last_collision_piece_ms = float(Time.get_ticks_usec() - piece_begin) / 1000.0
	_record_stage("collision piece", last_collision_piece_ms)
	return int(preparation["piece_at"]) >= pieces.size()

func _has_paused_preparation(key: Vector3i) -> bool:
	for paused: Dictionary in paused_preparations:
		if paused.data.key==key: return true
	return false

func _urgent_staging_index() -> int:
	for i in range(staging.size()):
		if staging[i].get("kind","")=="mesh" and activation_keys.has(staging[i].key): return i
	return -1

func _select_preparation_work() -> void:
	# Preserve partially uploaded resources; priority changes must not restart
	# them. Cap suspended background containers while retaining an edit slot.
	var urgent:=_urgent_staging_index() if not pending_edit else -1
	if not preparation.is_empty() and preparation.data.get("kind","")=="mesh":
		if pending_edit or (urgent>=0 and not activation_keys.has(preparation.data.key) and paused_preparations.size()<4):
			paused_preparations.append(preparation)
			preparation={}
	if not preparation.is_empty() or pending_edit: return
	for i in range(paused_preparations.size()):
		if activation_keys.has(paused_preparations[i].data.key):
			preparation=paused_preparations[i]
			paused_preparations.remove_at(i)
			return
	if urgent>=0:
		if urgent>0:
			var data: Dictionary=staging[urgent]
			staging.remove_at(urgent)
			staging.push_front(data)
	elif not paused_preparations.is_empty():
		preparation=paused_preparations.pop_front()

func _drain_staging(allowance_us:int=-1) -> void:
	if allowance_us<0:allowance_us=main_build_budget_us
	var begin: int = Time.get_ticks_usec()
	# A multi-region background upload must yield between bounded pieces rather
	# than keep a ready edit waiting for the entire coarse container.
	_select_preparation_work()
	if not partition_request.is_empty() and not _partition_valid(): _cancel_partition()
	if not lighting_upload.is_empty() and not pending_edit and _urgent_staging_index()<0 and (preparation.is_empty() or not activation_keys.has(preparation.data.key)):
		_apply_lighting_piece()
		if not lighting_upload.is_empty():
			last_publish_frame_ms = float(Time.get_ticks_usec() - begin) / 1000.0
			return
	while Time.get_ticks_usec() - begin < allowance_us:
		var unit_begin: int = Time.get_ticks_usec()
		# Atomic publication is its own indivisible unit. A final collision piece
		# may already have exhausted this slice; keep the old complete surface
		# until the next available slice rather than stacking the swap on top.
		if pending_edit and edit_worker_done and batch_remaining==0:
			if not latest_error.is_empty() or joint_edit_pending():break
			_commit_batch()
			last_publish_ms=last_commit_ms
			continue
		if pending_edit and batch_remaining==0 and not staged_batch.is_empty() and latest_error.is_empty():
			if joint_edit_pending():break
			_install_edit_geometry()
			continue
		_select_preparation_work()
		if preparation.is_empty():
			if staging.is_empty():
				break
			if pending_edit and str(staging.front().get("kind",""))!="batch": break
			var data: Dictionary = staging.pop_front()
			var key: Vector3i = data["key"]
			if str(data.get("kind", "")) == "mesh" and staging_versions.get(key) == Vector2i(int(data["epoch"]), int(data["stamp"])):
				staging_versions.erase(key)
			if not _staging_valid(data):
				_forget_light_job(data)
				continue
			if str(data.get("kind", "")) == "relight" and pending_edit:
				staging.push_back(data)
				break
			if str(data.get("kind", "")) == "relight":
				lighting_upload = {"data": data, "offset": 0}
				_apply_lighting_piece()
				break
			preparation = {"data": data, "entry": _begin_entry(data), "piece_at": 0}
			var attach_begin:=Time.get_ticks_usec()
			if not preparation.entry.has("resident_swap"):add_child(preparation.entry.node)
			_record_stage("prepared subtree attach",(Time.get_ticks_usec()-attach_begin)/1000.0)
		else:
			var data: Dictionary = preparation["data"]
			var key: Vector3i = data["key"]
			if not _staging_valid(data):
				_forget_light_job(data)
				_destroy_entry(preparation["entry"])
				preparation.clear()
				continue
			if _prepare_piece():
				var entry: Dictionary = preparation["entry"]
				preparation.clear()
				last_mesh_ms = float(data["worker_ms"])
				worker_builds += 1
				if str(data["kind"]) == "partition_child":
					partition_request.entries[key]=entry
					if partition_request.entries.size()==4: _commit_partition()
				elif str(data["kind"]) == "batch":
					if int(data["ticket"]) != edit_ticket:
						_destroy_entry(entry)
						continue
					if data.has("contact_count"):
						_stage_contact(key,entry,data)
						continue
					staged_batch[key] = entry
					batch_remaining -= 1
					_publish_ready_region(key)
				else:
					_install(key, entry)
					if str(data.get("kind", "")) == "relight":
						lighting_dirty.erase(key)
						lighting_in_flight.erase(key)
		last_publish_ms = float(Time.get_ticks_usec() - unit_begin) / 1000.0
	last_publish_frame_ms = float(Time.get_ticks_usec() - begin) / 1000.0

func _apply_lighting_piece() -> void:
	if lighting_upload.is_empty():
		return
	var data: Dictionary = lighting_upload["data"]
	var key: Vector3i = data["key"]
	if not _staging_valid(data) or not tiles.has(key) or pending_edit:
		if not pending_edit:
			_forget_light_job(data)
			lighting_upload.clear()
		return
	var entry: Dictionary = tiles[key]
	if data.has("brick_bottom"): entry=entry.bricks[data.brick_bottom]
	var node: Node3D = entry["node"]
	var mesh: ArrayMesh = node.mesh as ArrayMesh if node is MeshInstance3D else null
	var layout: Dictionary = entry.get("attribute_layout", {})
	var bytes: PackedByteArray = data["attribute_data"]
	if mesh == null or mesh.get_surface_count() == 0 or layout.is_empty():
		_forget_light_job(data)
		if data.has("brick_bottom"): entry["light_generation"]=data.light_ticket
		else: lighting_dirty.erase(key)
		lighting_upload.clear()
		return
	var stride: int = int(layout["stride"])
	if bytes.size() != int(layout["count"]) * stride:
		_fail("Lighting attribute length mismatch; no GPU write performed")
		lighting_upload.clear()
		return
	var offset: int = int(lighting_upload["offset"])
	var amount: int = mini(bytes.size() - offset, maxi(stride, (LIGHT_UPLOAD_BYTES / stride) * stride))
	var begin: int = Time.get_ticks_usec()
	if amount > 0:
		mesh.surface_update_attribute_region(0, offset, bytes.slice(offset, offset + amount))
	lighting_attribute_updates += 1
	last_light_upload_ms = float(Time.get_ticks_usec() - begin) / 1000.0
	_record_stage("lighting attribute upload", last_light_upload_ms)
	offset += amount
	lighting_upload["offset"] = offset
	if offset >= bytes.size():
		entry["arrays"] = data["arrays"]
		entry["cavity_visibility"] = data["cavity_visibility"]
		if data.has("brick_bottom"): entry["light_generation"]=data.light_ticket
		else: lighting_dirty.erase(key)
		_forget_light_job(data)
		lighting_upload.clear()

func _forget_light_job(data: Dictionary) -> void:
	if str(data.get("kind", "")) == "relight" and int(lighting_in_flight.get(data["key"], -1)) == int(data["light_ticket"]):
		lighting_in_flight.erase(data["key"])

func _staging_valid(data: Dictionary) -> bool:
	if data.has("contact_count") and (not pending_edit or int(data.ticket)!=edit_ticket):return false
	var key: Vector3i = data["key"]
	if int(data["epoch"]) != epoch or int(data["stamp"]) != int(stamps.get(key, 0)):
		return false
	if str(data.get("kind",""))=="partition_child":
		return _partition_valid() and int(data.token)==int(partition_request.token)
	if str(data.get("kind", "")) == "relight":
		return int(data["light_ticket"]) == int(lighting_dirty.get(key, -1))
	return true

func _detach_retired_collision(entry: Dictionary) -> void:
	if entry.has("resident_swap"):return
	# Layer zero alone still rebuilds Jolt compounds when shapes are freed.
	# Only retiring entries leave physics; cached LOD entries stay registered.
	if entry.has("bricks"):
		for child: Dictionary in entry.bricks.values(): _detach_retired_collision(child)
	var body: StaticBody3D = entry.get("body")
	if is_instance_valid(body):
		body.collision_layer = 0
		body.process_mode = Node.PROCESS_MODE_DISABLED

func _destroy_entry(entry: Dictionary) -> void:
	if entry.has("resident_swap"):return # Its nodes belong to the installed tile.
	_detach_retired_collision(entry)
	var node: Node3D = entry.get("node")
	if is_instance_valid(node):
		node.visible = false
		retired_nodes.push_back(node)

func _set_active(entry: Dictionary, active: bool, inherited_visibility: bool=false) -> void:
	if (inherited_visibility and entry.has("resident_swap")) or bool(entry.get("active",false))==active:
		return
	entry["active"] = active
	if entry.has("bricks"):
		for child: Dictionary in entry.bricks.values(): _set_active(child,active,true)
	var node: Node3D = entry["node"]
	if not inherited_visibility: node.visible = active
	var body: StaticBody3D = entry["body"]
	if is_instance_valid(body):
		body.collision_layer = 1 if active else 0
	if active:
		entry["used"] = Time.get_ticks_msec()

func _install(key: Vector3i, entry: Dictionary) -> void:
	if tiles.has(key):
		var old: Dictionary = tiles[key]
		cache_bytes -= int(old.bytes)
		if entry.has("resident_swap"):
			_apply_resident_swap(entry,true)
			entry.active=old.active
			retired_payloads.append(entry.resident_swap)
			entry.erase("resident_swap")
		elif entry.get("brick_partial",false) and old.has("bricks"):
			# Keep the live container when only a minority of its bricks changed.
			# Reparenting an untouched StaticBody leaves and rejoins the physics
			# space even when the collision layer and mesh revision stay the same.
			if entry.get("triangle_pages",false) or entry.bricks.size()*2 < old.bricks.size():
				for bottom: int in entry.bricks:
					var replacement: Dictionary = entry.bricks[bottom]
					if replacement.has("resident_swap"):
						old.bytes-=old.bricks[bottom].bytes
						old.triangles-=old.bricks[bottom].triangles
						_apply_resident_swap(replacement,true)
						replacement.active=old.active
						retired_payloads.append(replacement.resident_swap)
						replacement.erase("resident_swap")
						old.bricks[bottom]=replacement
						continue
					if old.bricks.has(bottom):
						var replaced: Dictionary = old.bricks[bottom]
						old.bytes -= int(replaced.bytes)
						old.triangles -= int(replaced.triangles)
						_destroy_entry(replaced)
					replacement.node.reparent(old.node,false)
					old.bricks[bottom] = replacement
					_set_active(replacement,bool(old.active),true)
				old.bytes += int(entry.bytes)
				old.triangles += int(entry.triangles)
				if entry.has("rim_geometry"):old.rim_geometry=entry.rim_geometry
				elif entry.get("triangle_pages",false):old.erase("rim_geometry")
				old.stamp = entry.stamp
				old.used = entry.used
				old.dirty = false
				entry.bricks.clear()
				_destroy_entry(entry)
				entry = old
			else:
				for bottom: int in old.bricks.keys():
					if entry.bricks.has(bottom): continue
					var retained: Dictionary=old.bricks[bottom]
					retained.node.reparent(entry.node)
					entry.bricks[bottom]=retained
					entry.bytes+=int(retained.bytes)
					entry.triangles+=int(retained.triangles)
					old.bricks.erase(bottom)
				_destroy_entry(old)
		else:
			_destroy_entry(old)
	tiles[key] = entry
	_cut_dirty = _cut_dirty or visible_cut.has(key)
	cache_bytes += int(entry["bytes"])
	_set_active(entry, visible_cut.has(key))
	if activation_keys.has(key): schedule_timer=0.0

func _contact_domain(commands:Array)->Dictionary:
	if commands.size()!=1:return {}
	var packet:PackedByteArray=commands[0]
	if packet.size()!=44 or packet.decode_u32(0)!=2 or packet.decode_u32(36)!=0 or packet.decode_u32(32)>1 or packet.decode_float(28)<12:return {}
	var center:=Vector3(packet.decode_float(4),packet.decode_float(8),packet.decode_float(12))
	if center!=Vector3(packet.decode_float(16),packet.decode_float(20),packet.decode_float(24)):return {}
	# Cover the target and a full SDF band on all sides with resident fine tiles.
	var corner:=Vector2i(floori((center.x-8)/16)*16,floori((center.z-8)/16)*16)
	var end:=Vector2i(ceili((center.x+8)/16)*16,ceili((center.z+8)/16)*16)
	var bounds:=Rect2i(corner,end-corner)
	var keys:Array[Vector3i]=[]
	for z in range(corner.y,end.y,16):
		for x in range(corner.x,end.x,16):
			var key:Vector3i=_edit_owner_cells.get(Vector2i(x,z),Vector3i.ZERO)
			if key.z==0 or (not tiles[key].has("arrays") and not tiles[key].get("triangle_pages",false)) or tiles[key].step!=1:return {}
			if not keys.has(key):
				keys.append(key)
				bounds=bounds.merge(Rect2i(key.x,key.y,key.z,key.z))
	var covered:=0
	for key in keys:covered+=key.z*key.z
	if covered!=bounds.get_area() or keys.size()>4:return {}
	return {"keys":keys,"bounds":bounds}

func _retire_contact()->void:
	for key:Vector3i in _contact_entries:
		_destroy_entry(_contact_entries[key])
		if _contact_visible and tiles.has(key):_set_active(tiles[key],true)
	_contact_entries.clear()
	_contact_visible=false
	_contact_checked=false

func _stage_contact(key:Vector3i,entry:Dictionary,data:Dictionary)->void:
	_contact_entries[key]=entry
	if _contact_entries.size()!=int(data.contact_count):return
	var bounds:Rect2i=data.contact_bounds
	for id:Vector3i in _contact_entries:
		var outer:=0
		if id.x==bounds.position.x:outer|=1
		if id.x+id.z==bounds.end.x:outer|=2
		if id.y==bounds.position.y:outer|=4
		if id.y+id.z==bounds.end.y:outer|=8
		var rim:=_rim_geometry(tiles[id])
		if rim.is_empty():
			_retire_contact()
			return
		var replacement:Array=_contact_entries[id].arrays
		if not backend.collision_recipes.matching_cut_boundary(id,outer,rim[0],rim[1],replacement[Mesh.ARRAY_VERTEX],replacement[Mesh.ARRAY_INDEX]):
			_record_stage("resident cut boundary mismatch",0)
			_retire_contact()
			return
	_contact_checked=true
	_activate_contact()

func _activate_contact()->void:
	if joint_edit_pending() or not _contact_checked or _contact_visible or _contact_accepted_ticket!=edit_ticket:return
	# An exact owner can arrive ahead of its temporary contact surface.
	# Never let a late preview cover a replacement that is already live.
	for id:Vector3i in _contact_entries:
		if staged_batch.get(id,{}).get("local_active",false):
			_retire_contact()
			return
	for id:Vector3i in _contact_entries:
		_set_active(tiles[id],false)
		_set_active(_contact_entries[id],true)
	_contact_visible=true
	_wake_edited_contacts(_contact_entries.keys())
	edit_region_installed.emit(edit_ticket,_contact_entries.keys())

# A replaced concave shape updates ray queries immediately. Jolt can still
# retain a sleeping rigid body's old support until explicitly awakened.
# Layers 1 and 2 hold static terrain and structures. Gameplay rigid bodies
# use vehicle, ragdoll, debris or pickup layers. Custom worlds may opt in more.
@export_flags_3d_physics var edit_wake_layers:int=0xfffffffc

func _wake_edited_contacts(keys:Array)->void:
	if keys.is_empty():return
	var space:=get_world_3d().direct_space_state
	var shape:=BoxShape3D.new()
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape
	query.collision_mask=edit_wake_layers
	for brush in edit_geometry_bounds:
		var region:=AABB()
		for key:Vector3i in keys:
			var tile:=AABB(Vector3(key.x,brush.position.y,key.y),Vector3(key.z,brush.size.y,key.z))
			var part:=brush.intersection(tile)
			if part.has_volume():region=part if not region.has_volume() else region.merge(part)
		if not region.has_volume():continue
		shape.size=region.size
		query.transform=Transform3D(Basis.IDENTITY,region.get_center())
		var excluded:Array[RID]=[]
		while true:
			query.exclude=excluded
			var hits:=space.intersect_shape(query,64)
			for hit in hits:
				var rid:RID=hit.rid
				if rid in excluded:continue
				excluded.append(rid)
				if PhysicsServer3D.body_get_mode(rid)>=PhysicsServer3D.BODY_MODE_RIGID and PhysicsServer3D.body_get_state(rid,PhysicsServer3D.BODY_STATE_SLEEPING):
					PhysicsServer3D.body_set_state(rid,PhysicsServer3D.BODY_STATE_SLEEPING,false)
			if hits.size()<64:break

func _set_edit_replacement(key:Vector3i, replacement:Dictionary, active:bool)->void:
	var original:Dictionary=tiles[key]
	if replacement.has("resident_swap"):
		_apply_resident_swap(replacement,active)
		return
	if replacement.get("brick_partial",false) and original.has("bricks"):
		# Original and replacement parents coexist until commit. Only the
		# children actually replaced relinquish their visual and physics space.
		for id:int in replacement.bricks:
			if replacement.bricks[id].has("resident_swap"):
				_apply_resident_swap(replacement.bricks[id],active)
			elif original.bricks.has(id):_set_active(original.bricks[id],not active)
	else:
		_set_active(original,not active)
	_set_active(replacement,active)

func _rim_geometry(entry:Dictionary)->Array:
	if entry.has("rim_geometry"):return entry.rim_geometry
	if entry.has("arrays"):return [entry.arrays[Mesh.ARRAY_VERTEX],entry.arrays[Mesh.ARRAY_INDEX]]
	if entry.get("triangle_pages",false):
		var pages:Array=[]
		for id in (entry.key.z/8)*(entry.key.z/8):
			if not entry.bricks.has(id):return []
			pages.append(entry.bricks[id].arrays)
		entry.rim_geometry=backend.collision_recipes.triangle_page_rim(entry.key,pages)
		return entry.rim_geometry
	return []

func _ready_edit_group(seed:Vector3i)->Array[Vector3i]:
	if not _edit_visible_owners.has(seed):return []
	var group:Array[Vector3i]=[seed]
	var visited:Dictionary={seed:true}
	var at:=0
	while at<group.size():
		var key:=group[at]
		at+=1
		if _contact_visible and _contact_entries.has(key):
			# The preview spans a single seam-checked region. Replace its
			# owners together as soon as their exact neighbours are ready.
			for preview_key:Vector3i in _contact_entries:
				if not visited.has(preview_key):
					visited[preview_key]=true
					group.append(preview_key)
		var entry:Dictionary=staged_batch.get(key,{})
		if entry.is_empty():return []
		if entry.get("local_active",false) or entry.get("retain_geometry",false):continue
		var old:Dictionary=tiles[key]
		if not entry.has("rims"):
			entry.rims=15
			if old.step==1 and entry.step==1:
				var before:=_rim_geometry(old)
				var after:=_rim_geometry(entry)
				if not before.is_empty() and not after.is_empty():
					entry.rims=backend.collision_recipes.changed_rims(key,before[0],before[1],after[0],after[1])
		var rims:int=entry.rims
		if rims==0:continue
		for z in range(key.y-16,key.y+key.z+16,16):
			for x in range(key.x-16,key.x+key.z+16,16):
				var sides:=0
				if x<key.x:sides|=1
				elif x>=key.x+key.z:sides|=2
				if z<key.y:sides|=4
				elif z>=key.y+key.z:sides|=8
				if sides==0 or (rims&sides)!=sides:continue
				var cell:=Vector2i(x,z)
				if not _edit_owner_cells.has(cell):continue
				var neighbor:Vector3i=_edit_owner_cells[cell]
				if visited.has(neighbor):continue
				if not staged_batch.has(neighbor):return []
				visited[neighbor]=true
				group.append(neighbor)
	return group

func _publish_ready_region(seed:Vector3i)->void:
	var group:=_ready_edit_group(seed)
	if joint_edit_pending():
		for key:Vector3i in group:
			if _joint_owners.has(key):return
	_install_ready_edit_group(group)

func _install_ready_edit_group(group:Array)->void:
	if _contact_visible:
		for key:Vector3i in group:
			if _contact_entries.has(key):
				_retire_contact()
				break
	var installed:Array[Vector3i]=[]
	for key in group:
		var entry:Dictionary=staged_batch[key]
		if entry.get("local_active",false) or entry.get("retain_geometry",false):continue
		_set_edit_replacement(key,entry,true)
		entry.local_active=true
		installed.append(key)
	if not installed.is_empty():
		_wake_edited_contacts(installed)
		edit_region_installed.emit(edit_ticket,installed)

func edit_geometry_ready_in(bounds:AABB)->bool:
	if not pending_edit or _edit_visible_owners.is_empty():return false
	var area:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
	var matched:=false
	for key:Vector3i in _edit_visible_owners:
		if not area.intersects(Rect2(key.x,key.y,key.z,key.z),true):continue
		matched=true
		var staged:Dictionary=staged_batch.get(key,{})
		if not staged.get("local_active",false) and not staged.get("retain_geometry",false):return false
	return matched

func _install_edit_geometry()->void:
	_retire_contact()
	# Change every adjacent surface and its collider in the same main-thread
	# turn. Support sampling can finish independently on the terrain worker.
	_record_stage("geometry ready",0.0)
	var installed:Array[Vector3i]=[]
	for key: Vector3i in staged_batch:
		if staged_batch[key].get("retain_geometry",false):
			tiles[key].stamp=staged_batch[key].stamp
			tiles[key].dirty=false
		else:
			if not staged_batch[key].get("local_active",false):installed.append(key)
			_install(key, staged_batch[key])
	_wake_edited_contacts(installed)
	staged_batch.clear()
	edit_geometry_installed.emit(edit_ticket)

func _commit_batch() -> void:
	if joint_edit_pending():return
	var commit_begin: int = Time.get_ticks_usec()
	if _edit_support_result.size()!=_edit_support_snapshots.size():
		backend.disable_snapshot_writes("terrain support results missing")
		_fail("Terrain vegetation support did not complete; previous save preserved")
		return
	for index in _edit_support_snapshots.size():
		var provider:Dictionary=_edit_support_snapshots[index]
		if not provider.apply.is_valid() or not provider.apply.call(provider.snapshot,_edit_support_result[index]):
			backend.disable_snapshot_writes("terrain support publication failed")
			_fail("Terrain vegetation publication failed; previous save preserved")
			return
	last_support_publish_ms=(Time.get_ticks_usec()-commit_begin)/1000.0
	_record_stage("vegetation edit publish",last_support_publish_ms)
	_edit_support_snapshots.clear();_edit_support_result.clear()
	if not staged_batch.is_empty():_install_edit_geometry()
	pending_edit = false
	resident_edit_surface={}
	last_geometry_done_us = Time.get_ticks_usec()
	_queue_lighting_refresh()
	changed_since_save = true
	last_latency_ms = float(Time.get_ticks_usec() - edit_started_us) / 1000.0
	last_prepare_latency_ms = float(Time.get_ticks_usec() - last_worker_finished_us) / 1000.0 if last_worker_finished_us > 0 else 0.0
	pending_draw_us = edit_started_us
	if last_latency_ms > 150.0:
		slow_edits.push_back({"latency_ms": last_latency_ms, "capture_wait_ms": last_capture_wait_ms,
			"worker_queue_ms": last_queue_ms, "edit_ms": last_edit_ms, "build_total_ms": last_total_build_ms,
			"stage_wait_ms": last_prepare_latency_ms, "geometry": last_density_tiles, "lighting": last_relight_tiles,
			"upload_ms": last_mesh_upload_ms, "collision_ms": last_collision_piece_ms,
			"position": [focus.x, focus.y, focus.z], "time_ms": Time.get_ticks_msec()})
		if slow_edits.size() > 128:
			slow_edits.pop_front()
	edit_rollback.clear()
	published_revision += 1
	if committed_measurements.size() >= 64:
		committed_measurements.pop_front()
	committed_measurements.push_back(_edit_measurement(true))
	edit_published.emit(last_latency_ms)
	schedule_timer = 0.0
	_update_cut()
	last_commit_ms = float(Time.get_ticks_usec() - commit_begin) / 1000.0
	_record_stage("atomic publish", last_commit_ms)

func _edit_measurement(changed: bool) -> Dictionary:
	return {"ticket": edit_ticket, "changed": changed, "captured_us": edit_started_us,
		"publish_us": Time.get_ticks_usec(), "capture_wait_ms": last_capture_wait_ms,
		"worker_queue_ms": last_queue_ms, "field_ms": last_edit_ms,
		"build_ms": last_total_build_ms, "after_worker_ms": last_prepare_latency_ms,
		"publish_ms": float(Time.get_ticks_usec() - edit_started_us) / 1000.0,
		"upload_last_piece_ms": last_mesh_upload_ms, "collision_last_piece_ms": last_collision_piece_ms,
		"geometry_patches": last_density_tiles,"untouched_surface_tiles":last_untouched_surface_tiles, "descriptor": latest_edit_descriptor.duplicate(),
		"accepted_us": edit_accepted_us, "members": latest_edit_members.duplicate(true),
		"member_changed": latest_member_changes.duplicate(),
		"collision_pieces_reused_total": collision_pieces_reused,
		"collision_pieces_built_total": collision_pieces_built,
		"collision_match_last_ms": last_collision_match_ms}

func _emit_member_measurements(record: Dictionary, draw_us: int) -> void:
	var members: Array = record.get("members", [])
	if members.is_empty():
		members = [{"captured_us": record["captured_us"], "descriptor": record["descriptor"]}]
	var changes: Array = record.get("member_changed", [])
	for index in range(members.size()):
		var member: Dictionary = members[index]
		var row: Dictionary = record.duplicate()
		row.erase("members")
		row.erase("member_changed")
		row["captured_us"] = int(member["captured_us"])
		row["descriptor"] = member["descriptor"]
		row["changed"] = bool(changes[index]) if index < changes.size() else bool(record["changed"])
		row["member_index"] = index
		row["group_size"] = members.size()
		row["costs_shared_by_group"] = members.size() > 1
		row["capture_wait_ms"] = float(int(record["accepted_us"]) - int(member["captured_us"])) / 1000.0
		row["publish_ms"] = float(int(record["publish_us"]) - int(member["captured_us"])) / 1000.0
		row["draw_ms"] = float(draw_us - int(member["captured_us"])) / 1000.0 if draw_us > 0 else null
		if draw_us > 0:
			row["draw_us"] = draw_us
		edit_measured.emit(row)

func _post_draw() -> void:
	for record: Dictionary in committed_measurements:
		_emit_member_measurements(record, Time.get_ticks_usec())
	committed_measurements.clear()
	if pending_draw_us > 0:
		last_draw_latency_ms = float(Time.get_ticks_usec() - pending_draw_us) / 1000.0
		pending_draw_us = 0

func _distance(key: Vector3i) -> float:
	var dx: float = maxf(maxf(float(key.x) - focus.x, focus.x - float(key.x + key.z)), 0.0)
	var dz: float = maxf(maxf(float(key.y) - focus.z, focus.z - float(key.y + key.z)), 0.0)
	var dy: float = maxf(0.0, focus.y - 256.0) if not require_collision else 0.0
	return sqrt(dx * dx + dz * dz + dy * dy)

func _tile_modified(key: Vector3i) -> bool:
	for z in range(maxi(0, (key.y - 2) / 16), mini(125, (key.y + key.z + 2) / 16) + 1):
		for x in range(maxi(0, (key.x - 2) / 16), mini(125, (key.x + key.z + 2) / 16) + 1):
			if modified_columns.has(Vector2i(x, z)):
				return true
	return false

func _tile_light_modified(key: Vector3i) -> bool:
	for z in range(maxi(0, (key.y - 2) / 16), mini(125, (key.y + key.z + 2) / 16) + 1):
		for x in range(maxi(0, (key.x - 2) / 16), mini(125, (key.x + key.z + 2) / 16) + 1):
			if shadow_columns.has(Vector2i(x, z)):
				return true
	return false

func _schedule_urgent_collision() -> void:
	# A long held stroke must not indefinitely stop coverage immediately ahead.
	# Include the coverage bridges required to expose local fine collision.
	# Arbitrary distant LOD/lighting work remains excluded.
	# Flying still permits mining and needs editable local terrain. Disabling
	# walking collision requirements must not disable held-brush loading.
	schedule_timer = 0.10
	var requests := _plan_requests()
	_cancel_unrequested_meshes()
	var available: int = maxi(0, 2 - backend.queued())
	for key: Vector3i in requests:
		var interactive: bool=key.z==16 and activation_keys.has(key)
		if available <= 0 and not interactive: continue
		if not activation_keys.has(key) and (key.z > 32 or _distance(key) > 24.0):
			continue
		var version := Vector2i(epoch, int(stamps.get(key, 0)))
		if not preparation.is_empty() and preparation["data"]["key"] == key:
			continue
		if _has_paused_preparation(key): continue
		if in_flight.get(key, Vector2i(-1, -1)) == version or staging_versions.get(key, Vector2i(-1, -1)) == version:
			continue
		if backend.submit({"kind": "mesh", "key": key, "stamp": version.y, "epoch": epoch,
			"base": not _tile_modified(key), "relight_cache": _tile_light_modified(key),"interaction_mesh":interactive}, true):
			in_flight[key] = version
			available -= 1
	_update_cut(_planned_coverage)

var _planned_coverage:Dictionary={}
var _planned_eviction:Dictionary={}
var render_view := Vector3.INF
var render_projection_scale := 1.0
func _plan_requests() -> Array[Vector3i]:
	_planned_coverage={}
	_planned_eviction={}
	var target:Vector3=interaction_target if Time.get_ticks_usec()<interaction_target_until_us else Vector3.INF
	var velocity:=travel_velocity
	if navigation_interest.is_empty() and (target.is_finite() or not velocity.is_finite() or velocity.length_squared()<=0.01):velocity=Vector3.ZERO
	var over_budget:=tiles.size()>cache_entry_limit or cache_bytes>cache_byte_limit
	var plan:Dictionary=planner.requests_navigation(focus,require_collision,velocity,target,navigation_interest,tiles,split_state,visible_cut,true,over_budget,render_view,render_projection_scale,service_navigation)
	if not plan.ok:
		_fail("Native terrain scheduling rejected invalid state")
		return []
	requested_keys = plan.requested_keys
	activation_keys = plan.activation_keys
	split_state = plan.split_state
	_planned_coverage=plan.coverage
	_planned_eviction=plan.get("eviction",{})
	return plan.requests

var navigation_interest:=PackedVector3Array()
var service_navigation:=false
func set_navigation_interest(points:PackedVector3Array,service:bool=false)->void:
	if points.size()<=8:navigation_interest=points;service_navigation=service

func _cancel_unrequested_meshes() -> void:
	for cancelled: Dictionary in backend.cancel_stale_meshes(requested_keys, epoch, stamps):
		var key: Vector3i = cancelled["key"]
		if in_flight.get(key) == Vector2i(int(cancelled["epoch"]), int(cancelled["stamp"])):
			in_flight.erase(key)

func _schedule() -> Dictionary:
	var requests := _plan_requests()
	_cancel_unrequested_meshes()
	# No walking-path backlog: the active worker plus at most four waiting builds.
	var available: int = maxi(0, 4 - backend.queued())
	for key: Vector3i in requests:
		if available <= 0:
			break
		var version := Vector2i(epoch, int(stamps.get(key, 0)))
		if not preparation.is_empty() and preparation["data"]["key"] == key:
			continue
		if _has_paused_preparation(key): continue
		if in_flight.get(key, Vector2i(-1, -1)) == version or staging_versions.get(key, Vector2i(-1, -1)) == version:
			continue
		var accepted: bool = backend.submit({"kind": "mesh", "key": key,
			"stamp": version.y, "epoch": epoch, "base": not _tile_modified(key), "relight_cache": _tile_light_modified(key)})
		if accepted:
			in_flight[key] = version
			available -= 1
	return _planned_coverage

func request_partition(key: Vector3i) -> bool:
	if stopping or not world_ready or pending_edit or not partition_request.is_empty() or key.z<=16 or not visible_cut.has(key) or not tiles.has(key): return false
	var parent: Dictionary=tiles[key]
	if parent.has("bricks"): return false
	if bool(parent.dirty) or int(parent.stamp)!=int(stamps.get(key,0)) or in_flight.has(key) or staging_versions.has(key): return false
	var half:=key.z/2
	var children: Dictionary={}
	for offset: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
		var child:=Vector3i(key.x+offset.x*half,key.y+offset.y*half,half)
		if tiles.has(child) or in_flight.has(child) or staging_versions.has(child): return false
		children[child]=int(stamps.get(child,0))
	var source:=parent.duplicate()
	source["faces"]=PackedVector3Array()
	var packet:=Codec.encode_decoded_mesh(source)
	_partition_serial+=1
	if not backend.submit({"kind":"partition","packet":packet,"token":_partition_serial,"epoch":epoch,"stamp":int(stamps.get(key,0))}): return false
	partition_request={"key":key,"parent":parent,"stamp":int(stamps.get(key,0)),"epoch":epoch,"ticket":edit_ticket,"token":_partition_serial,"children":children,"entries":{}}
	for child: Vector3i in children: in_flight[child]=Vector2i(epoch,children[child])
	return true

func _partition_valid() -> bool:
	if partition_request.is_empty() or stopping or not world_ready or pending_edit: return false
	var request:=partition_request
	if request.epoch!=epoch or request.ticket!=edit_ticket or not visible_cut.has(request.key) or not tiles.has(request.key): return false
	if tiles[request.key]!=request.parent or tiles[request.key].dirty or int(stamps.get(request.key,0))!=request.stamp: return false
	for child: Vector3i in request.children:
		if tiles.has(child) or int(stamps.get(child,0))!=request.children[child]: return false
	return true

func _cancel_partition() -> void:
	if partition_request.is_empty(): return
	var request:=partition_request
	partition_request={}
	for child: Vector3i in request.children:
		if in_flight.get(child)==Vector2i(request.epoch,request.children[child]): in_flight.erase(child)
	for entry: Dictionary in request.entries.values(): _destroy_entry(entry)
	staging=staging.filter(func(data: Dictionary): return data.get("kind","")!="partition_child" or data.get("token")!=request.token)
	if not preparation.is_empty() and preparation.data.get("kind","")=="partition_child" and preparation.data.get("token")==request.token:
		_destroy_entry(preparation.entry)
		preparation.clear()

func _receive_partition(result: Dictionary) -> void:
	if partition_request.is_empty() or result.get("token")!=partition_request.token: return
	if partition_request.get("received",false): return
	if not _partition_valid() or result.get("epoch")!=epoch or result.get("stamp")!=partition_request.stamp or result.get("cancelled",false) or result.get("chunks",[]).size()!=4:
		_cancel_partition();return
	var received: Dictionary={}
	var added_bytes: int=0
	for data: Dictionary in result.chunks:
		if not partition_request.children.has(data.key) or received.has(data.key): _cancel_partition();return
		received[data.key]=true
		added_bytes+=int(data.bytes)
	if tiles.size()+4>cache_entry_limit or cache_bytes+added_bytes>cache_byte_limit: _cancel_partition();return
	partition_request["received"]=true
	for data: Dictionary in result.chunks:
		data.merge({"kind":"partition_child","token":partition_request.token,"epoch":epoch,"stamp":partition_request.children[data.key]},true)
		staging.append(data)

func _commit_partition() -> void:
	if not _partition_valid(): _cancel_partition();return
	var request:=partition_request
	var added_bytes: int=0
	for entry: Dictionary in request.entries.values(): added_bytes+=int(entry.bytes)
	if tiles.size()+4>cache_entry_limit or cache_bytes+added_bytes>cache_byte_limit: _cancel_partition();return
	partition_request={}
	for key: Vector3i in request.entries:
		in_flight.erase(key)
		_install(key,request.entries[key])
	split_state[request.key]=true
	_update_cut()

func _update_cut(covered:Dictionary={}) -> void:
	if pending_edit:
		return
	if covered.is_empty():covered=planner.coverage_available(tiles,split_state,visible_cut)
	if not covered.ok:
		_fail("Native terrain coverage rejected invalid state")
		return
	var next: Array[Vector3i] = covered["keys"]
	root_coverage = covered.root_coverage
	covered_roots = covered.covered_roots
	if not _cut_dirty and next == visible_cut:
		return
	for key: Vector3i in covered.hidden:
		if tiles.has(key):
			_set_active(tiles[key], false)
	active_leaves.clear()
	total_triangles = 0
	for key: Vector3i in next:
		_set_active(tiles[key], true)
		total_triangles += int(tiles[key]["triangles"])
		# A completed EMPTY fine patch has valid empty collision, not missing data.
		var expected_parts:int=(key.z/8)*(key.z/8) if tiles[key].get("triangle_pages",false) else 8
		if key.z <= 32 and int(tiles[key].get("step",1))==1 and (is_instance_valid(tiles[key]["body"]) or tiles[key].get("bricks",{}).size()==expected_parts or int(tiles[key]["triangles"]) == 0):
			for z in range(key.y / FINE_SIZE, (key.y + key.z) / FINE_SIZE):
				for x in range(key.x / FINE_SIZE, (key.x + key.z) / FINE_SIZE):
					active_leaves[Vector2i(x, z)] = true
	visible_cut = next
	_cut_dirty = false

func _evict(eviction:Dictionary={}) -> void:
	if tiles.size() <= cache_entry_limit and cache_bytes <= cache_byte_limit:
		return
	if eviction.is_empty():eviction=planner.eviction_candidates(tiles,visible_cut,requested_keys)
	if not eviction.ok:
		_fail("Native terrain eviction rejected invalid state")
		return
	var victims: Array[Vector3i] = eviction["keys"]
	for key: Vector3i in victims:
		if tiles.size() <= cache_entry_limit and cache_bytes <= cache_byte_limit:
			break
		cache_bytes -= int(tiles[key]["bytes"])
		_destroy_entry(tiles[key])
		tiles.erase(key)
		lighting_dirty.erase(key)

func player_region_ready(point: Vector3) -> bool:
	return world_ready and active_leaves.has(Vector2i(floori(point.x / float(FINE_SIZE)), floori(point.z / float(FINE_SIZE))))

func is_collision_region_ready(bounds: AABB) -> bool:
	# Publication readiness, not a solid-ground test. Empty columns are valid.
	return world_ready and planner.collision_region_ready(bounds,active_leaves)

func request_height(point: Vector3, token: int) -> void:
	backend.submit({"kind": "height", "point": point, "token": token}, true)

func request_density_ray(from: Vector3, to: Vector3, token: int, budget: int = 256, with_material:bool=false) -> bool:
	if stopping or not world_ready or pending_edit or _density_requests.size()>=8 or token<0: return false
	_density_serial+=1
	var request := {"token":token,"epoch":epoch,"revision":native_revision,"ticket":edit_ticket}
	if not backend.submit({"kind":"density_ray","from":from,"to":to,"budget":budget,"token":_density_serial,"epoch":epoch,"revision":native_revision,"with_material":with_material}): return false
	_density_requests[_density_serial]=request
	return true

func try_placement_target(point:Vector3,normal:Vector3)->Dictionary:
	if stopping or closing or not world_ready or pending_edit:return {}
	return backend.try_placement_target(point,normal,native_revision)

func request_placement_target(point:Vector3,normal:Vector3,token:int,region:=false)->bool:
	if stopping or not world_ready or pending_edit or _density_requests.size()>=8 or token<0:return false
	_density_serial+=1
	var request:={"kind":"placement_target","region":region,"token":token,"epoch":epoch,"revision":native_revision,"ticket":edit_ticket}
	if not backend.submit({"kind":"placement_target","region":region,"point":point,"normal":normal,"token":_density_serial,"epoch":epoch,"revision":native_revision}):return false
	_density_requests[_density_serial]=request
	return true

func _cancel_density_requests(status: String) -> void:
	var requests := _density_requests.values()
	_density_requests.clear()
	for request: Dictionary in requests:
		var reply:={"kind":request.get("kind","density_ray"),"status":status,"token":request.token,"epoch":request.epoch,"requested_revision":request.revision}
		if reply.kind=="placement_target":
			reply["region"]=request.get("region",false)
			placement_target_received.emit(reply)
		else:density_ray_received.emit(reply)

func _select_dirty_owners(job: Dictionary, members: int) -> void:
	var key: Vector3i=job.key
	if not tiles.has(key) or not tiles[key].has("bricks"):return
	if tiles[key].get("triangle_pages",false):
		var previous:Dictionary={}
		for id:int in tiles[key].bricks:previous[id]=tiles[key].bricks[id].arrays
		job.previous_pages=previous
		return
	var bottoms: Array=[]
	for bottom: int in tiles[key].bricks:
		var child: Dictionary=tiles[key].bricks[bottom]
		for i in edit_geometry_bounds.size():
			if (members & (1 << i)) == 0: continue
			var brush := edit_geometry_bounds[i]
			if child.has("region_bounds"):
				var region: AABB = child.region_bounds.grow(17.0 if key.z>32 else 1.0)
				if not region.intersects(brush): continue
			elif bottom>brush.end.y or bottom+33<brush.position.y: continue
			bottoms.append(bottom)
			break
	job["brick_bottoms"]=bottoms

func _invalidate() -> Array[Dictionary]:
	var affected: Array[Dictionary] = []
	var refinement: Array[Dictionary] = []
	# Union the touched LOD tiles. Bits identify the individual brush footprints
	# that reach each tile, including their simplifier halos.
	var tile_members := {}
	for i in edit_geometry_bounds.size():
		var lo := edit_geometry_bounds[i].position
		var hi := edit_geometry_bounds[i].end
		for size: int in [16, 32, 64, 128, 256]:
			var halo:=17.0 if (backend.region_terrain or backend.local_terrain) and size>32 else 0.0
			var x0: int = maxi(0, floori((lo.x-halo) / float(size))) * size
			var z0: int = maxi(0, floori((lo.z-halo) / float(size))) * size
			var x1: int = mini(2047, ceili(hi.x+halo))
			var z1: int = mini(2047, ceili(hi.z+halo))
			for z in range(z0, z1 + 1, size):
				for x in range(x0, x1 + 1, size):
					var key := Vector3i(x, z, size)
					tile_members[key] = int(tile_members.get(key,0)) | (1 << i)
	for key: Vector3i in tile_members:
		var was_clean: bool=tiles.has(key) and not tiles[key].dirty
		edit_rollback.push_back({"key": key, "stamp": int(stamps.get(key, 0)), "dirty": bool(tiles[key]["dirty"]) if tiles.has(key) else false})
		stamps[key] = int(stamps.get(key, 0)) + 1
		if tiles.has(key):
			tiles[key]["dirty"] = true
		if visible_cut.has(key):
			last_density_tiles += 1
			affected.push_back({"key": key, "stamp": stamps[key], "lighting_only": false})
			if key.z in [16,32] and tiles[key].step==1 and tiles[key].has("arrays"):
				# Packed arrays retain the exact prior geometry by reference until
				# the worker has compared the two sides of this publication.
				affected[-1].previous_rim=[tiles[key].arrays[Mesh.ARRAY_VERTEX],tiles[key].arrays[Mesh.ARRAY_INDEX]]
				affected[-1].previous_stamp=tiles[key].stamp
			if backend.qualify_surface_owners and was_clean and key.z in [16,32] and tiles[key].step==1 and not tiles[key].has("bricks") and not lighting_dirty.has(key):
				affected[-1]["retain_if_untouched"]=true
				for light:Vector2 in tiles[key].arrays[Mesh.ARRAY_TEX_UV]:
					if light.x<1.0 or light.y<1.0:
						affected[-1]["retain_if_untouched"]=false
						break
			_select_dirty_owners(affected[-1],tile_members[key])
			if was_clean and affected[-1].has("previous_pages") and not lighting_dirty.has(key):affected[-1].clean_pages=true
		elif key.z == 16 and requested_keys.has(key):
			# Repeated edits must not invalidate the same requested fine
			# children forever. Publish a bounded set in this transaction,
			# with the same field revision as the still-visible coarse mesh.
			refinement.push_back({"key": key, "stamp": stamps[key], "lighting_only": false})
			# A current hidden child can retain unaffected owners just like
			# a visible child. Previously dirty children require a full build:
			# this brush's bounds cannot account for earlier missed changes.
			if was_clean: _select_dirty_owners(refinement[-1],tile_members[key])
	refinement.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _distance(a["key"]) < _distance(b["key"]))
	for index in range(mini(4, refinement.size())):
		affected.push_back(refinement[index])
		last_density_tiles += 1
	# Build the region under a single brush first. The camera may be across
	# the lake, particularly when authoring from the third-person view.
	if edit_geometry_bounds.size()==1:
		var center:=edit_geometry_bounds[0].get_center()
		for item in affected:
			var key:Vector3i=item.key
			var offset:=Vector2(key.x+key.z*0.5-center.x,key.y+key.z*0.5-center.z)
			item.brush_distance=offset.length_squared()
		affected.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
			if a.brush_distance==b.brush_distance:return _distance(a.key)<_distance(b.key)
			return a.brush_distance<b.brush_distance)
	else:
		affected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _distance(a["key"]) < _distance(b["key"]))
	_edit_visible_owners.clear()
	_edit_owner_cells.clear()
	for item in affected:
		var owner:Vector3i=item.key
		if not visible_cut.has(owner):continue
		_edit_visible_owners[owner]=true
		for z in range(owner.y,owner.y+owner.z,16):
			for x in range(owner.x,owner.x+owner.z,16):
				_edit_owner_cells[Vector2i(x,z)]=owner
	return affected

func _queue_lighting_refresh() -> void:
	lighting_generation += 1
	last_relight_tiles = 0
	for key: Vector3i in tiles:
		# Newly rebuilt geometry already contains current lighting. Inactive old
		# cache entries get invalidated, not synchronously rebuilt for a dig.
		var rebuilt := false
		for bounds in edit_geometry_bounds:
			if key.x+key.z>=bounds.position.x and key.x<=bounds.end.x and key.y+key.z>=bounds.position.z and key.y<=bounds.end.z:
				rebuilt = true
				break
		if rebuilt:
			if tiles[key].has("bricks"):
				lighting_dirty[key]=lighting_generation
				last_relight_tiles+=1
			else: lighting_dirty.erase(key)
			continue
		if float(key.x + key.z) < shadow_lo.x or float(key.x) > shadow_hi.x or float(key.y + key.z) < shadow_lo.z or float(key.y) > shadow_hi.z:
			continue
		if not bool(tiles[key].get("cavity_visibility", false)):
			continue
		lighting_dirty[key] = lighting_generation
		last_relight_tiles += 1

func _schedule_lighting() -> void:
	if not world_ready or pending_edit or stopping or foreground_brush or generation_collision_only or diagnostics_pause_streaming:
		return
	# Coalesce remote roof-light changes during a stroke. Local lighting is
	# already committed with geometry; distant irradiance catches up separately.
	if Time.get_ticks_usec() - last_geometry_done_us < 150000:
		return
	if backend.queued() >= 2 or lighting_in_flight.size() >= 1:
		return
	for key: Vector3i in lighting_dirty:
		if lighting_in_flight.has(key) or not tiles.has(key) or not visible_cut.has(key):
			continue
		var entry: Dictionary = tiles[key]
		if bool(entry["dirty"]):
			continue
		var brick_bottom: int=-1
		if entry.has("bricks"):
			for bottom: int in entry.bricks:
				var child: Dictionary=entry.bricks[bottom]
				if int(child.get("light_generation",-1))==int(lighting_dirty[key]): continue
				if child.attribute_layout.is_empty():
					child["light_generation"]=lighting_dirty[key]
					continue
				brick_bottom=bottom
				entry=child
				break
			if brick_bottom<0:
				lighting_dirty.erase(key)
				continue
		if not entry.has("arrays"): continue
		var accepted: bool = backend.submit({"kind": "relight", "key": key, "arrays": entry["arrays"], "attribute_layout": entry["attribute_layout"],
			"triangles": entry["triangles"], "bytes": entry["bytes"], "stamp": stamps.get(key, 0),
			"epoch": epoch, "light_ticket": lighting_dirty[key], "brick_bottom":brick_bottom})
		if accepted:
			lighting_in_flight[key] = lighting_dirty[key]
		break

func loading_state(point: Vector3, flying: bool) -> Dictionary:
	var ready_near: int = 0
	var needed_near: int = 0
	if not flying or (point.x >= 0 and point.z >= 0 and point.x < 2000 and point.z < 2000 and point.y < 300):
		for z in [-16.0, 0.0, 16.0]:
			for x in [-16.0, 0.0, 16.0]:
				var test: Vector3 = point + Vector3(x, 0, z)
				if test.x >= 0 and test.z >= 0 and test.x < 2000 and test.z < 2000:
					needed_near += 1
					if player_region_ready(test):
						ready_near += 1
	var ready_coverage:int=root_coverage
	var needed_coverage:int=roots.size()
	if nearby_first:
		ready_coverage=0;needed_coverage=0
		for key: Vector3i in roots:
			var dx: float = maxf(maxf(float(key.x) - point.x, point.x - float(key.x + key.z)), 0.0)
			var dz: float = maxf(maxf(float(key.y) - point.z, point.z - float(key.y + key.z)), 0.0)
			if dx * dx + dz * dz < 384.0 * 384.0:
				needed_coverage+=1
				if covered_roots.has(key):ready_coverage+=1
	var coverage_ready:bool=ready_coverage==needed_coverage
	return {"ready": world_ready and coverage_ready and ready_near == needed_near,
		"roots": root_coverage, "root_total": roots.size(), "local": ready_near, "local_total": needed_near,
		"coverage_ready":ready_coverage,"coverage_total":needed_coverage,"coverage_scope":"within 384 m" if nearby_first else "whole map",
		"queued": backend.queued(), "worker": backend.status()}

func edit(data: PackedByteArray, lo: Vector3, hi: Vector3, captured_us: int = 0, commands: Array[PackedByteArray] = [], member_captures: Array[Dictionary] = []) -> bool:
	if not world_ready or pending_edit or stopping or closing:
		return false
	if commands.is_empty():
		commands = [data]
	if commands.size() > 4 or (not member_captures.is_empty() and member_captures.size() != commands.size()):
		return false
	_cancel_partition()
	note_interaction()
	# Start timing BEFORE invalidation, not after unmeasured input-thread work.
	var accepted_us: int = Time.get_ticks_usec()
	edit_accepted_us = accepted_us
	edit_started_us = captured_us if captured_us > 0 else accepted_us
	last_capture_wait_ms = float(accepted_us - edit_started_us) / 1000.0
	last_density_tiles = 0
	last_untouched_surface_tiles=0
	last_direct_triangle_pages=0
	last_worker_packed_surfaces=0
	last_relight_tiles = 0
	latest_edit_members.clear()
	latest_member_changes.clear()
	edit_lo = lo
	edit_hi = hi
	edit_geometry_bounds.clear()
	geometry_lo = Vector3.INF
	geometry_hi = -Vector3.INF
	for index in range(commands.size()):
		var command: PackedByteArray = commands[index]
		var descriptor: Dictionary = {"command": command.decode_u32(0)}
		var member_lo: Vector3 = lo
		var member_hi: Vector3 = hi
		if command.size() == 44 and command.decode_u32(0) == 2:
			var a := Vector3(command.decode_float(4), command.decode_float(8), command.decode_float(12))
			var b := Vector3(command.decode_float(16), command.decode_float(20), command.decode_float(24))
			var shape:int=command.decode_u32(32)
			var halo: Vector3 = Vector3.ONE * (command.decode_float(28) + 5.0 + (Codec.CONTACT_MINING_HALO if shape==Codec.CONTACT_MINING_SHAPE else 0.0))
			member_lo = a.min(b) - halo
			member_hi = a.max(b) + halo
			descriptor["radius"] = command.decode_float(28)
			descriptor["shape"] = shape
			descriptor["add"] = command.decode_u32(36) != 0
			descriptor["a"] = [a.x, a.y, a.z]
			descriptor["b"] = [b.x, b.y, b.z]
		elif command.size() >= 20 and command.decode_u32(0) == 3:
			var cell := Vector3(command.decode_s32(4), command.decode_s32(8), command.decode_s32(12))
			member_lo = cell - Vector3.ONE * 2.0
			member_hi = cell + Vector3.ONE * 3.0
		edit_geometry_bounds.append(AABB(member_lo,member_hi-member_lo))
		geometry_lo = geometry_lo.min(member_lo)
		geometry_hi = geometry_hi.max(member_hi)
		var member_us: int = int(member_captures[index]["captured_us"]) if not member_captures.is_empty() else edit_started_us
		latest_edit_members.push_back({"captured_us": member_us, "descriptor": descriptor})
	latest_edit_descriptor = latest_edit_members[0]["descriptor"]
	# Upper-hemisphere ray directions have a minimum Y component of .18.
	# Remote light recipients are marked but are no longer part of the geometry
	# publication barrier. There is no 100m-wide collision rebuild for a 1m dig.
	var reach: float = maxf(0.0, hi.y) * 5.47
	shadow_lo = lo - Vector3(reach, 0.0, reach)
	shadow_hi = hi + Vector3(reach, 0.0, reach)
	edit_rollback.clear()
	resident_edit_surface={}
	var affected: Array[Dictionary] = _invalidate()
	edit_ticket += 1
	pending_edit = true
	edit_worker_done = false
	batch_remaining = 0
	var support:=_capture_edit_support(AABB(geometry_lo,geometry_hi-geometry_lo))
	var support_snapshots:Array=[]
	for provider:Dictionary in _edit_support_snapshots:support_snapshots.append(provider.snapshot)
	_hand_edit=commands.size()==1 and (latest_edit_descriptor.command==38 or latest_edit_descriptor.get("shape",-1)==Codec.CONTACT_MINING_SHAPE)
	var accepted: bool = backend.submit({"kind": "edit", "command": data, "commands": commands, "tiles": affected, "contact_domain":_contact_domain(commands),
		"epoch": epoch, "ticket": edit_ticket, "geometry_lo": geometry_lo, "geometry_hi": geometry_hi,"support_points":support,"support_snapshots":support_snapshots}, true)
	if not accepted:
		pending_edit = false
		_edit_support_snapshots.clear();_edit_support_result.clear()
		_rollback_dirty()
		message_changed.emit("Terrain is busy; this stroke was not submitted. Try again when the current work finishes.")
	else:
		_cancel_density_requests("stale")
	return accepted

func _rollback_dirty() -> void:
	for old: Dictionary in edit_rollback:
		var key: Vector3i = old["key"]
		stamps[key] = old["stamp"]
		if tiles.has(key):
			tiles[key]["dirty"] = old["dirty"]
	edit_rollback.clear()

func _mark_modified_columns() -> void:
	for bounds in edit_geometry_bounds:
		for z in range(maxi(0, floori(bounds.position.z/16.0)), mini(125, floori(bounds.end.z/16.0))+1):
			for x in range(maxi(0, floori(bounds.position.x/16.0)), mini(125, floori(bounds.end.x/16.0))+1):
				modified_columns[Vector2i(x,z)] = true

func save_world() -> void:
	if stopping or not world_ready:
		message_changed.emit("Wait for the world before saving")
		return
	_manual_save_requested=true
	if pending_edit:
		message_changed.emit("Save queued until the pending edit is published")
		return
	_flush_manual_save()

func _flush_manual_save() -> void:
	if not _manual_save_requested or pending_edit or stopping or not world_ready: return
	if not latest_error.is_empty():
		_manual_save_requested=false
		message_changed.emit("Save cancelled because the world has an unresolved error")
		return
	# Capture addon state only after edit publication and its synchronous change
	# callbacks. A full worker queue leaves one coalesced request for next frame.
	var save_begin:=Time.get_ticks_usec()
	var submitted:bool=backend.submit({"kind":"save"})
	_record_stage("save capture",(Time.get_ticks_usec()-save_begin)/1000.0)
	if submitted:
		_manual_save_requested=false
		autosave_timer=0.0
		changed_since_save=false

func reload_world(reset: bool = false) -> void:
	if closing or stopping: return
	if pending_edit:
		message_changed.emit("Wait for the pending edit before loading/resetting")
		return
	if lifecycle_ready.is_valid() and not lifecycle_ready.call("reset" if reset else "reload"):
		if not _reload_requested: message_changed.emit("Waiting for addon transfers before loading")
		_reload_requested = true
		_reload_reset = reset
		return
	_reload_requested = false
	_cancel_partition()
	var dispatch_begin:=Time.get_ticks_usec()
	reload_started.emit()
	_record_stage("reload handlers",(Time.get_ticks_usec()-dispatch_begin)/1000.0)
	dispatch_begin=Time.get_ticks_usec()
	epoch += 1
	initial_loading = true
	root_coverage = 0
	covered_roots.clear()
	lighting_dirty.clear()
	lighting_in_flight.clear()
	lighting_upload.clear()
	latest_error = ""
	world_ready = false
	_cancel_density_requests("stale")
	var teardown_begin:=Time.get_ticks_usec()
	_retire_contact()
	for key: Vector3i in tiles:
		_destroy_entry(tiles[key])
	for key: Vector3i in staged_batch:
		_destroy_entry(staged_batch[key])
	_record_stage("reload deactivate",(Time.get_ticks_usec()-teardown_begin)/1000.0)
	teardown_begin=Time.get_ticks_usec()
	retired_payloads.append_array(tiles.values())
	retired_payloads.append_array(staged_batch.values())
	retired_payloads.append_array(staging)
	tiles.clear()
	if not preparation.is_empty():
		_destroy_entry(preparation["entry"])
		retired_payloads.append(preparation)
		preparation={}
	for paused: Dictionary in paused_preparations:
		_destroy_entry(paused.entry)
	retired_payloads.append_array(paused_preparations)
	paused_preparations.clear()
	staged_batch.clear()
	staging.clear()
	staging_versions.clear()
	_edit_support_snapshots.clear();_edit_support_result.clear()
	in_flight.clear()
	stamps.clear()
	visible_cut.clear()
	_cut_dirty = true
	active_leaves.clear()
	cache_bytes = 0
	_record_stage("reload records",(Time.get_ticks_usec()-teardown_begin)/1000.0)
	_record_stage("reload terrain retirement",(Time.get_ticks_usec()-dispatch_begin)/1000.0)
	dispatch_begin=Time.get_ticks_usec()
	backend.submit({"kind": "reset" if reset else "load", "epoch": epoch}, true)
	_record_stage("reload submit",(Time.get_ticks_usec()-dispatch_begin)/1000.0)

func lod_counts() -> String:
	var count: Dictionary = {16: 0, 32: 0, 64: 0, 128: 0, 256: 0}
	for key: Vector3i in visible_cut:
		count[key.z] += 1
	return "%d / %d / %d / %d / %d" % [count[16], count[32], count[64], count[128], count[256]]
