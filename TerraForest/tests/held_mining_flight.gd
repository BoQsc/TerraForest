# SPDX-License-Identifier: 0BSD
extends "res://tests/foundation_mining.gd"
const VisualObserver=preload("res://tests/mining_visual_observer.gd")
var visual: RefCounted

# Exercise controller ray hits, 50ms held capture, stroke buffer and draw events.
# Do not replace this with serial sculpt calls that wait before capturing again.
func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://reports")
	if writer.start()!=OK: quit(2);return
	game=Scene.instantiate();game.temporary_world=true
	game.max_fps=60;game.background_fps=60
	root.add_child(game);game.fly=true
	if "--visual-debug" in OS.get_cmdline_user_args():
		visual=VisualObserver.new()
		visual.attach(game)
	process_frame.connect(frame)
	RenderingServer.frame_pre_draw.connect(pre_draw)
	RenderingServer.frame_post_draw.connect(post_draw)
	game.terrain.stage_measured.connect(stage)
	game.terrain.edit_measured.connect(func(row: Dictionary):
		var measured: Dictionary=row.duplicate(true)
		measured["current_visible_terrain"]=false
		var coordinates: Array=row.descriptor.get("a",[])
		if coordinates.size()==3:
			for key: Vector3i in game.terrain.visible_cut:
				if coordinates[0]>=key.x and coordinates[0]<key.x+key.z and coordinates[2]>=key.y and coordinates[2]<key.y+key.z and not game.terrain.tiles[key].dirty:
					measured["current_visible_terrain"]=true;break
		edits.append(measured))
	game.terrain.height_received.connect(func(_p: Vector3,h: float,t: int):
		if t==height_token: height_value=h)
	if not await until(func(): return game.terrain.world_ready and not game.loading_active,60):
		check(false,"initial readiness");finish();return
	check(Presentation.measurement(root).fair_graphical_sample,"1920x1080 fullscreen at full scale")
	var reports: Array=[]
	game.tool=3;game.radius=2.5
	for destination in [Vector3(1308,0,1260),Vector3(1302,0,1212)]:
		height_value=NAN;height_token+=1
		game.terrain.request_height(destination,height_token)
		if not await until(func(): return is_finite(height_value),5):
			check(false,"flight destination query");break
		destination.y=height_value
		game.player.position=destination+Vector3(0,10,12)
		game.camera.look_at(destination)
		root.grab_focus()
		if not await until(func(): return game.app_focused,2):
			check(false,"automated window obtains focus before input");break
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		begin_phase("held_flight_%d"%reports.size())
		var started:=Time.get_ticks_usec()
		if visual!=null: visual.begin(phase,started,destination)
		var press:=InputEventMouseButton.new()
		press.button_index=MOUSE_BUTTON_LEFT;press.pressed=true
		Input.parse_input_event(press)
		var input_frames:=0
		var eligible_frames:=0
		var hit_frames:=0
		var loading_frames:=0
		var pending_frames:=0
		var readiness_trace: Array=[]
		var previous_state: String=""
		var held_until:=Time.get_ticks_msec()+3000
		while Time.get_ticks_msec()<held_until:
			await process_frame
			input_frames+=1
			if game.app_focused and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): eligible_frames+=1
			if not game.latest_hit.is_empty(): hit_frames+=1
			if game.loading_active: loading_frames+=1
			if game.terrain.pending_edit: pending_frames+=1
			# Record readiness transitions rather than hiding pre-capture waits.
			if edits.is_empty():
				var state: String="query=%s cache=%s hit=%s target=%s pending=%s"%[not game.terrain_pick_request.is_empty(),not game.terrain_pick_cache.is_empty(),not game.latest_hit.is_empty(),game.terrain.interaction_target,game.terrain.pending_edit]
				if state!=previous_state:
					readiness_trace.append({"ms":(Time.get_ticks_usec()-started)/1000.0,"state":state,"in_flight":str(game.terrain.in_flight.keys()),"staging":game.terrain.staging.size(),"preparing":str(game.terrain.preparation.get("data",{}).get("key","none")),"visible":str(game.terrain.visible_cut)})
					previous_state=state
		press=InputEventMouseButton.new()
		press.button_index=MOUSE_BUTTON_LEFT;press.pressed=false
		Input.parse_input_event(press)
		await until(func(): return not game.terrain.pending_edit,3)
		await process_frame
		if visual!=null: visual.end()
		var gaps: Array[float]=[]
		var last_draw:=started
		var latencies: Array[float]=[]
		for row: Dictionary in edits:
			if row.changed and row.current_visible_terrain and int(row.get("draw_us",0))>last_draw:
				gaps.append((int(row.draw_us)-last_draw)/1000.0)
				last_draw=int(row.draw_us)
			if row.changed and row.current_visible_terrain: latencies.append(float(row.draw_ms))
		end_phase()
		var row: Dictionary={"phase":phase,"changed_draws":gaps.size(),"visible_gaps":summary(gaps),"capture_to_draw":summary(latencies),"frames":summary(frames),"edits":edits.duplicate(true),"last_hit":not game.latest_hit.is_empty()}
		row["input_state"]={"frames":input_frames,"eligible":eligible_frames,"ray_hit":hit_frames,"loading":loading_frames,"pending_edit":pending_frames}
		row["readiness_trace"]=readiness_trace
		reports.append(row)
		check(eligible_frames>=input_frames*.9,"held-input workload valid: focused, captured and pressed")
		check(gaps.size()>=10,"held input produces repeated visible changes")
		check(not latencies.is_empty() and summary(latencies).p95_ms<=150,"held capture-to-draw p95 <=150ms")
		check(not gaps.is_empty() and summary(gaps).max_ms<=150,"no gap between visible mining changes exceeds 150ms")
		check(not frames.is_empty() and summary(frames).p99_ms<=20 and summary(frames).over_50ms==0,"frame p99 <=20ms and no frame >50ms")
	var file:=FileAccess.open("res://reports/held_mining_flight.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"phases":reports,"presentation":Presentation.measurement(root),"visual_diagnostic":visual!=null,"scope":"Two three-second held mining bursts after scripted flight arrival; real controller physics ray, capture queue and rendered draw timing. No sustained movement during each burst; not endurance acceptance. Visual mode includes intrusive GPU readback; use separate normal run for performance."},"  "));file.close()
	if visual!=null: visual.finish()
	finish()
