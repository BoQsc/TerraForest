# SPDX-License-Identifier: 0BSD
extends SceneTree
# Measure rendered frames only: no images, GPU readback, logging or disk writes
# during a sample. Measurement validity is separate from meeting the 60 FPS goal.
var game:Node
var output:="res://reports/entry_fly_in/performance"
var slot:="Exploration_1703_8f8d4c8f"
var original_hash:=""
var samples:Dictionary={}
var focused_frames:Dictionary={}
var previous_usec:=0
var first_person_usec:=0
var phase_override:=""
var measuring:=true
var valid:=true
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func wait_for(predicate:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		if is_instance_valid(game):game.app_focused=true
		await process_frame
	return predicate.call()
func frame_drawn()->void:
	var now:=Time.get_ticks_usec()
	var interval:float=(now-previous_usec)/1000.0 if previous_usec>0 else 0.0
	previous_usec=now
	if not measuring or not is_instance_valid(game) or interval<=0:return
	var entry=game.player_view.entry
	if entry.starts==0:return
	var phase:=phase_override
	if entry.active:phase="entry_initial" if entry.starts==1 else "entry_warm"
	elif phase.is_empty():
		if first_person_usec==0:first_person_usec=now
		phase="first_person_after_entry" if now-first_person_usec<5000000 else "first_person_settled"
	if not samples.has(phase):samples[phase]=[]
	if root.has_focus():focused_frames[phase]=int(focused_frames.get(phase,0))+1
	var viewport:=root.get_viewport_rid()
	samples[phase].append([interval,RenderingServer.viewport_get_measured_render_time_gpu(viewport),RenderingServer.viewport_get_measured_render_time_cpu(viewport)])
func summary(rows:Array)->Dictionary:
	var frame:Array[float]=[];var gpu:Array[float]=[];var cpu:Array[float]=[]
	var total:=0.0;var over33:=0;var over50:=0;var over100:=0
	for row:Array in rows:
		frame.append(row[0]);gpu.append(row[1]);cpu.append(row[2]);total+=row[0]
		if row[0]>33.34:over33+=1
		if row[0]>50.0:over50+=1
		if row[0]>100.0:over100+=1
	frame.sort();gpu.sort();cpu.sort()
	var p95:=int(ceil(frame.size()*.95))-1;var p99:=int(ceil(frame.size()*.99))-1
	return {"frames":frame.size(),"sample_seconds":total/1000.0,"average_fps":frame.size()*1000.0/total,"frame_median_ms":frame[frame.size()/2],"frame_p95_ms":frame[p95],"frame_p99_ms":frame[p99],"frame_max_ms":frame[-1],"frames_over_33ms":over33,"frames_over_50ms":over50,"frames_over_100ms":over100,"gpu_p95_ms":gpu[p95],"render_cpu_p95_ms":cpu[p95]}
func run()->void:
	var args:=PackedStringArray(["--temporary","--snapshot-readonly","--entry-fly-in","--gameplay-construction","--ground-cover","--actors","--vehicle-fleet"])
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--entry-output="):output=arg.trim_prefix("--entry-output=")
		elif arg.begins_with("--entry-slot="):slot=arg.trim_prefix("--entry-slot=")
		elif arg.begins_with("--derived-cache="):args.append(arg)
	var path:="user://worlds/"+slot+".trw"
	if not preload("res://demo/world_launch.gd").valid_slot(slot) or not FileAccess.file_exists(path):push_error("Missing valid read-only performance fixture");quit(1);return
	original_hash=FileAccess.get_sha256(path);args.append("--world-slot="+slot)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(args,true)
	DirAccess.make_dir_recursive_absolute(output)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.max_fps=60;game.player_view.settings_path=""
	root.add_child(game)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	RenderingServer.frame_post_draw.connect(frame_drawn)
	valid=await wait_for(func():return first_person_usec>0 or (not game.loading_active and not game.player_view.entry.pending and game.player_view.entry.starts==0),160)
	valid=valid and game.player_view.entry.starts==1 and game.terrain.latest_error.is_empty()
	var initial_completed:bool=is_equal_approx(game.player_view.entry.elapsed,3.0)
	var warm_elapsed:=0.0
	if valid:
		await wait_for(func():return Time.get_ticks_usec()-first_person_usec>=10000000,12)
		phase_override="first_person_after_warm"
		valid=game.player_view.entry.begin()
		if valid:
			await wait_for(func():return not game.player_view.entry.active,5)
			warm_elapsed=game.player_view.entry.elapsed
			var end:=Time.get_ticks_usec()+5000000
			await wait_for(func():return Time.get_ticks_usec()>=end,7)
	measuring=false;RenderingServer.frame_post_draw.disconnect(frame_drawn)
	var result:={"valid":valid,"slot":slot,"read_only":true,"cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"viewport":str(root.size),"gpu":RenderingServer.get_video_adapter_name(),"terrain_roots":game.terrain.root_coverage,"forest_owners":game.ecosystem.resident.size(),"initial_completed_three_seconds":initial_completed,"warm_elapsed_seconds":warm_elapsed,"warm_completed_three_seconds":is_equal_approx(warm_elapsed,3.0),"focused_window_frames":focused_frames,"scope":"Single source process; automatic entry, 5s immediate FP, 5s settled FP, warm entry attempt, 5s FP. A warm attempt may end early on nearby geometry and is not a matched full-flight comparison. No screenshot/readback/compression during measurement; no movement inputs. Loading boundary and render-time query overhead included. Not installed-build or traversal qualification.","phases":{},"raw_frame_ms_gpu_ms_render_cpu_ms":samples}
	for phase:String in samples:
		if samples[phase].size()>0:result.phases[phase]=summary(samples[phase])
	for phase:String in ["entry_initial","first_person_after_entry","first_person_settled","entry_warm","first_person_after_warm"]:
		valid=valid and result.phases.has(phase) and result.phases.get(phase,{}).get("frames",0)>=20
	valid=valid and FileAccess.get_sha256(path)==original_hash
	result.valid=valid
	FileAccess.open(output.path_join("timing.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("ENTRY_PERFORMANCE ",JSON.stringify(result.phases))
	game.player_view.entry.finish();game.shutdown_requested=true
	await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("ENTRY_PERFORMANCE valid=",str(valid).to_lower());quit(0 if valid else 1)
