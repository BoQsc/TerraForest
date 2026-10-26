extends "res://tests/foundation_mining.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var total_commands:=0
var observations:Array[Dictionary]=[]
var visual_mode:=false
var soak_rounds:=3
var observer_operations:Array[Dictionary]=[]
var hitches:Array[Dictionary]=[]
var runtime_frames:Array[float]=[]
var pipeline_counts:PackedInt64Array=[]
var pipeline_changes:Array[Dictionary]=[]
func frame()->void:
	var elapsed:=Time.get_ticks_usec()-previous_us
	var counts:=PackedInt64Array()
	for monitor:int in [Performance.PIPELINE_COMPILATIONS_CANVAS,Performance.PIPELINE_COMPILATIONS_MESH,Performance.PIPELINE_COMPILATIONS_SURFACE,Performance.PIPELINE_COMPILATIONS_DRAW,Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:counts.append(int(Performance.get_monitor(monitor)))
	if counts!=pipeline_counts:pipeline_changes.append({"time_us":Time.get_ticks_usec(),"counts":counts});pipeline_counts=counts
	if previous_us>0 and phase!="startup":runtime_frames.append(elapsed/1000.0)
	if previous_us>0 and elapsed>40000:
		hitches.append({"time_us":Time.get_ticks_usec(),"phase":phase,"frame_ms":elapsed/1000.0,"ground_ms":game.ground_cover.last_process_us/1000.0,"water_ms":game.lakes.last_process_us/1000.0,"focused":game.app_focused,"pipeline_counts":pipeline_counts})
	super.frame()
func begin_phase(label:String)->void:
	var began:=Time.get_ticks_usec()
	super.begin_phase(label)
	observer_operations.append({"operation":"begin "+label,"time_us":began,"ms":(Time.get_ticks_usec()-began)/1000.0})
func end_phase()->void:
	var began:=Time.get_ticks_usec()
	super.end_phase()
	observer_operations.append({"operation":"end "+phase,"time_us":began,"ms":(Time.get_ticks_usec()-began)/1000.0})
func check(ok:bool,label:String)->void:
	var began:=Time.get_ticks_usec()
	super.check(ok,label)
	observer_operations.append({"operation":"check "+label,"time_us":began,"ms":(Time.get_ticks_usec()-began)/1000.0})
func mouse(button:int,pressed:bool)->void:
	var began:=Time.get_ticks_usec()
	var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=pressed
	Input.parse_input_event(event)
	observer_operations.append({"operation":"mouse","time_us":began,"ms":(Time.get_ticks_usec()-began)/1000.0})
func select_tool(slot:int,mode:int=-1)->void:
	var began:=Time.get_ticks_usec()
	game.session_menu.activate_developer_slot(slot)
	observer_operations.append({"operation":"select tool","time_us":began,"ms":(Time.get_ticks_usec()-began)/1000.0})
	if mode>=0:
		began=Time.get_ticks_usec()
		game._set_player_tool_mode(false,false,mode)
		observer_operations.append({"operation":"tool mode","time_us":began,"ms":(Time.get_ticks_usec()-began)/1000.0})
func submit(packet:PackedByteArray)->bool:
	var before:=edits.size()
	var began:=Time.get_ticks_usec()
	var accepted:bool=game.terrain.edit(packet,Vector3.ZERO,Vector3.ZERO)
	var elapsed:float=(Time.get_ticks_usec()-began)/1000.0
	if elapsed>10:observer_operations.append({"operation":"submit","time_us":began,"ms":elapsed})
	if not accepted:return false
	total_commands+=1
	if not await until(func():return not game.terrain.pending_edit or not game.terrain.world_ready,60):return false
	if not game.terrain.world_ready:return false
	return await until(func():return edits.size()>before,2)
func aim(point:Vector3)->bool:
	height_value=NAN;height_token+=1;game.terrain.request_height(point,height_token)
	if not await until(func():return is_finite(height_value),5):return false
	point.y=height_value
	game.player.position=point+Vector3(0,8,12);game.camera.look_at(point)
	game.terrain.set_interaction_target(point)
	return await until(func():return game.terrain.player_region_ready(point) and not game.latest_hit.is_empty(),15)
func cover_settled()->bool:
	var cover=game.ground_cover
	return not game.terrain.pending_edit and cover.resident.size()==cover._wanted.size() and cover._retiring.is_empty() and cover._dirty.is_empty() and cover._requests.is_empty() and cover._scatter_job.is_empty() and cover._support_job.is_empty() and game.ecosystem._requests.is_empty() and game.ecosystem._resample.is_empty() and game.ecosystem._reconcile.is_empty()
func run()->void:
	visual_mode="--terrain-tools-visual" in OS.get_cmdline_user_args()
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--terrain-soak-rounds="):soak_rounds=clampi(argument.get_slice("=",1).to_int(),1,20)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://reports/terrain_tools_endurance"))
	if writer.start()!=OK:quit(2);return
	game=Scene.instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;game.player_view.settings_path=""
	root.add_child(game);game.fly=true
	process_frame.connect(frame);RenderingServer.frame_pre_draw.connect(pre_draw);RenderingServer.frame_post_draw.connect(post_draw)
	game.terrain.stage_measured.connect(stage)
	game.terrain.work_measured.connect(func(row:Dictionary):work.append(row.duplicate(true)))
	game.terrain.edit_measured.connect(func(row:Dictionary):edits.append(row.duplicate(true)))
	game.terrain.height_received.connect(func(_point:Vector3,height:float,token:int):
		if token==height_token:height_value=height)
	if not await until(func():return game.terrain.world_ready and not game.loading_active,60):check(false,"startup deadline");finish();return
	check(Presentation.measurement(root).fair_graphical_sample,"fullscreen 1920x1080 at full render scale")
	check(game.ground_enabled,"production ground cover participates in terrain edits")
	if not game.session_menu.developer:game.session_menu.toggle_developer()
	select_tool(0)
	game.zombies.clear();game.zombies.population_enabled=false
	root.grab_focus();await until(func():return game.app_focused,3)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	check(game.session_menu.tool_workspace.radius.min_value==0.5,"detailed terrain controls use native minimum radius")
	var radii:Array=[]
	for node:Node in game.session_menu.developer_hud.content.get_children():
		if node is SpinBox:radii.append(node.min_value)
	check(radii==[0.5],"ALT terrain controls use native minimum radius")
	for tool:int in [3,2,4,1]:
		select_tool(0 if tool==3 else (2 if tool==1 else 1),tool);game.radius=1.5
		if not await aim(Vector3(800+(tool*24),0,1310)):
			check(false,"tool %d target ready"%tool);finish();return
		for add:bool in [true,false]:
			begin_phase("held_tool_%d_%s"%[tool,"fill" if add else "dig"])
			var revision:int=game.terrain.density_revision
			var button:=MOUSE_BUTTON_RIGHT if add else MOUSE_BUTTON_LEFT
			mouse(button,true)
			await create_timer(2).timeout
			mouse(button,false)
			var settled:=await until(func():return not game.terrain.pending_edit and game.stroke_buffer.samples.is_empty(),30)
			await process_frame
			check(settled and game.terrain.world_ready and game.terrain.density_revision>revision,"tool %d %s changes terrain and drains bounded queue"%[tool,"fill" if add else "dig"])
			end_phase()
	select_tool(0)
	begin_phase("large_volume_api")
	for radius:float in [8,16,32,64]:
		for shape:int in [0,1]:
			var center:=Vector3(1024.25,90.25,1312.25)
			game.player.position=center+Vector3(70,80,100);game.camera.look_at(center)
			for add:bool in [true,false]:
				var began:=Time.get_ticks_usec()
				var ok:=await submit(Codec.brush(center,center,radius,shape,add,1))
				observations.append({"radius":radius,"shape":shape,"add":add,"complete":ok,"latency_ms":(Time.get_ticks_usec()-began)/1000.0,"field_ms":game.terrain.last_edit_ms,"build_ms":game.terrain.last_total_build_ms,"support_instances":game.terrain.last_support_instances,"support_worker_ms":game.terrain.last_support_worker_ms,"support_publish_ms":game.terrain.last_support_publish_ms})
				if not ok:check(false,"large-volume edit completes");end_phase();finish();return
	end_phase()
	check(true,"all 8/16/32/64 m sphere and box add/remove edits publish")
	if visual_mode:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/terrain_tools_endurance/large_excavation.png")
		check(await until(cover_settled,45),"large-edit vegetation support finishes revalidation")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/terrain_tools_endurance/large_excavation_settled.png")
	game.player.position=Vector3(805,70,1322);game.camera.look_at(Vector3(800,48,1310))
	await create_timer(3).timeout
	for round_index:int in range(soak_rounds):
		begin_phase("mixed_history_%d"%round_index)
		var ok:=true
		for index:int in range(400):
			var radius:float=[0.5,0.75,1.0,2.5,4.0][index%5]
			var center:=Vector3(800+index%8,48+(index/8%4),1300+(index/32%8))
			var shape:=index%2
			var add:=index%4<2
			ok=await submit(Codec.brush(center,center+Vector3(0.25,0.25,0.25),radius,shape,add,1+index%3))
			if not ok:break
		check(ok and game.terrain.latest_error.is_empty(),"400 mixed sphere/box additions and excavations finish in round %d"%round_index)
		end_phase()
		if not ok:finish();return
	begin_phase("idle_recovery")
	await create_timer(10).timeout;end_phase()
	if not visual_mode:
		for row:Dictionary in phases:
			check(row.frames.p99_ms<=20 and row.frames.over_50ms==0,row.phase+": p99 frame <=20ms and no >50ms stall")
			if row.phase.begins_with("mixed_history"):
				check(row.edit_latency.p95_ms<=150,row.phase+": ordinary edit publication p95 <=150ms")
		var entire_run:=summary(runtime_frames)
		check(entire_run.p99_ms<=20 and entire_run.over_50ms==0,"whole workload including tool switches and phase boundaries meets frame budget")
	check(game.terrain.tiles.size()<=game.terrain.cache_entry_limit+16,"resident mesh entries remain bounded after recovery")
	if visual_mode:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/terrain_tools_endurance/mixed_excavation.png")
	finish()
