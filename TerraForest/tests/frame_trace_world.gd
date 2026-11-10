# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var output:=""
var slot:=""
var samples:Array[Dictionary]=[]
var previous:=0
var label:="loading"
var manual_save:Dictionary={"requested":false,"completed":false,"success":false}
var light_abba:=false
var repeat_light_setters:=false
var light_phases:Array[Dictionary]=[]
var render_probe:=false
var render_probe_result:Dictionary={}
var outdoor_result:Dictionary={}
var destruction_result:Dictionary={}
var occlusion_result:Dictionary={}
var collision_piece_triangles:=0
var collision_configured:=false
var collision_stages:Dictionary={}
var collision_stages_dropped:=0
var world_opened_us:=0
var world_ready_ms:=0.0
var gpu_timers:=true
var normal_window:=false

func collision_stage(stage_name:String,milliseconds:float)->void:
	if stage_name not in ["collision node attach","collision piece","staging frame","atomic publish","retire collision/mesh"]:return
	var key:=label+":"+stage_name
	if not collision_stages.has(key):collision_stages[key]=[]
	if collision_stages[key].size()<20000:collision_stages[key].append(milliseconds)
	else:collision_stages_dropped+=1

func collision_census(entries:Dictionary)->Dictionary:
	# Post-measurement census; hashing full geometry must never enter frame timings.
	var result:Dictionary={"shapes":0,"triangles":0,"largest_piece":0,"geometry":{}}
	for key:Variant in entries:
		var entry:Dictionary=entries[key]
		if entry.has("bricks"):
			var child:=collision_census(entry.bricks)
			result.shapes+=child.shapes;result.triangles+=child.triangles
			result.largest_piece=maxi(result.largest_piece,child.largest_piece)
			for brick:String in child.geometry:result.geometry[str(key)+"/"+brick]=child.geometry[brick]
			continue
		if not is_instance_valid(entry.get("body")):continue
		var faces:=PackedVector3Array()
		for shape_node:Node in entry.body.get_children():
			if not shape_node is CollisionShape3D:continue
			var piece:PackedVector3Array=shape_node.shape.get_faces()
			faces.append_array(piece);result.shapes+=1
			result.triangles+=piece.size()/3
			result.largest_piece=maxi(result.largest_piece,piece.size()/3)
		var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256)
		hashing.update(faces.to_byte_array());result.geometry[str(key)]=hashing.finish().hex_encode()
	return result
func repeat_lights()->void:
	if not repeat_light_setters or not is_instance_valid(game):return
	for light:Node in game.structures.resident_lights.get_children():
		if light is OmniLight3D and light.visible:
			light.global_position=light.global_position
			light.light_energy=light.light_energy
func _initialize()->void:
	normal_window="--trace-normal-window" in OS.get_cmdline_user_args()
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	gpu_timers=not "--trace-without-gpu-timers" in OS.get_cmdline_user_args()
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--trace-collision-piece-triangles="):collision_piece_triangles=int(arg.get_slice("=",1))
	var legacy_cover:bool="--trace-legacy-cover" in OS.get_cmdline_user_args()
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":
			ProjectSettings.set_setting("terraforest/offscreen_session",true)
			if collision_piece_triangles>0:
				collision_configured=node.terrain.backend.configure_collision_piece_size(collision_piece_triangles)
				node.terrain.stage_measured.connect(collision_stage)
		if node.name=="CanopyShadows" and "--trace-legacy-canopy-snapshot" in OS.get_cmdline_user_args():node.legacy_snapshot=true
		if legacy_cover and node.get_script()!=null and node.get_script().resource_path=="res://addons/world_ecosystem/ground_cover.gd":node.render_partition_subdivisions=1)
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--trace-world-slot="):slot=arg.trim_prefix("--trace-world-slot=")
		if arg.begins_with("--trace-world-output="):output=arg.trim_prefix("--trace-world-output=")
	run.call_deferred()
func update_test_focus()->void:
	if not is_instance_valid(game):return
	if normal_window:
		var focused:=DisplayServer.window_is_focused()
		if game.app_focused!=focused:
			game.app_focused=focused
			game._refresh_frame_cap()
	else:game.app_focused=true
