# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var game: Node
var phases: Array=[]
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func settled() -> bool:
	return game.terrain.backend.queued()==0 and game.terrain.backend.status()=="idle" and game.ecosystem._requests.is_empty() and game.ecosystem.resident.size()==game.ecosystem._wanted.size() and game.ground_cover._requests.is_empty() and game.ground_cover._support_job.is_empty() and game.ground_cover._dirty.is_empty()
func summary(rows: Array,field: String) -> Dictionary:
	var values: Array=[]
	for row: Dictionary in rows: values.append(float(row[field]))
	values.sort()
	return {"median":values[values.size()/2],"p95":values[floori((values.size()-1)*0.95)],"p99":values[floori((values.size()-1)*0.99)],"max":values.back()}
func sample(label: String,enabled: bool) -> void:
	var cover: Node=game.ground_cover
	cover.set_process(enabled)
	if not enabled: cover.reset()
	var begin:=Time.get_ticks_usec()
	var deadline:=Time.get_ticks_msec()+12000
	while (not settled() or (enabled and cover.resident.size()!=49)) and Time.get_ticks_msec()<deadline: await process_frame
	var arrival_ms: float=(Time.get_ticks_usec()-begin)/1000.0
	check(settled() and (not enabled or cover.resident.size()==49),label+" reaches settled workload")
	var idle_frames:=0
	deadline=Time.get_ticks_msec()+12000
	while idle_frames<60 and Time.get_ticks_msec()<deadline:
		await RenderingServer.frame_post_draw
		idle_frames=idle_frames+1 if settled() else 0
	check(idle_frames==60,label+" sustains a one-second idle warmup")
	var viewport: RID=root.get_viewport_rid()
	var rows: Array=[]
	var previous:=Time.get_ticks_usec()
	for frame in range(180):
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		rows.append({"frame_ms":(now-previous)/1000.0,"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),"render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"queued":game.terrain.backend.queued(),"worker":game.terrain.backend.status(),"worker_busy":0 if game.terrain.backend.status()=="idle" else 1,"static_memory":Performance.get_monitor(Performance.MEMORY_STATIC)})
		previous=now
	var result:={"phase":label,"enabled":enabled,"arrival_ms":arrival_ms,"trees":game.vegetation.renderer.roots.size(),"tree_owners":game.ecosystem.resident.size(),"ground_owners":cover.resident.size(),"rows":rows,"summary":{},"render":[]}
	for field in ["frame_ms","render_cpu_ms","render_gpu_ms","process_ms","draw_calls","primitives","queued","worker_busy","static_memory"]: result.summary[field]=summary(rows,field)
	for batch in cover.batches: result.render.append(batch.render_stats())
	check(result.summary.queued.max==0 and result.summary.worker_busy.max==0,label+" has no queued or active terrain jobs during stationary capture")
	check(result.summary.frame_ms.p95<=18.5 and result.summary.frame_ms.p99<=25 and result.summary.frame_ms.max<=50,label+" meets existing short-route frame gates")
	check(result.summary.render_gpu_ms.median>0,label+" GPU timer is available")
	phases.append(result)
	if label=="enabled_b":
		DirAccess.make_dir_recursive_absolute("res://reports/ground_cover")
		root.get_texture().get_image().save_png("res://reports/ground_cover/cost_enabled.png")
	print("GROUND_COST_PHASE ",JSON.stringify({"phase":label,"arrival_ms":arrival_ms,"summary":result.summary}))
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"world ready")
	game.set_physics_process(false);game._clear_motion()
	game.camera.rotation_degrees.x=-15
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	await sample("disabled_a",false)
	await sample("enabled_a",true)
	await sample("enabled_b",true)
	await sample("disabled_b",false)
	var presentation: Dictionary=load("res://addons/presentation/fullscreen_policy.gd").measurement(root)
	check(presentation.fair_graphical_sample and Engine.max_fps==60,"fullscreen 1920x1080 at native scale and 60 FPS cap")
	check(phases[0].trees==phases[1].trees and phases[1].trees==phases[2].trees and phases[2].trees==phases[3].trees,"tree workload remains identical across paired phases")
	DirAccess.make_dir_recursive_absolute("res://reports/ground_cover")
	var report:={"failures":failures,"phases":phases,"presentation":presentation,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"logical_cpus":OS.get_processor_count(),"notes":"Stationary ABBA marginal-cost check, natural ground cover only. GPU timing is viewport render time, not whole-device utilization/power. Frame intervals include the cap. Process monitor excludes worker CPU. No thermal or endurance claim."}
	var file:=FileAccess.open("res://reports/ground_cover/cost.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),false)
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
	for frame in range(2): await process_frame
	print("GROUND_COVER_COST failures=",failures)
	quit(1 if failures else 0)
