# SPDX-License-Identifier: 0BSD
# Measures real moving frames, and separates edit CPU, mesh build and publication latency.
extends Node
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
var host
var names: Array[String] = ["display_only_control", "moving_surface", "underground", "construction", "pre_dig", "continuous_dig", "post_dig", "whole_map"]
var phase: int = -1
var state: String = "startup"
var elapsed: float = 0.0
var total_elapsed: float = 0.0
var duration: float = 10.0
var warmup: float = 3.0
var soak_duration: float = 300.0
var settle: float = 0.0
var samples: Array[float] = []
var edit_latencies: Array[float] = []
var gpu_times: Array[float] = []
var begin_position := Vector3.ZERO
var dig_y: float = 60.0
var dig_clock: float = 0.0
var rows: Array[Array] = []
var sample_file: FileAccess
var prefix: String = "user://benchmark"
var soak: bool = false
var proof_submitted: bool = false
var last_tick: int = 0
var last_process_us: int = 0
var viewport_gpu_supported: bool = false

func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "--soak":
			soak = true
		if arg.begins_with("--seconds="):
			duration = clampf(float(arg.get_slice("=", 1)), 5.0, 3600.0)
		if arg.begins_with("--soak-seconds="):
			soak_duration = clampf(float(arg.get_slice("=", 1)), 300.0, 3000.0)
		if arg.begins_with("--out="):
			prefix = arg.substr(6)
	if soak:
		names.append("sustained_digging")
	var size: Vector2 = host.get_viewport().get_visible_rect().size
	if int(size.x) != 1920 or int(size.y) != 1080:
		_fail("Benchmark requires an actual 1920x1080 viewport; received %dx%d" % [size.x, size.y])
		return
	sample_file = FileAccess.open(prefix + ".frames.csv", FileAccess.WRITE)
	if sample_file == null:
		_fail("Cannot open benchmark output: " + prefix)
		return
	sample_file.store_csv_line(PackedStringArray(["phase", "sample", "frame_ms", "viewport_gpu_ms", "worker_edit_ms", "worker_patch_ms", "main_publish_ms", "edit_to_publish_ms", "queued_jobs", "cache_mib", "pages", "triangles", "pending_edit", "engine_static_memory_mib", "worker_queue_ms", "all_patch_builds_ms", "publish_frame_ms", "edit_to_draw_callback_ms", "wall_hitches_over_50ms"]))
	host.terrain.edit_published.connect(_on_edit)
	host.fly = true
	last_tick = Time.get_ticks_usec()
	host._message("BENCHMARK: temporary world; actual 1080p; waiting for complete starting coverage")

func _fail(text: String) -> void:
	push_error(text)
	print("BENCHMARK FAILED: ", text)
	if sample_file != null:
		sample_file.close()
	host.terrain.shutdown()
	get_tree().quit(2)

func _on_edit(latency: float) -> void:
	if state == "measuring":
		edit_latencies.push_back(latency)