func wait_for(predicate:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline and not predicate.call():
		update_test_focus()
		await process_frame
	return predicate.call()
func frame()->void:
	var now:=Time.get_ticks_usec()
	if previous>0:
		var sample:Dictionary={"phase":label,"frame_ms":(now-previous)/1000.0,"frame":Engine.get_process_frames(),"drawn_frame":Engine.get_frames_drawn(),"at_us":now}
		sample.gpu_ms=RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()) if gpu_timers else -1.0
		sample.render_cpu_ms=RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()) if gpu_timers else -1.0
		sample.render_setup_cpu_ms=RenderingServer.get_frame_setup_time_cpu() if gpu_timers else -1.0
		sample.draw_calls=Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		sample.fps_cap=Engine.max_fps;sample.vsync=DisplayServer.window_get_vsync_mode()
		sample.window_focused=DisplayServer.window_is_focused()
		sample.window_mode=DisplayServer.window_get_mode()
		if collision_piece_triangles>0:
			sample.physics_monitor_ms=Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0
		samples.append(sample)
	previous=now
func source_sha256(path:String)->String:
	var code:String=load(path).source_code
	# Compiled exports may not expose source; an empty-text hash is not identity.
	return code.sha256_text() if not code.is_empty() else ""
func run()->void:
	if not slot.begins_with("StartupBench_FPS_") or not slot.is_valid_identifier() or output.is_empty():quit(2);return
	var original_occlusion:bool=root.use_occlusion_culling
	DirAccess.make_dir_recursive_absolute(output)
	# The recorder-off control must retain the same root GPU timing instrumentation.
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),gpu_timers)
	RenderingServer.frame_post_draw.connect(frame)
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	var browser=current_scene
	if not await wait_for(func():return not browser.library.loading,60):quit(1);return
	var command:Dictionary=preload("res://demo/world_launch.gd").command(slot,false,29,1703,true)
	world_opened_us=Time.get_ticks_usec()
	browser._open_game(command.args)
	if not await wait_for(func():return is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn",90):quit(1);return
	game=current_scene;update_test_focus()
	if normal_window:
		root.grab_focus()
		if not await wait_for(func():return DisplayServer.window_is_focused(),8):
			push_error("Foreground frame capture could not acquire OS window focus; no gameplay comparison is valid")
			quit(1);return
		update_test_focus()
	if not "--trace-normal-window" in OS.get_cmdline_user_args():game.background_fps=60
	game.background_hud_updates="--trace-legacy-hidden-hud" in OS.get_cmdline_user_args()
	if not await wait_for(func():return game.startup_complete,90):quit(1);return
	if "--trace-no-first-person-depth" in OS.get_cmdline_user_args():game.first_person_view.set_enabled(false,false)
	if "--trace-uncapped" in OS.get_cmdline_user_args():
		# The session normally restores VSync on focus. This diagnostic explicitly
		# owns uncapped pacing; retain normal production focus policy elsewhere.
		var restore:Callable=root.get_node("WorldSession")._restore_presentation.call_deferred
		if root.focus_entered.is_connected(restore):root.focus_entered.disconnect(restore)
		game.max_fps=0;game.background_fps=0;Engine.max_fps=0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if not await wait_for(func():return game.startup_complete and not game.loading_active and not game.player_view.entry.blocks_actions(),120):quit(1);return
	if "--trace-legacy-owner-bounds" in OS.get_cmdline_user_args():
		game.ecosystem._exclusion_index=null
		game.ground_cover.boulders._exclusion_index=null
	world_ready_ms=(Time.get_ticks_usec()-world_opened_us)/1000.0
	# Registration occurs asynchronously during startup; replace only after ready.
	var legacy_structure_capture:bool="--trace-legacy-structure-capture" in OS.get_cmdline_user_args()
	if legacy_structure_capture:game.persistence._providers["structures"].capture=game.structures.capture_storage_snapshot
	var trace=root.get_node_or_null("WorldSession/FrameTrace")
	var initializations:Array=[]
	for zombie:Node in game.zombies.residents:initializations.append(zombie.initialization_us.duplicate())
	var initial_yaw:float=game.yaw
	label="arrival_idle"
	var short:bool="--trace-short" in OS.get_cmdline_user_args()
	var hidden_hud_text:String=game.hud.text
	var hud_was_hidden:bool=not game.hud.is_visible_in_tree()
	await wait_for(func():return false,12 if short else 20)
	var hidden_hud_stable:bool=not hud_was_hidden or game.background_hud_updates or game.hud.text==hidden_hud_text
	if "--trace-player-abba" in OS.get_cmdline_user_args():
		var original_feel:bool=game.player_view.feel_enabled
		for motion:String in ["idle","turn"]:
			for setting:String in ["on_a","off_b","off_b2","on_a2"]:
				label="player_warmup"
				game.player_view.set_feel_enabled(setting.begins_with("on"),false)
				game.yaw=initial_yaw
				await wait_for(func():return false,1)
				label="player_"+motion+"_"+setting
				var began:=Time.get_ticks_msec()
				while Time.get_ticks_msec()-began<6000:
					update_test_focus()
					if motion=="turn":game.yaw=initial_yaw+float(Time.get_ticks_msec()-began)*TAU/30000.0
					await process_frame
		game.player_view.set_feel_enabled(original_feel,false)
		game.yaw=initial_yaw
	if "--trace-block-occlusion" in OS.get_cmdline_user_args() and not "--trace-outdoor-cover" in OS.get_cmdline_user_args():
		occlusion_result=await load(get_script().resource_path.get_base_dir().path_join("render_occlusion_probe.gd")).new().run(self,game,output)
	if "--trace-outdoor-cover" in OS.get_cmdline_user_args():
		outdoor_result=await load(get_script().resource_path.get_base_dir().path_join("cover_outdoor_probe.gd")).new().run(self,game,output)
		if "--trace-block-occlusion" in OS.get_cmdline_user_args() and outdoor_result.ok:
			occlusion_result=await load(get_script().resource_path.get_base_dir().path_join("render_occlusion_probe.gd")).new().run(self,game,output,"outdoor_occlusion")
	for arg:String in OS.get_cmdline_user_args():
		if not arg.begins_with("--trace-render-partition="):continue
		label="render_preparation"
		var original_lod:float=root.mesh_lod_threshold
		if "--trace-render-full-detail" in OS.get_cmdline_user_args():root.mesh_lod_threshold=0.0
		var partition=load(get_script().resource_path.get_base_dir().path_join("render_partition_probe.gd")).new()
		partition.prepare(game,float(arg.get_slice("=",1)))
		render_probe=true;RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		render_probe_result={"span":float(arg.get_slice("=",1)),"mesh_lod_threshold":root.mesh_lod_threshold,"original_batches":partition.originals.size(),"replacement_batches":partition.replacements.size(),"instances":partition.instance_count,"unchanged":true}
		for phase:String in ["original_a","partitioned_b","partitioned_b2","original_a2"]:
			partition.set_partitioned(phase.begins_with("partitioned"));label="render_warmup"
			await wait_for(func():return false,2)
			label="render_"+phase;print("RENDER_PARTITION_PHASE begin=",label)
			await wait_for(func():return false,5)
			print("RENDER_PARTITION_PHASE end=",label)
			render_probe_result.unchanged=render_probe_result.unchanged and partition.unchanged()
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(label+".png"))
		partition.release();root.mesh_lod_threshold=original_lod
	light_abba="--trace-light-abba" in OS.get_cmdline_user_args()
	if light_abba:
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
		process_frame.connect(repeat_lights)
		for phase:String in ["guarded_a","repeated_b","repeated_b2","guarded_a2"]:
			repeat_light_setters=phase.begins_with("repeated")
			label="light_warmup"
			await wait_for(func():return false,1)
			label="lights_"+phase
			await wait_for(func():return false,5)
			light_phases.append({"phase":phase,"lights":game.structures.resident_lights.statistics()})
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(label+".png"))
		repeat_light_setters=false;process_frame.disconnect(repeat_lights)
	if "--trace-save" in OS.get_cmdline_user_args():
		label="save_during_play"
		if trace!=null:trace.mark("explicit normal save during gameplay")
		manual_save.requested=true
		var saved_callback:Callable=func(success:bool):manual_save.completed=true;manual_save.success=success
		game.terrain.save_completed.connect(saved_callback,CONNECT_ONE_SHOT)
		game.terrain.changed_since_save=true;game.terrain.save_world()
		manual_save.capture=game.persistence.last_capture.duplicate(true)
		var structure_payload:RefCounted=game.structures._cached_save
		await wait_for(func():return manual_save.completed,20)
		if structure_payload!=null:manual_save.structure_capture_stats=structure_payload.stats()
	if "--trace-destruction-load" in OS.get_cmdline_user_args():
		destruction_result=await load(get_script().resource_path.get_base_dir().path_join("destruction_load_probe.gd")).new().run(self,game,output)
	label="turning"
	var turn_started:=Time.get_ticks_msec()
	var deadline:=turn_started+(5000 if short else 30000)
	while Time.get_ticks_msec()<deadline:
		update_test_focus();game.yaw=initial_yaw+(Time.get_ticks_msec()-turn_started)*TAU/30000.0
		await process_frame
	label="settled_idle"
	await wait_for(func():return false,5 if short else 15)
	if trace!=null:
		trace.mark("end of fresh-world observation")
		await wait_for(func():return false,3)
	label="test_screenshot"
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("arrival.png"))
	RenderingServer.frame_post_draw.disconnect(frame)
	# UI regression checks happen after the timed gameplay and screenshots.
	var prior_hud_visibility:bool=game.hud.visible
	game.hud.show();game.hud_timer=0.0
	await process_frame;await process_frame
	var visible_hud_updated:bool=game.hud.text.begins_with("Terrain Rewrite") and not game.frame_samples.is_empty()
	game.hud.visible=prior_hud_visibility
	var record:Dictionary={"slot":slot,"samples":samples,"trace_enabled":trace!=null,"position":game.player.position,"temporary":game.temporary_world,"snapshot_readonly":game.terrain.backend.readonly_snapshot,"mouse_captures":preload("res://addons/world_runtime/mouse_ownership.gd").captures}
	record.debug_hud={"hidden_stable":hidden_hud_stable,"visible_updated":visible_hud_updated}
	record.initializations=initializations
	record.runtime_source_sha256={"zombie":source_sha256("res://addons/characters/runtime/zombie.gd"),"controller":source_sha256("res://demo/controller.gd")}
	for script:String in ["res://addons/vegetation/forest.gd","res://addons/vegetation/canopy_shadows.gd"]:record.runtime_source_sha256[script]=source_sha256(script)
	record.runtime_source_unavailable=[]
	for script:String in record.runtime_source_sha256:
		if record.runtime_source_sha256[script].is_empty():record.runtime_source_unavailable.append(script)
	record.gpu_timers=gpu_timers
	record.rendering_driver=RenderingServer.get_current_rendering_driver_name()
	record.rendering_method=RenderingServer.get_current_rendering_method()
	record.presentation={"requested_cap":game.max_fps,"effective_cap":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"refresh_hz":DisplayServer.screen_get_refresh_rate(),"hidden_hud_control":game.background_hud_updates}
	record.presentation.window=preload("res://addons/presentation/fullscreen_policy.gd").measurement(root)
	record.presentation.window_position=DisplayServer.window_get_position()
	record.presentation.background_cap=game.background_fps
	record.presentation.foreground_required="--trace-normal-window" in OS.get_cmdline_user_args()
	var unfocused_gameplay_frames:=0
	for sample:Dictionary in samples:
		if sample.phase not in ["loading","test_screenshot"] and not sample.window_focused:unfocused_gameplay_frames+=1
	record.presentation.unfocused_gameplay_frames=unfocused_gameplay_frames
	var pacing_mismatches:=0
	var uncapped:bool="--trace-uncapped" in OS.get_cmdline_user_args()
	for sample:Dictionary in samples:
		if sample.phase not in ["loading","test_screenshot"] and (sample.fps_cap!=(0 if uncapped else 60) or sample.vsync!=(DisplayServer.VSYNC_DISABLED if uncapped else DisplayServer.VSYNC_ENABLED)):pacing_mismatches+=1
	record.pacing_mismatches=pacing_mismatches
	record.uncapped_pacing_mismatches=pacing_mismatches if uncapped else 0
	if collision_piece_triangles>0:
		record.collision={"configured":collision_configured,"requested_triangles":collision_piece_triangles,"ready_ms":world_ready_ms,"stages":collision_stages,"stages_dropped":collision_stages_dropped,"census":collision_census(game.terrain.tiles),"resident_tiles":game.terrain.tiles.size(),"engine_static_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)}
	record.last_capture=game.persistence.last_capture.duplicate(true)
	record.manual_save=manual_save.duplicate()
	record.legacy_structure_capture=legacy_structure_capture
	if game.structures._cached_save!=null:record.structure_capture_stats=game.structures._cached_save.stats()
	record.cover_render=[]
	if not outdoor_result.is_empty():record.outdoor=outdoor_result
	if not destruction_result.is_empty():record.destruction=destruction_result
	if not occlusion_result.is_empty():record.occlusion=occlusion_result
	if game.structures.blocks.has_method("occlusion_stats"):record.block_occlusion=game.structures.blocks.occlusion_stats()
	for batch:Node in game.ground_cover.batches:record.cover_render.append(batch.render_stats())
	if render_probe:record.render_probe=render_probe_result
	if light_abba:record.light_phases=light_phases
	if trace!=null:record.trace_files=trace.written;record.trace_overhead_last_us=trace.overhead_us
	if "--trace-render-inventory" in OS.get_cmdline_user_args():
		# Diagnostic readbacks happen only after all frame observations are saved.
		var inventory:Dictionary=load(get_script().resource_path.get_base_dir().path_join("render_inventory.gd")).capture(game)
		FileAccess.open(output.path_join("render_inventory.json"),FileAccess.WRITE).store_string(JSON.stringify(inventory))
	game.yaw=initial_yaw;game.player.rotation.y=initial_yaw
	game.shutdown_requested=true
	var saved:bool=await game.terrain.shutdown_after_edits()
	game.free();await process_frame;await process_frame
	record.viewport_occlusion_restored=root.use_occlusion_culling==original_occlusion
	FileAccess.open(output.path_join("observation.json"),FileAccess.WRITE).store_string(JSON.stringify(record))
	var okay:bool=saved and record.mouse_captures==0 and (not manual_save.requested or manual_save.completed and manual_save.success)
	if normal_window:
		okay=okay and unfocused_gameplay_frames==0 and record.presentation.background_cap==15
		if unfocused_gameplay_frames>0:push_error("Foreground frame capture lost OS focus for %d gameplay frames"%unfocused_gameplay_frames)
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--trace-expected-driver="):okay=okay and record.rendering_driver==arg.get_slice("=",1) and record.rendering_method=="forward_plus"
	okay=okay and hidden_hud_stable and visible_hud_updated
	okay=okay and record.viewport_occlusion_restored and pacing_mismatches==0
	if collision_piece_triangles>0:okay=okay and collision_configured and collision_stages_dropped==0 and record.collision.census.shapes>0 and record.collision.census.largest_piece<=collision_piece_triangles
	if render_probe:okay=okay and render_probe_result.unchanged and render_probe_result.instances>0
	if not outdoor_result.is_empty():okay=okay and outdoor_result.ok
	if not destruction_result.is_empty():okay=okay and destruction_result.ok
	if not occlusion_result.is_empty():okay=okay and occlusion_result.ok
	var completion:=FileAccess.open(output.path_join("completion.json"),FileAccess.WRITE)
	if completion==null:
		push_error("Could not retain frame-trace completion receipt");quit(1);return
	completion.store_string(JSON.stringify({"schema":1,"slot":slot,"ok":okay,"shutdown_saved":saved}))
	completion.close()
	print("FRAME_TRACE_WORLD ok=",okay," slot=",slot);quit(0 if okay else 1)
