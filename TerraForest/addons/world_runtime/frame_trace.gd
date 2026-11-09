# SPDX-License-Identifier: 0BSD
extends Node
## Opt-in rolling recorder. Inserted rows are immutable, including their stages.
const CAPACITY:=1200
const MAX_FILES:=8
const NAVIGATION_SAMPLE_LIMIT:=16
const PRE_US:=10000000
const POST_US:=2000000
const COOLDOWN_US:=10000000
var game:Node
var ring:Array[Dictionary]=[]
var head:=0
var count:=0
var stages:Dictionary={}
var physics_started:=0
var physics_elapsed_us:=0
var physics_steps:=0
var navigation_samples:Array[Dictionary]=[]
var navigation_samples_dropped:=0
var navigation_capture_us:=0
var process_started:=0
var process_finished:=0
var draw_started:=0
var previous:=0
var serial:=0
var last_trigger:=-COOLDOWN_US
var pending:Dictionary={}
var writer:Thread
var written:=0
var skipped_triggers:=0
var output:=""
var probe:RefCounted
var work_start:=PackedInt64Array()
var work_process:=PackedInt64Array()
var work_draw:=PackedInt64Array()
var work_physics:=PackedInt64Array()
var work_end:=PackedInt64Array()
var physics_cycles:=0
var physics_cpu_us:=0
var phase_probe_us:=0
var overhead_us:=0
var previous_profiling:Dictionary={}
var capture_threshold_ms:=20.0
var deferred_outlier_us:=0
var deferred_peak_ms:=0.0
var resident_ids:Dictionary={}
var cadence:Array[float]=[]
var cadence_sum:=0.0

func _ready()->void:
	process_priority=1000000;process_physics_priority=1000000
	ring.resize(CAPACITY)
	output="user://frame_traces/"+Time.get_datetime_string_from_system(true).replace(":","")+"_"+str(OS.get_process_id())
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--frame-trace-dir="):output=arg.trim_prefix("--frame-trace-dir=")
	if DirAccess.make_dir_recursive_absolute(output)!=OK:
		push_error("Frame trace output could not be created: "+output);queue_free();return
	if ClassDB.class_exists("NativeResourceUsage"):probe=ClassDB.instantiate("NativeResourceUsage")
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	get_tree().process_frame.connect(_begin_process)
	get_tree().physics_frame.connect(_begin_physics)
	RenderingServer.frame_pre_draw.connect(_begin_draw)
	RenderingServer.frame_post_draw.connect(_end_draw)
	print("FRAME_TRACE enabled output=",ProjectSettings.globalize_path(output)," marker=Ctrl+Shift+F12")

func attach(host:Node)->void:
	if host.get_viewport()!=get_tree().root:return
	detach();game=host
	game.terrain.stage_measured.connect(stage)
	for key:String in ["zombies","ground_cover"]:
		previous_profiling[key]=game.get(key).profiling_enabled;game.get(key).profiling_enabled=true
	previous_profiling["forest"]=game.vegetation.renderer.profiling_enabled
	game.vegetation.renderer.profiling_enabled=true
	game.tree_exiting.connect(detach,CONNECT_ONE_SHOT)
	stage("trace world attached",0)

func detach()->void:
	if is_instance_valid(game):
		if game.tree_exiting.is_connected(detach):game.tree_exiting.disconnect(detach)
		if game.terrain.stage_measured.is_connected(stage):game.terrain.stage_measured.disconnect(stage)
		for key:String in ["zombies","ground_cover"]:
			if previous_profiling.has(key):game.get(key).profiling_enabled=previous_profiling[key]
		if previous_profiling.has("forest"):game.vegetation.renderer.profiling_enabled=previous_profiling.forest
	game=null;previous_profiling.clear();resident_ids.clear()

func stage(label:String,milliseconds:float)->void:
	stages[label]=float(stages.get(label,0.0))+milliseconds

func _begin_process()->void:
	process_started=Time.get_ticks_usec()
	work_start=_sample_work()
func _begin_physics()->void:
	physics_started=Time.get_ticks_usec();physics_steps+=1
	work_physics=_sample_work()
func _physics_process(_delta:float)->void:
	if physics_started>0:
		physics_elapsed_us+=Time.get_ticks_usec()-physics_started
		var work:=_sample_work()
		var cycles:=work_delta(work_physics,work,0)
		var cpu_us:=work_delta(work_physics,work,1)
		physics_cycles=physics_cycles+cycles if physics_cycles>=0 and cycles>=0 else -1
		physics_cpu_us=physics_cpu_us+cpu_us if physics_cpu_us>=0 and cpu_us>=0 else -1
	physics_started=0
	if is_instance_valid(game) and game.startup_complete and game.zombies.update_phase_us.has("planning"):
		capture_navigation(game.zombies.navigation_status,game.zombies.update_phase_us)

