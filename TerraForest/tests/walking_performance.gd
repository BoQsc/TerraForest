# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_gameplay.gd"
# Reuse the human-checked source-world setup/input helpers, not its expensive
# capture/inspection loop. No runtime quality settings or population are reduced.
const COLUMNS := ["frame", "end_us", "frame_ms", "phase", "x", "y", "z", "yaw", "speed", "invalid", "grounded", "before_process_ms", "process_to_draw_ms", "draw_ms", "gpu_delayed_ms", "render_cpu_delayed_ms", "physics_monitor_ms", "draw_calls", "primitives", "pipeline_draw", "pipeline_specialization", "terrain_queued", "recorded_stage_sum_ms", "cover_ms", "forest_ms", "zombies_residency_ms", "thread_cycles", "thread_cpu_coarse_ms", "recorder_us", "cap", "vsync", "process_callbacks_ms", "after_process_ms", "physics_callbacks_ms", "physics_steps", "before_process_cycles", "process_cycles", "after_process_cycles", "draw_cycles"]
const CAPACITY := 24000
var samples := PackedFloat64Array()
var sample_count := 0
var recording := false
var diagnostic := false
var pacing := "uncapped"
var seconds := 30.0
var stage_id := 0
var stamp := 0
var start_stamp := 0
var process_stamp := 0
var draw_stamp := 0
var stage_ms := 0.0
var native_probe: Object
var prior_work := PackedInt64Array()
var overflow := false
var setup_failed := false
var phases: Array = []
var presentation := {}
var source_file := ""
var process_end_stamp := 0
var physics_start_stamp := 0
var physics_us := 0
var physics_steps := 0
var boundary_probe_us := 0
var work_begin := PackedInt64Array()
var work_process_end := PackedInt64Array()
var work_draw := PackedInt64Array()
var observer: Node
var frame_stages := {}
var detailed_frames: Array = []
var render_control := false
var render_controls: Array = []
var mesh_cache_control := false
var mesh_cache_result := {}

class BoundaryObserver extends Node:
	var lab: SceneTree
	func _process(_delta:float) -> void:
		lab.process_end_stamp=Time.get_ticks_usec()
		lab.work_process_end=lab.sample_work()
	func _physics_process(_delta:float) -> void:
		lab.physics_us+=Time.get_ticks_usec()-lab.physics_start_stamp
		lab.physics_steps+=1

func sample_work() -> PackedInt64Array:
	var began:=Time.get_ticks_usec()
	var result:=PackedInt64Array()
	if native_probe!=null and OS.get_thread_caller_id()==OS.get_main_thread_id():result=native_probe.thread_work()
	boundary_probe_us+=Time.get_ticks_usec()-began
	return result

func cycles(older:PackedInt64Array,newer:PackedInt64Array) -> float:
	return float(newer[0]-older[0]) if older.size()==2 and newer.size()==2 and older[0]>=0 and newer[0]>=older[0] else -1.0

func mark_physics() -> void:
	physics_start_stamp=Time.get_ticks_usec()

func mark_process() -> void:
	process_stamp=Time.get_ticks_usec()
	if diagnostic:work_begin=sample_work()

func mark_draw() -> void:
	draw_stamp=Time.get_ticks_usec()
	if diagnostic:work_draw=sample_work()

func mark_stage(_label: String, milliseconds: float) -> void:
	stage_ms+=milliseconds
	frame_stages[_label]=float(frame_stages.get(_label,0.0))+milliseconds

