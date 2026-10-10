# SPDX-License-Identifier: 0BSD
extends SceneTree
var game: Node
var rows: Array=[]
var failures:=0
var previous:=0
var viewport: RID
var trace_enabled: bool="--trace-loading" in OS.get_cmdline_user_args()
var trace: Array=[]
var next_trace:=0
func trace_loading(phase: String) -> void:
	if not trace_enabled or Time.get_ticks_msec()<next_trace:return
	next_trace=Time.get_ticks_msec()+250
	trace.append({"time_us":Time.get_ticks_usec(),"phase":phase,"queue":game.terrain.backend.diagnostic_queue_snapshot(),"receive_ms":game.terrain.last_receive_ms,"publish_ms":game.terrain.last_publish_frame_ms,"schedule_ms":game.terrain.last_schedule_ms,"ground_dirty":game.ground_cover._dirty.size(),"ground_requests":game.ground_cover._requests.size(),"ecosystem_requests":game.ecosystem._requests.size(),"settled":settled()})
func _initialize() -> void:run.call_deferred()
func settled() -> bool:
	return not game.terrain.pending_edit and game.terrain.backend.queued()==0 and game.terrain.backend.status()=="idle" and game.ecosystem._requests.is_empty() and game.ecosystem.resident.size()==game.ecosystem._wanted.size() and game.ground_cover._requests.is_empty() and game.ground_cover._support_job.is_empty() and game.ground_cover._dirty.is_empty()
func capture(phase: String) -> void:
	await RenderingServer.frame_post_draw
	var now:=Time.get_ticks_usec()
	rows.append({"phase":phase,"frame_ms":(now-previous)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"queued":game.terrain.backend.queued(),"worker":game.terrain.backend.status(),"section":game.road_authoring.section,"trees":game.vegetation.renderer.roots.size(),"ground_dirty":game.ground_cover._dirty.size(),"ground_requests":game.ground_cover._requests.size(),"settled":settled()})
	previous=now
	trace_loading(phase)
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"world loaded")
	game.terrain.backend.disable_snapshot_writes();game.set_physics_process(false);game._clear_motion();game.app_focused=true
	game.player.position=Vector3(800,55,1250);game.camera.global_position=Vector3(795,75,1275);game.camera.look_at(Vector3(750,55,1310));Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	viewport=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
	if trace_enabled:game.terrain.backend.enable_diagnostics()
	var idle:=0;deadline=Time.get_ticks_msec()+15000
	while idle<60 and Time.get_ticks_msec()<deadline:
		await process_frame;idle=idle+1 if settled() else 0
		trace_loading("warmup")
	check(idle==60,"baseline reaches 60 idle frames")
	previous=Time.get_ticks_usec()
	for i in 120:await capture("baseline")
	var p=game.road_palette;p.width.value=4;p.depth.value=4;p.clearance.value=16
	p.mark(true,Vector3(784,50.86719,1310));p.mark(false,Vector3(672,59,1310));game._road_action("smooth")
	deadline=Time.get_ticks_msec()+20000
	while game.road_authoring.phase in ["request","sampling","fitting"] and Time.get_ticks_msec()<deadline:await capture("prepare")
	check(game.road_authoring.phase=="ready","smooth preview ready")
	game._road_action("build");deadline=Time.get_ticks_msec()+30000
	while game.road_authoring.phase=="building" and Time.get_ticks_msec()<deadline:await capture("build")
	check(game.road_authoring.phase=="complete","all road sections published")
	idle=0;deadline=Time.get_ticks_msec()+15000
	while idle<60 and Time.get_ticks_msec()<deadline:
		await capture("recovery");idle=idle+1 if settled() else 0
	check(idle==60,"terrain and vegetation recover to 60 idle frames")
	for i in 120:await capture("after")
	var summary: Dictionary={}
	for phase in ["baseline","prepare","build","recovery","after"]:
		var values: Array=[];var total:=0.0
		for row in rows:
			if row.phase==phase:values.append(row.frame_ms);total+=row.frame_ms
		values.sort()
		if not values.is_empty():summary[phase]={"frames":values.size(),"elapsed_ms":total,"p95_ms":values[int((values.size()-1)*0.95)],"max_ms":values[-1]}
	for phase in ["baseline","build","after"]:
		check(summary.has(phase) and summary[phase].p95_ms<=18.5,phase+" frame p95 <=18.5 ms")
	DirAccess.make_dir_recursive_absolute("res://reports/road_construction_cost")
	var file:=FileAccess.open("res://reports/road_construction_cost/result.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"summary":summary,"rows":rows,"trace":trace},"  "));file.close()
	root.get_texture().get_image().save_png("res://reports/road_construction_cost/settled.png")
	print(JSON.stringify(summary));game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