func _process(_delta: float) -> void:
	var now_us: int = Time.get_ticks_usec()
	var delta: float = float(now_us - last_process_us) / 1000000.0 if last_process_us > 0 else 0.0
	last_process_us = now_us
	total_elapsed += delta
	if total_elapsed > (3600.0 if soak else 600.0):
		_fail("Benchmark watchdog: setup or work did not finish within its deadline")
		return
	if host.terrain.latest_error != "":
		_fail(host.terrain.latest_error)
		return
	if state == "startup":
		if host.terrain.world_ready and not host.waiting_spawn and not host.loading_active and host.terrain.player_region_ready(host.player.position) and host.terrain.visible_cut.size() >= 64 and host.terrain.backend.queued() == 0:
			_next_phase()
		return
	if state == "waiting":
		if host.waiting_spawn or host.loading_active or host.terrain.pending_edit or (phase != 7 and not host.terrain.player_region_ready(host.player.position)):
			return
		if phase == 3 and not proof_submitted:
			host.build_proof()
			proof_submitted = true
			return
		if host.terrain.backend.queued() > 0 or not host.terrain.staging.is_empty() or not host.terrain.preparation.is_empty() or not host.terrain.in_flight.is_empty():
			settle = 0.0
			return
		settle += delta
		if settle < 0.5:
			return
		if phase == 1:
			host.player.position.y += 8.0
		if phase == 4:
			dig_y = host.player.position.y - 2.0
			host.player.position = Vector3(980, dig_y + 15.0, 1332)
		if phase == 5 or phase == 6 or phase == 8:
			host.player.position = Vector3(980, dig_y + 15.0, 1332)
		begin_position = host.player.position
		state = "warmup"
		elapsed = 0.0
		return
	if state != "warmup" and state != "measuring":
		return
	elapsed += delta
	_move_camera(elapsed)
	if state == "warmup":
		if elapsed >= warmup:
			elapsed = 0.0
			state = "measuring"
			print("BENCHMARK_MEASURING ", names[phase])
			samples.clear()
			gpu_times.clear()
			edit_latencies.clear()
			last_tick = Time.get_ticks_usec()
		return
	var tick: int = Time.get_ticks_usec()
	var frame_ms: float = float(tick - last_tick) / 1000.0
	last_tick = tick
	var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(host.get_viewport().get_viewport_rid()) if host.gpu_timing_enabled else -1.0
	samples.push_back(frame_ms)
	if gpu > 0.0:
		gpu_times.push_back(gpu)
	if (phase == 5 or phase == 8) and not host.terrain.pending_edit:
		dig_clock -= delta
		if dig_clock <= 0.0:
			dig_clock = 0.15
			# Continuously CHANGING terrain, not only repeated no-op edits.
			var t: float = elapsed if phase == 5 else elapsed * 0.4
			var center := Vector3(973.0 + 10.0 * sin(t * 0.15), dig_y - 2.0 - fmod(t * 0.16, 16.0), 1310.0 + 8.0 * cos(t * 0.11))
			var add: bool = phase == 8 and int(t / 20.0) % 2 == 1
			var margin := Vector3.ONE * 8.5
			host.terrain.edit(Codec.brush(center, center, 3.5, 0, add, 1), center - margin, center + margin)
	sample_file.store_csv_line(PackedStringArray([names[phase], str(samples.size()), str(frame_ms), str(gpu), str(host.terrain.last_edit_ms), str(host.terrain.last_mesh_ms), str(host.terrain.last_publish_ms), str(host.terrain.last_latency_ms), str(host.terrain.backend.queued()), str(float(host.terrain.cache_bytes) / 1048576.0), str(host.terrain.sdf_pages), str(host.terrain.total_triangles), str(host.terrain.pending_edit), str(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0), str(host.terrain.last_queue_ms), str(host.terrain.last_total_build_ms), str(host.terrain.last_publish_frame_ms), str(host.terrain.last_draw_latency_ms), str(host.hitch_count)]))
	var phase_duration: float = soak_duration if phase == 8 else duration
	if elapsed >= phase_duration:
		_finish_phase()
		_next_phase()

func _move_camera(t: float) -> void:
	if phase == 0:
		return
	if phase == 7:
		host.player.position = begin_position + Vector3(sin(t * 0.1) * 25.0, 0, cos(t * 0.1) * 25.0)
		host.camera.look_at(Vector3(1000, 80, 1000), Vector3.UP)
	elif phase == 2:
		host.player.position = begin_position + Vector3(sin(t * 0.2) * 2.0, 0, cos(t * 0.2) * 2.0)
		host.camera.look_at(Vector3(1010, 62, 1020), Vector3.UP)
	elif phase >= 4:
		host.player.position = begin_position + Vector3(sin(t * 0.4) * 4.0, 0, cos(t * 0.4) * 3.0)
		host.camera.look_at(Vector3(975, dig_y - 2.0, 1310), Vector3.UP)
	else:
		host.player.position = begin_position + Vector3(sin(t * 0.15) * 18.0, 0, cos(t * 0.15) * 8.0)
		host.camera.look_at(Vector3(1484, begin_position.y, 1450) if phase == 3 else Vector3(1000, 125, 850), Vector3.UP)
	host.terrain.focus = host.player.position