func sample_frame() -> void:
	if not recording:return
	var now:=Time.get_ticks_usec()
	if sample_count>=CAPACITY:
		overflow=true;return
	var i:=sample_count*COLUMNS.size()
	var point:Vector3=game.player.position
	travelled+=point.distance_to(previous);previous=point
	var invalid:bool=not playable() or game.session_menu.visible_ui() or game.player_hud.inventory_open or game.fly
	if invalid:invalid_play_frames+=1
	samples[i]=Engine.get_process_frames();samples[i+1]=now-start_stamp
	samples[i+2]=(now-stamp)/1000.0;samples[i+3]=stage_id
	samples[i+4]=point.x;samples[i+5]=point.y;samples[i+6]=point.z
	samples[i+7]=game.yaw;samples[i+8]=game.player.velocity.length()
	samples[i+9]=float(invalid);samples[i+10]=float(game.player.is_on_floor())
	samples[i+11]=(process_stamp-stamp)/1000.0
	samples[i+12]=(draw_stamp-process_stamp)/1000.0;samples[i+13]=(now-draw_stamp)/1000.0
	if diagnostic:
		samples[i+31]=(process_end_stamp-process_stamp)/1000.0
		samples[i+32]=(draw_stamp-process_end_stamp)/1000.0
		samples[i+33]=physics_us/1000.0;samples[i+34]=physics_steps
		samples[i+14]=RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		samples[i+15]=RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		samples[i+16]=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0
		samples[i+17]=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		samples[i+18]=Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		samples[i+19]=Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
		samples[i+20]=Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)
		samples[i+21]=game.terrain.backend.queued();samples[i+22]=stage_ms
		samples[i+23]=game.ground_cover.last_process_us/1000.0
		samples[i+24]=game.vegetation.renderer.stats.get("update_us",0)/1000.0
		samples[i+25]=float(game.zombies.update_phase_us.get("residency",0))/1000.0
		if native_probe!=null and OS.get_thread_caller_id()==OS.get_main_thread_id():
			var work:PackedInt64Array=native_probe.thread_work()
			samples[i+35]=cycles(prior_work,work_begin);samples[i+36]=cycles(work_begin,work_process_end)
			samples[i+37]=cycles(work_process_end,work_draw);samples[i+38]=cycles(work_draw,work)
			if work.size()==2 and prior_work.size()==2:
				if work[0]>=prior_work[0] and prior_work[0]>=0:samples[i+26]=work[0]-prior_work[0]
				if work[1]>=prior_work[1] and prior_work[1]>=0:samples[i+27]=(work[1]-prior_work[1])/1000.0
			prior_work=work
		# Bounded worst-frame detail; never runs in qualification mode. Native
		# batch uploads/retirement are separate from ground_cover.gd's own timer.
		if detailed_frames.size()<24 or samples[i+2]>float(detailed_frames.back().frame_ms):
			var batches:Array=[]
			for batch in game.ground_cover.batches:batches.append(batch.render_frame_profile())
			var owners:Dictionary={}
			for pair in [["blocks",game.structures.blocks],["model_horizon",game.structures._model_horizon],["resident_lights",game.structures.resident_lights]]:
				if is_instance_valid(pair[1]) and pair[1].has_method("process_frame_profile"):owners[pair[0]]=pair[1].process_frame_profile()
			detailed_frames.append({"frame":samples[i],"frame_ms":samples[i+2],"stages_ms":frame_stages.duplicate(),"cover_batches":batches,"native_process":owners,"zombie_phases_us":game.zombies.update_phase_us.duplicate()})
			detailed_frames.sort_custom(func(a,b):return a.frame_ms>b.frame_ms)
			if detailed_frames.size()>24:detailed_frames.pop_back()
	samples[i+29]=Engine.max_fps;samples[i+30]=DisplayServer.window_get_vsync_mode()
	samples[i+28]=Time.get_ticks_usec()-now+boundary_probe_us
	stamp=now;stage_ms=0.0;frame_stages.clear();physics_us=0;physics_steps=0;boundary_probe_us=0;sample_count+=1