func capture_navigation(status:Dictionary,phases:Dictionary)->void:
	var began:=Time.get_ticks_usec()
	if navigation_samples.size()<NAVIGATION_SAMPLE_LIMIT:
		navigation_samples.append({"physics_frame":Engine.get_physics_frames(),"navigation":status.duplicate(true),"phases_us":phases.duplicate()})
	else:navigation_samples_dropped+=1
	navigation_capture_us+=Time.get_ticks_usec()-began

func take_navigation_samples()->Dictionary:
	var result:Dictionary={"samples":navigation_samples,"dropped":navigation_samples_dropped}
	navigation_samples=[];navigation_samples_dropped=0
	return result
func _process(_delta:float)->void:
	process_finished=Time.get_ticks_usec()
	work_process=_sample_work()
	_poll_writer()
func _begin_draw()->void:
	draw_started=Time.get_ticks_usec()
	work_draw=_sample_work()

func _main_thread_work()->PackedInt64Array:
	# Never subtract counters sampled on different engine threads.
	if probe==null or OS.get_thread_caller_id()!=OS.get_main_thread_id():return PackedInt64Array()
	return probe.thread_work()

func _sample_work()->PackedInt64Array:
	var began:=Time.get_ticks_usec()
	var result:=_main_thread_work()
	phase_probe_us+=Time.get_ticks_usec()-began
	return result

static func work_delta(older:PackedInt64Array,newer:PackedInt64Array,index:int)->int:
	# Unsupported/failed counters are unknown, never evidence of zero CPU work.
	if older.size()!=2 or newer.size()!=2 or older[index]<0 or newer[index]<older[index]:return -1
	return newer[index]-older[index]

static func add_work(row:Dictionary,label:String,older:PackedInt64Array,newer:PackedInt64Array)->void:
	var cycles:=work_delta(older,newer,0)
	var cpu_us:=work_delta(older,newer,1)
	if cycles>=0:row["thread_cycles" if label.is_empty() else label+"_cycles"]=cycles
	if cpu_us>=0:row[("" if label.is_empty() else label+"_")+"thread_cpu_ms"]=cpu_us/1000.0

func _end_draw()->void:
	var began:=Time.get_ticks_usec()
	var work:=_main_thread_work()
	if previous==0:
		previous=began;work_end=work;stages={};physics_elapsed_us=0;physics_steps=0
		physics_cycles=0;physics_cpu_us=0;phase_probe_us=0;return
	var row:Dictionary={"frame":Engine.get_process_frames(),"at_us":began,"frame_ms":(began-previous)/1000.0,
		"before_process_ms":(process_started-previous)/1000.0,"process_ms":(process_finished-process_started)/1000.0,
		"after_process_ms":(draw_started-process_finished)/1000.0,"draw_ms":(began-draw_started)/1000.0,
		"physics_ms":physics_elapsed_us/1000.0,"physics_steps":physics_steps,"stages_ms":stages,
		"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"pipeline_draw":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
		"pipeline_specialization":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION),
		"focused":DisplayServer.window_is_focused(),"fps_cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),
		"recorder_previous_us":overhead_us,"trace_writer_active":writer!=null}
	add_work(row,"",work_end,work)
	add_work(row,"before_process",work_end,work_start)
	add_work(row,"process",work_start,work_process)
	add_work(row,"after_process",work_process,work_draw)
	add_work(row,"draw",work_draw,work)
	if physics_steps>0:
		if physics_cycles>=0:row.physics_cycles=physics_cycles
		if physics_cpu_us>=0:row.physics_thread_cpu_ms=physics_cpu_us/1000.0
	work_end=work
	var active:bool=is_instance_valid(game) and game.startup_complete
	if active:
		row.position=game.player.position;row.velocity=game.player.velocity
		row.loading=game.loading_active;row.menu=game.session_menu.visible_ui();row.inventory=game.player_hud.inventory_open
		row.entry=game.player_view.entry.blocks_actions();row.driving=game.world_vehicle.driving
		row.first_person={"enabled":game.first_person_view.enabled,"active":game.first_person_view.active,"detailed_shadows":game.first_person_view.shadows_enabled,"overlay":game.first_person_view.overlay_active}
		row.focus_admitted=game.app_focused;row.terrain_queued=game.terrain.backend.queued()
		row.terrain_pending_edit=game.terrain.pending_edit;row.surface_backlog=game.terrain._surface_replies.size()
		row.zombies=game.zombies.residents.size();row.zombie_phases_us=game.zombies.update_phase_us.duplicate()
		row.zombie_navigation=game.zombies.navigation_status.duplicate(true)
		var current_ids:Dictionary={}
		for zombie:Node3D in game.zombies.residents:
			if not is_instance_valid(zombie):continue
			var identity:int=zombie.get_instance_id();current_ids[identity]=true
			if not resident_ids.has(identity):
				if not row.has("zombie_initializations"):row.zombie_initializations=[]
				row.zombie_initializations.append({"id":identity,"initialization_us":zombie.initialization_us.duplicate()})
		resident_ids=current_ids
		if stages.has("save capture"):row.save_components=game.persistence.last_capture.duplicate(true)
		row.forest_us=game.vegetation.renderer.stats.get("update_us",0);row.ecosystem_us=game.ecosystem.last_process_us
		row.cover_us=game.ground_cover.last_process_us;row.cover_cells=game.ground_cover.resident.size();row.cover_wanted=game.ground_cover._wanted.size()
		row.block_occlusion=game.structures.blocks.occlusion_stats()
		row.cover_render_phases_us=[]
		for batch:Node in game.ground_cover.batches:row.cover_render_phases_us.append(batch.render_frame_profile())
		row.phase="loading" if game.loading_active else ("entry" if row.entry else ("menu" if row.menu or row.inventory else "gameplay"))
	else:row.phase="startup" if is_instance_valid(game) else "browser"
	row.zombie_navigation_ticks=take_navigation_samples()
	var eligible:bool=active and not game.shutdown_requested and not game.loading_active and not row.menu and not row.inventory and game.app_focused
	record(row,eligible)
	previous=began;stages={};physics_elapsed_us=0;physics_steps=0
	physics_cycles=0;physics_cpu_us=0
	overhead_us=Time.get_ticks_usec()-began+navigation_capture_us+phase_probe_us
	navigation_capture_us=0;phase_probe_us=0