func _next_phase() -> void:
	phase += 1
	if phase >= names.size():
		_complete()
		return
	state = "waiting"
	elapsed = 0.0
	settle = 0.0
	host.terrain.visible = phase != 0
	host.flashlight.visible = phase == 2
	var points: Array[Vector3] = [Vector3(960, 0, 1310), Vector3(960, 0, 1310), Vector3(985, 61, 985), Vector3(1484, 0, 1410), Vector3(980, 0, 1310), Vector3(980, 0, 1310), Vector3(980, 0, 1310), Vector3(2300, 1600, 2500), Vector3(980, 0, 1310)]
	host.camera.far = 6000.0 if phase == 7 else 3300.0
	host.camera.near = 1.0 if phase == 7 else 0.08
	host.teleport(points[phase], 61.0 if phase == 2 else (1600.0 if phase == 7 else -1.0))
	host._message("BENCHMARK %d/%d: %s (waiting for collision/LOD cache)" % [phase + 1, names.size(), names[phase]])
	print("BENCHMARK_PHASE ", names[phase])

func _percentile(values: Array[float], q: float) -> float:
	if values.is_empty():
		return -1.0
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[mini(sorted.size() - 1, int(float(sorted.size() - 1) * q))]

func _finish_phase() -> void:
	var total: float = 0.0
	for value: float in samples:
		total += value
	var mean: float = total / float(maxi(1, samples.size()))
	rows.append([names[phase], samples.size(), mean, 1000.0 / maxf(0.001, mean), _percentile(samples, 0.5), _percentile(samples, 0.95), _percentile(samples, 0.99), _percentile(gpu_times, 0.5), _percentile(gpu_times, 0.95), edit_latencies.size(), _percentile(edit_latencies, 0.95), host.terrain.sdf_pages, host.terrain.blocks, float(host.terrain.cache_bytes) / 1048576.0])
	sample_file.flush()
	print("BENCHMARK_RESULT ", rows.back())

func _complete() -> void:
	state = "complete"
	sample_file.close()
	var summary := FileAccess.open(prefix + ".summary.csv", FileAccess.WRITE)
	if summary == null:
		_fail("Cannot write benchmark summary")
		return
	summary.store_csv_line(PackedStringArray(["phase", "frames", "mean_frame_ms", "mean_fps", "p50_ms", "p95_ms", "p99_ms", "viewport_gpu_median_ms", "viewport_gpu_p95_ms", "published_edits", "edit_publish_p95_ms", "sdf_pages", "exact_blocks", "cache_estimate_mib"]))
	for row: Array in rows:
		var strings := PackedStringArray()
		for value: Variant in row:
			strings.append(str(value))
		summary.store_csv_line(strings)
	summary.close()
	var metadata := FileAccess.open(prefix + ".metadata.json", FileAccess.WRITE)
	if metadata != null:
		metadata.store_string(JSON.stringify({"project_version": ProjectSettings.get_setting("application/config/version", "unknown"), "engine": Engine.get_version_info(), "render_method": RenderingServer.get_current_rendering_method(), "video_adapter": RenderingServer.get_video_adapter_name(), "viewport": "1920x1080", "fps_cap": host.max_fps, "shadows": host.sun.shadow_enabled, "msaa": host.get_viewport().msaa_3d, "temporary_world": true, "gpu_timer_note": "Unavailable/zero timers are not evidence of zero GPU work; external device power CSV is separate."}, "\t"))
		metadata.close()
	print("BENCHMARK COMPLETE ", ProjectSettings.globalize_path(prefix + ".summary.csv"))
	host.terrain.shutdown()
	get_tree().quit(0)