func frozen_render_control() -> void:
	# Explicit post-route counterfactual, not gameplay acceptance. Hold pose,
	# simulation and geometry while varying only the root's render scale.
	game.process_mode=Node.PROCESS_MODE_DISABLED;Engine.time_scale=0.0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for order in 2:
		for scale_value:float in ([1.0,0.5,0.5,1.0] if order==0 else [0.5,1.0,1.0,0.5]):
			root.scaling_3d_scale=scale_value
			for warm_frame in 48:await RenderingServer.frame_post_draw
			var gpu:=PackedFloat64Array();var wall:=PackedFloat64Array();var draws:=PackedFloat64Array();var primitives:=PackedFloat64Array()
			var prior:=Time.get_ticks_usec()
			for frame in 96:
				await RenderingServer.frame_post_draw
				var now:=Time.get_ticks_usec();wall.append((now-prior)/1000.0);prior=now
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
				draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
				primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			render_controls.append({"order":order,"scale":scale_value,"gpu_ms":gpu,"frame_ms":wall,"draw_calls":draws,"primitives":primitives})
	root.scaling_3d_scale=1.0;Engine.time_scale=1.0;game.process_mode=Node.PROCESS_MODE_INHERIT

func compare_mesh_cache() -> void:
	# Same rendered scene and identical isolated buffers/meshes. Only whether
	# Godot has a CPU copy differs. Never inspect individual baseline transforms:
	# that getter itself creates the CPU copy and would destroy this control.
	game.process_mode=Node.PROCESS_MODE_DISABLED;Engine.time_scale=0.0
	var original:MultiMesh
	for page in game.ground_cover.batches[2].get_children():
		if page is MultiMeshInstance3D and page.multimesh.instance_count>0:original=page.multimesh;break
	if original==null:failures.append("Mesh-cache control needs a real grass page");return
	var buffer:=original.buffer
	var meshes:Array[Mesh]=[original.mesh,original.mesh.duplicate()]
	var variants:Array[MultiMesh]=[]
	var integrity:Array=[]
	for cached in [false,true]:
		var multi:=MultiMesh.new();multi.transform_format=MultiMesh.TRANSFORM_3D
		multi.use_custom_data=original.use_custom_data;multi.use_colors=original.use_colors
		multi.mesh=meshes[0];multi.instance_count=original.instance_count
		multi.custom_aabb=original.custom_aabb
		if cached:multi.set_instance_transform(0,Transform3D.IDENTITY)
		multi.buffer=buffer;variants.append(multi)
		# get_buffer returns bytes without creating the per-instance CPU cache.
		integrity.append(multi.buffer==buffer)
	var windows:Array=[]
	for cached in [false,true,true,false,true,false,false,true]:
		var selected:MultiMesh=variants[1 if cached else 0]
		var elapsed:=PackedFloat64Array()
		for frame in 64:
			await process_frame
			var began:=Time.get_ticks_usec()
			selected.mesh=meshes[(frame+1)%2]
			elapsed.append((Time.get_ticks_usec()-began)/1000.0)
		windows.append({"cached":cached,"switch_ms":elapsed})
	for multi in variants:integrity.append(multi.buffer==buffer)
	var resident_bytes:=0
	for batch in game.ground_cover.batches:
		for page in batch.get_children():
			if page is MultiMeshInstance3D:resident_bytes+=page.multimesh.instance_count*(64 if page.multimesh.use_custom_data else 48)
	mesh_cache_result={"windows":windows,"byte_identity":integrity,"instances":original.instance_count,"buffer_bytes":buffer.size()*4,"all_cover_resident_buffer_bytes":resident_bytes,"scope":"Same background scene; two non-visible MultiMeshes with identical mesh data, bounds, buffers and instance counts. Cache enabled with one pre-upload transform write. Full-buffer getters outside timings do not create the CPU cache. Only mesh assignment is timed; no gameplay or GPU-time pass inferred."}
	if not integrity.all(func(value):return value):failures.append("Mesh cache changed instance bytes")
	Engine.time_scale=1.0;game.process_mode=Node.PROCESS_MODE_INHERIT

func measure(label:String,duration:float,turn_rate:float=0.0) -> void:
	stage_id=phases.size()
	var first:=sample_count
	var began:=Time.get_ticks_usec()
	var last:=began
	while Time.get_ticks_usec()-began<int(duration*1000000) and not overflow:
		game.app_focused=true
		var now:=Time.get_ticks_usec()
		game.yaw+=turn_rate*(now-last)/1000000.0;game.player.rotation.y=game.yaw;last=now
		await RenderingServer.frame_post_draw
	phases.append({"id":stage_id,"label":label,"first":first,"end":sample_count})

