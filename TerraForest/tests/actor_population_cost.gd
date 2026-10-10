# SPDX-License-Identifier: 0BSD
extends SceneTree
var game: Node
var failures:=0
var phases: Array=[]
var ids:=PackedInt64Array()
var start:=Vector3.ZERO
var direction:=Vector3.RIGHT
var side:=Vector3.BACK
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func settled() -> bool:
	return game.terrain.backend.queued()==0 and game.terrain.backend.status()=="idle" and game.ecosystem._requests.is_empty() and game.ground_cover._requests.is_empty() and game.ground_cover._support_job.is_empty() and game.ground_cover._dirty.is_empty()
func summary(rows: Array,field: String) -> Dictionary:
	var values: Array=[]
	for row in rows:values.append(float(row[field]))
	values.sort();return {"median":values[values.size()/2],"p95":values[int((values.size()-1)*0.95)],"max":values[-1]}
func add_until(count: int) -> void:
	while ids.size()<count:
		var i:=ids.size();var point:=start+direction*(i/4)*0.8+side*(i%4-1.5)*1.0
		var identity: int=game.actors.spawn(point);ids.append(identity)
		game.actors.orders.set_target(identity,point+direction*12)
func sample(label: String) -> void:
	var rows: Array=[];var visited: Dictionary={};var prior:=PackedInt64Array();var changes:=0
	var previous:=Time.get_ticks_usec()
	var viewport:=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
	for tick in 120:
		await physics_frame
		var begin:=Time.get_ticks_usec()
		game.actors.update_simulation(1.0/60,start,true,game._actor_collision_ready)
		var cost: float=(Time.get_ticks_usec()-begin)/1000.0
		var active: PackedInt64Array=game.actors.pool.active_handles()
		for handle in active:
			visited[game.actors.store.persistent_id(handle)]=true
			if not prior.has(handle):changes+=1
		prior=active
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		rows.append({"frame_ms":(now-previous)/1000.0,"actor_ms":cost,"active":active.size(),"held":game.actors.simulation_status.get("held",0),"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"queued":game.terrain.backend.queued(),"worker_busy":0 if game.terrain.backend.status()=="idle" else 1,"settled":settled()});previous=now
	var result:={"phase":label,"stored_near":ids.size(),"distinct_simulated":visited.size(),"activation_entries":changes,"rows":rows,"summary":{}}
	for field in ["frame_ms","actor_ms","active","held","gpu_ms","draw_calls","queued","worker_busy"]:result.summary[field]=summary(rows,field)
	phases.append(result)
	check(result.summary.active.max<=16 and game.actors.pool.get_child_count()==16,label+" maintains fixed16 physics cap")
	check(result.summary.held.max==0,label+" no collision-readiness holds")
	check(result.summary.actor_ms.p95<=1 and result.summary.actor_ms.max<=2,label+" actor adapter p95<=1ms max<=2ms")
	check(result.summary.frame_ms.p95<=18.5,label+" frame p95<=18.5ms")
	print(label," ",JSON.stringify(result.summary)," distinct=",visited.size()," entries=",changes)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	game.terrain.backend.disable_snapshot_writes();game.set_physics_process(false);game._clear_motion();game.app_focused=true
	var ends: PackedVector3Array=game.road_palette.prepared_streets[0].ends
	direction=(ends[1]-ends[0]).normalized();side=Vector3(-direction.z,0,direction.x);start=ends[0]+direction*5+Vector3.UP*0.95
	game.player.position=start+side*8;game.terrain.focus=start
	game.camera.global_position=start-direction*6+side*7+Vector3.UP*5;game.camera.look_at(start+direction*8)
	var idle:=0;deadline=Time.get_ticks_msec()+30000
	while idle<60 and Time.get_ticks_msec()<deadline:await process_frame;idle=idle+1 if settled() else 0
	check(idle==60,"world reaches60 idle frames before measurement")
	await sample("empty")
	add_until(16);await sample("moving16")
	add_until(64);await sample("nearby64")
	DirAccess.make_dir_recursive_absolute("res://reports/actor_population_cost")
	var file:=FileAccess.open("res://reports/actor_population_cost/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"phases":phases},"  "));file.close()
	root.get_texture().get_image().save_png("res://reports/actor_population_cost/world.png")
	game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
