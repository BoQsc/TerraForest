# SPDX-License-Identifier: 0BSD
# Observation wrapper around the existing scripted full-world benchmark.
extends SceneTree
const Presentation=preload("res://addons/presentation/fullscreen_policy.gd")
var game: Node
var telemetry: FileAccess
var next_sample:=0
var last_stage:=""
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var prefix:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):prefix=arg.substr(6)
	if prefix.is_empty() or not "--benchmark" in OS.get_cmdline_user_args():
		push_error("Baseline requires --benchmark and an explicit --out prefix");quit(2);return
	telemetry=FileAccess.open(prefix+".observations.jsonl",FileAccess.WRITE)
	if telemetry==null:quit(2);return
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
func _process(_delta: float) -> bool:
	if game==null or telemetry==null:return false
	var now:=Time.get_ticks_msec()
	var stage:="%s:%s" % [game.benchmark.phase,game.benchmark.state]
	if now<next_sample and stage==last_stage:return false
	last_stage=stage
	next_sample=now+1000
	var row:=Presentation.measurement(root)
	row["engine_ms"]=now;row["phase"]=game.benchmark.phase;row["state"]=game.benchmark.state
	row["utc_unix_s"]=Time.get_unix_time_from_system()
	row["fps_cap_actual"]=Engine.max_fps;row["vsync_mode"]=DisplayServer.window_get_vsync_mode()
	row["focused"]=DisplayServer.window_is_focused();row["refresh_hz"]=DisplayServer.screen_get_refresh_rate()
	row["adapter"]=RenderingServer.get_video_adapter_name();row["renderer"]=RenderingServer.get_current_rendering_method()
	row["static_memory_bytes"]=Performance.get_monitor(Performance.MEMORY_STATIC)
	row["draw_calls"]=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	row["rendered_objects"]=Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	row["trees"]=game.vegetation.renderer.roots.size();row["terrain_triangles"]=game.terrain.total_triangles
	row["queued_jobs"]=game.terrain.backend.queued();row["derived_cache_enabled"]=game.terrain.backend.disk_cache.enabled
	row["generator"]=game.terrain.backend.world_generator;row["seed"]=game.terrain.backend.world_seed
	telemetry.store_line(JSON.stringify(row));telemetry.flush()
	return false
