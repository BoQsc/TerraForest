# SPDX-License-Identifier: 0BSD
extends RefCounted
var host: Node
var rows: Array[Dictionary]=[]
var stages: Dictionary={}
var previous:=0
var phase:="preparation"
var viewport: RID
var previous_profiling:=false
var process_started:=0
var draw_started:=0
var pipeline_monitors: Dictionary={}
func start(game: Node) -> void:
	host=game;previous=Time.get_ticks_usec();viewport=game.get_viewport().get_viewport_rid()
	for name: String in ClassDB.class_get_integer_constant_list("Performance"):
		if "PIPELINE_COMPILATIONS" in name: pipeline_monitors[name]=ClassDB.class_get_integer_constant("Performance",name)
	previous_profiling=host.vegetation.renderer.profiling_enabled;host.vegetation.renderer.profiling_enabled=true
	RenderingServer.viewport_set_measure_render_time(viewport,true)
	game.terrain.stage_measured.connect(_stage)
	game.get_tree().process_frame.connect(_process_begin)
	RenderingServer.frame_pre_draw.connect(_draw_begin)
	RenderingServer.frame_post_draw.connect(_frame)
func _process_begin() -> void: process_started=Time.get_ticks_usec()
func _draw_begin() -> void: draw_started=Time.get_ticks_usec()
func _stage(label: String,ms: float) -> void:
	stages[label]=float(stages.get(label,0.0))+ms
func measure_action(label: String,action: Callable) -> void:
	var started:=Time.get_ticks_usec()
	action.call()
	_stage("test action: "+label,(Time.get_ticks_usec()-started)/1000.0)
func _frame() -> void:
	var now:=Time.get_ticks_usec()
	if rows.size()<1200:
		rows.append({"phase":phase,"frame_ms":(now-previous)/1000.0,"cap":Engine.max_fps,"dialog_focus":host.construction_palette.survey_dialog.has_focus(),"stages":stages.duplicate(),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"vegetation_update_us":host.vegetation.renderer.stats.get("update_us",0),"ecosystem_us":host.ecosystem.last_process_us,"queued":host.terrain.backend.queued(),"pending_edit":host.terrain.pending_edit,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		rows[-1]["vegetation_phases_us"]=Array(host.vegetation.renderer.phase_us)
		rows[-1]["vegetation_stats"]=host.vegetation.renderer.stats.duplicate()
		rows[-1]["native_selection"]=host.vegetation.renderer.native_selection!=null
		rows[-1]["embedded_dialog"]=host.construction_palette.survey_dialog.is_embedded()
		rows[-1]["before_process_ms"]=(process_started-previous)/1000.0
		rows[-1]["process_to_draw_ms"]=(draw_started-process_started)/1000.0
		rows[-1]["draw_to_post_ms"]=(now-draw_started)/1000.0
		var pipelines: Dictionary={}
		for name: String in pipeline_monitors: pipelines[name]=Performance.get_monitor(pipeline_monitors[name])
		rows[-1]["pipeline_compilations"]=pipelines
	previous=now;stages.clear()
func finish(path: String) -> Dictionary:
	RenderingServer.frame_post_draw.disconnect(_frame);host.terrain.stage_measured.disconnect(_stage)
	host.get_tree().process_frame.disconnect(_process_begin)
	RenderingServer.frame_pre_draw.disconnect(_draw_begin)
	RenderingServer.viewport_set_measure_render_time(viewport,false)
	host.vegetation.renderer.profiling_enabled=previous_profiling
	var intervals: Array[float]=[]
	for row: Dictionary in rows: intervals.append(row.frame_ms)
	intervals.sort()
	var summary:={"frames":rows.size(),"p95_ms":intervals[floori((intervals.size()-1)*0.95)] if not intervals.is_empty() else 0,"max_ms":intervals[-1] if not intervals.is_empty() else 0,"notes":"Post-draw wall intervals include cap/wait time. Stage labels can nest and must not be summed across labels. GPU timers may lag and zero is unavailable, not zero work. 1200-frame capture limit."}
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify({"summary":summary,"frames":rows},"  "));file.close()
	return summary
