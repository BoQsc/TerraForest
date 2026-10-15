# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var rows: Array=[]
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func percentile(values: Array,p: float) -> float:
	var sorted:=values.duplicate();sorted.sort();return sorted[mini(sorted.size()-1,int(sorted.size()*p))]
func run() -> void:
	if DisplayServer.get_name()=="headless":push_error("Rendered test required");quit(2);return
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("91abb8")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.55;root.add_child(environment)
	var sun:=DirectionalLight3D.new();root.add_child(sun);sun.rotation_degrees=Vector3(-45,30,0);sun.shadow_enabled=true
	var camera:=Camera3D.new();root.add_child(camera);camera.current=true
	var catalog=preload("res://addons/structures/furniture_catalog.gd")
	var asset: Resource=catalog.furnished_tower(3)
	for count in [1,16,64]:
		var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
		check(world.prepare() and catalog.register(world).size()==3,"fixture prepared %d"%count)
		for c in [preload("res://addons/structures/storage_catalog.gd"),preload("res://addons/structures/window_catalog.gd"),preload("res://addons/structures/door_catalog.gd"),preload("res://addons/structures/guardrail_catalog.gd")]:check(not c.register(world).is_empty(),"model catalog registered %d"%count)
		var side:=int(sqrt(count));var maximum_call_us:=0
		var focus:=Vector3.ZERO if count==1 else Vector3(-12,0,-12)
		world.blocks.set_focus(focus);world.blocks.set_collision_radius(64);world.set_model_focus(focus)
		camera.position=focus+Vector3(40,24,60);camera.look_at(focus+Vector3(0,6,0))
		for index in count:
			var origin:=Vector3i(int((index%side-(side-1)*0.5)*24),0,int((index/side-(side-1)*0.5)*24))
			var tx=ClassDB.instantiate("NativePrefabPlacement")
			var start:=Time.get_ticks_usec()
			var result: Dictionary=tx.begin(world.blocks,asset,origin,0,world.model_collections(),[])
			maximum_call_us=maxi(maximum_call_us,Time.get_ticks_usec()-start)
			while result.ok and result.status=="preparing":
				start=Time.get_ticks_usec();result=tx.advance(2048,16,1000)
				maximum_call_us=maxi(maximum_call_us,Time.get_ticks_usec()-start);await process_frame
			start=Time.get_ticks_usec()
			if result.ok:result=tx.commit([])
			maximum_call_us=maxi(maximum_call_us,Time.get_ticks_usec()-start)
			if not result.ok:check(false,"tower placement %d/%d: %s"%[index,count,result]);break
		for frame in 120:await process_frame
		var exact: bool=world.blocks.stats().cells==count*asset.get_cell_count()
		var residents: Dictionary={};var total_models:=0;var settled:=true
		for key: String in world.model_collections():
			var batch=world.model(key);total_models+=batch.get_ids().size()
			var rendering: Dictionary=batch.render_stats();var collision: Dictionary=batch.collision_stats()
			residents[key]={"render":rendering,"collision":collision}
			settled=settled and not rendering.selection_pending and rendering.pending_batches==0 and not collision.selection_pending and collision.pending_bodies==0
		check(exact and total_models==count*66,"exact furnished population %d"%count)
		check(settled,"model render and collision queues settled %d"%count)
		var local_ready: bool=world.is_collision_region_ready(AABB(focus+Vector3(-9,0,-9),Vector3(19,14,20)))
		check(local_ready,"nearest complete tower has collision coverage %d"%count)
		var frames: Array=[];var cpu: Array=[];var gpu_render: Array=[];var cpu_render: Array=[];var previous:=Time.get_ticks_usec()
		for frame in 120:
			await process_frame
			var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
			cpu.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000)
			gpu_render.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			cpu_render.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		var row: Dictionary={"towers":count,"blocks":world.blocks.stats(),"models":total_models,"residents":residents,"nearest_tower_collision_ready":local_ready,"max_placement_call_us":maximum_call_us,"frame_p50_ms":percentile(frames,0.5),"frame_p95_ms":percentile(frames,0.95),"frame_max_ms":frames.max(),"engine_process_monitor_p95_ms":percentile(cpu,0.95),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
		row["viewport_gpu_p95_ms"]=percentile(gpu_render,0.95)
		row["viewport_render_cpu_p95_ms"]=percentile(cpu_render,0.95)
		rows.append(row);print("TOWER_DENSITY_ROW ",JSON.stringify(row))
		check(float(row.frame_p95_ms)<=20,"settled frame p95 <=20 ms diagnostic threshold %d"%count)
		DirAccess.make_dir_recursive_absolute("res://reports")
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png("res://reports/tower_density_%d.png"%count)
		world.free();await process_frame
	var file:=FileAccess.open("res://reports/tower_density.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"rows":rows,"scope":"1080p capped 60, 120 measured frames per size, isolated buildings with shadows; no terrain forest actors traffic or thermal qualification"},"  "));file.close()
	print("TOWER_DENSITY failures=",failures);quit(1 if failures else 0)