func fail_setup(reason:String) -> void:
	failures.append(reason);setup_failed=true
	await finish_lab()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):output=arg.trim_prefix("--check-evidence-dir=")
		if arg.begins_with("--gameplay-source-slot="):slot=arg.trim_prefix("--gameplay-source-slot=")
		if arg.begins_with("--lab-seconds="):seconds=float(arg.trim_prefix("--lab-seconds="))
		if arg.begins_with("--lab-pacing="):pacing=arg.trim_prefix("--lab-pacing=")
		if arg=="--lab-diagnostic":diagnostic=true
		if arg=="--lab-render-control":render_control=true
		if arg=="--lab-mesh-cache-control":mesh_cache_control=true
	if output.is_empty() or not slot.is_valid_identifier() or seconds<30 or seconds>120 or not pacing in ["uncapped","cap61"]:
		push_error("Use admitted walking lab with 30..120 seconds and uncapped/cap61 pacing");quit(1);return
	source_file="user://worlds/"+slot+".trw"
	if not FileAccess.file_exists(source_file):await fail_setup("Source save unavailable");return
	source_hash=FileAccess.get_sha256(source_file)
	samples.resize(CAPACITY*COLUMNS.size());samples.fill(-1.0)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot="+slot,"--snapshot-readonly","--temporary","--no-derived-cache","--ground-cover","--gameplay-construction","--actors","--vehicle-fleet"]),true)
	game=WalkingWorld.new();game.name="TerraForest";game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
	if not await ready_within(func():return not game.loading_active and not game.needs_floor_spawn,90):await fail_setup("Source world load timeout");return
	game.session_menu.set_open(true)
	if not await ready_within(playable,90):await fail_setup("Arrival timeout");return
	game.teleport(Vector3(1740,0,1700))
	if not await ready_within(playable,90):await fail_setup("Outdoor destination timeout");return
	if not await ready_within(func():return game.ecosystem.coverage_status().ready,45):await fail_setup("Forest coverage timeout");return
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game._clear_motion();game.fly=false;game.pitch=deg_to_rad(-12.0);game.camera.rotation.x=game.pitch
	await ready_within(func():return false,6)
	game.yaw=approach_heading();game.player.rotation.y=game.yaw
	observe_preparation("settled_outdoor_route")
	if not playable() or not game.player.is_on_floor():await fail_setup("Invalid or ungrounded starting pose");return
	var restore:Callable=root.get_node("WorldSession")._restore_presentation.call_deferred
	if root.focus_entered.is_connected(restore):root.focus_entered.disconnect(restore)
	game.max_fps=0 if pacing=="uncapped" else 61;game.background_fps=game.max_fps;Engine.max_fps=game.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if diagnostic:
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		game.ground_cover.profiling_enabled=true;game.vegetation.renderer.profiling_enabled=true;game.zombies.profiling_enabled=true
		game.terrain.stage_measured.connect(mark_stage)
		if ClassDB.class_exists("NativeResourceUsage"):native_probe=ClassDB.instantiate("NativeResourceUsage")
		game.structures.blocks.set_process_profiling_enabled(true)
		observer=BoundaryObserver.new();observer.lab=self;observer.process_priority=1000000;observer.process_physics_priority=1000000;root.add_child(observer)
		physics_frame.connect(mark_physics)
	presentation=preload("res://addons/presentation/fullscreen_policy.gd").measurement(root)
	presentation["refresh_hz"]=DisplayServer.screen_get_refresh_rate()
	presentation["renderer"]=RenderingServer.get_current_rendering_method()
	presentation["adapter"]=RenderingServer.get_video_adapter_name()
	presentation["engine"]=Engine.get_version_info()
	presentation["scope"]="Engine post-draw cadence, not physical display presentation. Isolated desktop differs from interactive fullscreen."
	process_frame.connect(mark_process);RenderingServer.frame_pre_draw.connect(mark_draw);RenderingServer.frame_post_draw.connect(sample_frame)
	physics_frame.connect(physics_tick)
	game.session_menu.set_open(false)
	# One untimed frame establishes the boundary; every subsequent interval counts.
	await RenderingServer.frame_post_draw
	previous=game.player.position;capture_start=previous;stamp=Time.get_ticks_usec();start_stamp=stamp;stage_ms=0.0
	recording=true;key(KEY_W,true)
	await measure("walk",seconds*14.0/30.0)
	await measure("walk_turn",seconds*10.0/30.0,-0.10)
	key(KEY_W,false);key(KEY_D,true)
	await measure("strafe",seconds*6.0/30.0)
	recording=false;key(KEY_D,false)
	if physics_frame.is_connected(physics_tick):physics_frame.disconnect(physics_tick)
	if render_control:await frozen_render_control()
	if mesh_cache_control:await compare_mesh_cache()
	await finish_lab()