func checkpoint(complete:bool)->void:
	if not complete:return
	FileAccess.open("res://reports/terrain_tools_endurance/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"phases":phases,"large_edits":observations,"api_commands":total_commands,"soak_rounds":soak_rounds,"visual_mode":visual_mode,"observer_operations":observer_operations,"hitches":hitches,"pipeline_changes":pipeline_changes,"runtime_frames":summary(runtime_frames),"presentation":Presentation.measurement(root),"scope":"Actual held mouse/controller input for all four dev terrain modes, maximum sphere/box volume publication, 400 mixed API edits per round, idle recovery. Full rendering/collision/vegetation active; entities disabled. Native-volume and storage checks cover separate long histories and archive reopen. Not multi-hour endurance or all hardware."},"  "))
func finish()->void:
	mouse(MOUSE_BUTTON_LEFT,false);mouse(MOUSE_BUTTON_RIGHT,false)
	process_frame.disconnect(frame);RenderingServer.frame_pre_draw.disconnect(pre_draw);RenderingServer.frame_post_draw.disconnect(post_draw)
	writer.submit({"rows":frame_batch});frame_batch=[];writer.stop()
	check(not writer.failed and writer.rows_written==captured_frames,"all measured frame samples retained")
	checkpoint(true)
	game.shutdown_requested=true
	check(await game.terrain.shutdown_after_edits(),"temporary endurance world closes consistently")
	game.free();await process_frame;await process_frame
	var failed:=checks.any(func(row:Dictionary):return not row.pass)
	print("TERRAIN_TOOLS_ENDURANCE failures=",1 if failed else 0);quit(1 if failed else 0)