func record(row:Dictionary,auto_trigger:bool)->void:
	if auto_trigger:
		cadence.append(float(row.frame_ms));cadence_sum+=float(row.frame_ms)
		if cadence.size()>30:cadence_sum-=cadence.pop_front()
	else:cadence.clear();cadence_sum=0
	var sustained:bool=cadence.size()==30 and cadence_sum/30.0>17.5
	row.cadence_ms=cadence_sum/cadence.size() if not cadence.is_empty() else 0.0
	ring[head]=row;head=(head+1)%CAPACITY;count=mini(count+1,CAPACITY)
	if not pending.is_empty():
		if pending.frames.size()<CAPACITY*2:pending.frames.append(row)
		else:pending.truncated=true
		if int(row.at_us)>=int(pending.until_us):_submit()
	if auto_trigger and (float(row.frame_ms)>capture_threshold_ms or sustained) and pending.is_empty():
		if deferred_outlier_us==0:deferred_outlier_us=int(row.at_us)
		deferred_peak_ms=maxf(deferred_peak_ms,float(row.frame_ms))
	if deferred_outlier_us>0 and pending.is_empty() and writer==null and int(row.at_us)-last_trigger>=COOLDOWN_US:
		if mark("frame over %.1f ms or sustained 30-frame mean over 17.5 ms (peak %.3f ms)"%[capture_threshold_ms,deferred_peak_ms],int(row.at_us)):
			pending.metadata.outlier_us=deferred_outlier_us
			deferred_outlier_us=0;deferred_peak_ms=0

func history(now:int)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for offset in count:
		var row:Dictionary=ring[(head-count+offset+CAPACITY)%CAPACITY]
		if int(row.at_us)>=now-PRE_US:result.append(row)
	return result

func mark(label:String,now:int=-1)->bool:
	if now<0:now=Time.get_ticks_usec()
	if not pending.is_empty() or writer!=null:skipped_triggers+=1;return false
	last_trigger=now;serial+=1
	pending={"schema":1,"trigger":label,"trigger_us":now,"until_us":now+POST_US,"frames":history(now),"truncated":false,
		"metadata":{"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"viewport":get_viewport().get_visible_rect().size,
		"arguments":OS.get_cmdline_user_args(),"slot":game.terrain.save_slot if is_instance_valid(game) else "",
		"scope":"Wall intervals; physics/stages overlap other intervals. GPU timers may lag; CPU-time quantized. Encoding/I/O off-thread. Ring: 1200 frames/10 s; post: 2 s, max 2400 rows. Eight files rotate per session.",
		"skipped_triggers":skipped_triggers,"capture_serial":serial}}
	return true

func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F12 and event.ctrl_pressed and event.shift_pressed:
		mark("player marker");get_viewport().set_input_as_handled()

func _submit()->void:
	if pending.is_empty() or writer!=null:return
	var snapshot:=pending;pending={}
	var path:=output.path_join("trace_%02d.json"%((serial-1)%MAX_FILES))
	writer=Thread.new()
	if writer.start(_write.bind(path,snapshot))!=OK:writer=null;push_error("Frame trace writer could not start")

static func _write(path:String,snapshot:Dictionary)->Dictionary:
	var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file==null:return {"ok":false,"path":path}
	file.store_string(JSON.stringify(snapshot));file.close()
	var error:=DirAccess.rename_absolute(path+".tmp",path)
	return {"ok":error==OK,"path":path}

func _poll_writer()->void:
	if writer==null or writer.is_alive():return
	var result:Dictionary=writer.wait_to_finish();writer=null
	if result.ok:written+=1
	else:push_error("Frame trace write failed: "+str(result.path))

func _exit_tree()->void:
	detach()
	if writer!=null:writer.wait_to_finish();writer=null
	if pending.is_empty() and deferred_outlier_us>0:mark("deferred outlier at shutdown")
	if not pending.is_empty():
		pending.truncated=true;_submit()
		if writer!=null:writer.wait_to_finish();writer=null