func finish_lab() -> void:
	recording=false
	if physics_frame.is_connected(physics_tick):physics_frame.disconnect(physics_tick)
	if physics_frame.is_connected(mark_physics):physics_frame.disconnect(mark_physics)
	if process_frame.is_connected(mark_process):process_frame.disconnect(mark_process)
	if RenderingServer.frame_pre_draw.is_connected(mark_draw):RenderingServer.frame_pre_draw.disconnect(mark_draw)
	if RenderingServer.frame_post_draw.is_connected(sample_frame):RenderingServer.frame_post_draw.disconnect(sample_frame)
	if is_instance_valid(observer):observer.free()
	if not source_hash.is_empty() and FileAccess.get_sha256(source_file)!=source_hash:failures.append("Canonical save changed")
	if overflow:failures.append("Recorder capacity exceeded; run invalid")
	if invalid_play_frames>0:failures.append("Route entered invalid gameplay state")
	if not setup_failed and travelled<40.0:failures.append("Insufficient physical traversal")
	samples.resize(sample_count*COLUMNS.size())
	var raw:=samples.to_byte_array()
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(raw)
	var raw_hash:=digest.finish().hex_encode()
	var compressed:=raw.compress(FileAccess.COMPRESSION_DEFLATE)
	if compressed.size()>1536*1024:push_error("Evidence exceeds admitted binary bound");quit(1);return
	FileAccess.open(output.path_join("walking.frames.zlib"),FileAccess.WRITE).store_buffer(compressed)
	var result:Dictionary={"schema":1,"columns":COLUMNS,"dtype":"little-endian float64","frames":sample_count,"raw_bytes":raw.size(),"sha256":raw_hash,"diagnostic":diagnostic,"pacing":pacing,"requested_seconds":seconds,"slot":slot,"save_sha256":source_hash,"failures":failures,"overflow":overflow,"travelled_m":travelled,"start":str(capture_start),"end":str(previous),"physics_frames":physics_frames,"grounded_frames":grounded_frames,"invalid_play_frames":invalid_play_frames,"phases":phases,"preparation":preparation,"presentation":presentation,"route":"One setup teleport to (1740,0,1700); normal pause while settling; choose clear departure; W walk, W turn, D strafe; no teleport, actor/collision/streaming suppression during measurement.","budget_ms":1000.0/61.0,"critical_ms":1000.0/60.0,"headroom_ms":0.8*1000.0/61.0,"notes":"Missing diagnostic counters are -1; delayed GPU/render values are not matched to the current frame. Thread CPU time is coarse. Phase wall times overlap subsystem timings; never sum them. All walking frames retained; no outlier removal."}
	result["worst_frame_details"]=detailed_frames
	result["post_route_render_control"]=render_controls
	result["mesh_cache_control"]=mesh_cache_result
	FileAccess.open(output.path_join("walking.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	if is_instance_valid(game):game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
	print("WALKING_LAB_COMPLETE frames=",sample_count," validity_failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
