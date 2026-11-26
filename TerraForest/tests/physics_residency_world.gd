# SPDX-License-Identifier: 0BSD
extends SceneTree
## Repeatable grounded workload at two human-capture hotspots. Source stays read-only.
class Observer extends Node:
	const FrameTrace=preload("res://addons/world_runtime/frame_trace.gd")
	var diagnostics:=OS.get_cmdline_user_args().has("--residency-diagnostics")
	var manual_draw:=OS.get_cmdline_user_args().has("--manual-no-present-probe")
	var detached_present:=OS.get_cmdline_user_args().has("--no-present-probe")
	var probe:RefCounted
	var render_trace:RefCounted
	var previous_work:=PackedInt64Array()
	var process_work:=PackedInt64Array()
	var draw_work:=PackedInt64Array()
	var host:Node
	var phase:="setup"
	var rows:Array[Dictionary]=[]
	var previous:=0
	var process_begin:=0
	var process_end:=0
	var draw_begin:=0
	var physics_begin:=0
	var physics_us:=0
	var physics_ticks:=0
	var zombie_phases:Dictionary={}
	var tail_begin:=0
	var tail_us:=0
	var stages:Dictionary={}
	var transitions:Array[Dictionary]=[]
	var known_transitions:Dictionary={}
	var resident_snapshot:Dictionary={}
	var residency_events:Array[Dictionary]=[]
	var observed_actors:Dictionary={}
	var clouds:Array[Dictionary]=[]
	var cloud_vertices:=0
	var cloud_overflow:=false
	var clock_anchor:Dictionary={}
	func _input(_event:InputEvent)->void:
		# Scripted controls own this replay. Desktop typing/clicks must not open
		# menus or change held keys while the same route is being measured.
		get_viewport().set_input_as_handled()
	func _ready()->void:
		clock_anchor={"ticks_us":Time.get_ticks_usec(),"utc_s":Time.get_unix_time_from_system()}
		probe=ClassDB.instantiate("NativeResourceUsage")
		if diagnostics:
			render_trace=preload("res://addons/world_runtime/render_trace.gd").new()
		process_priority=1000000;process_physics_priority=1000000
		get_tree().process_frame.connect(begin_process)
		get_tree().physics_frame.connect(begin_physics)
		RenderingServer.frame_pre_draw.connect(begin_draw)
		RenderingServer.frame_post_draw.connect(end_draw)
		if manual_draw:RenderingServer.render_loop_enabled=false
		if detached_present:
			RenderingServer.viewport_attach_to_screen(get_viewport().get_viewport_rid(),Rect2(),DisplayServer.INVALID_WINDOW_ID)
			RenderingServer.viewport_set_update_mode(get_viewport().get_viewport_rid(),RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	func finish_tail(now:int)->void:
		if tail_begin:tail_us+=now-tail_begin;tail_begin=0
	func work()->PackedInt64Array:
		return probe.thread_work() if probe!=null and OS.get_thread_caller_id()==OS.get_main_thread_id() else PackedInt64Array()
	func begin_process()->void:process_begin=Time.get_ticks_usec();finish_tail(process_begin);process_work=work()
	func begin_physics()->void:physics_begin=Time.get_ticks_usec();finish_tail(physics_begin)
	func _physics_process(_delta:float)->void:
		physics_ticks+=1
		if is_instance_valid(host):
			for key:String in host.zombies.update_phase_us:zombie_phases[key]=int(zombie_phases.get(key,0))+int(host.zombies.update_phase_us[key])
		observe_residents()
		var now:=Time.get_ticks_usec()
		if physics_begin:physics_us+=now-physics_begin
		tail_begin=now
	func event(kind:String,details:Dictionary)->void:
		if residency_events.size()>=4096:return
		var row:=details.duplicate();row.kind=kind;row.phase=phase;row.tick=Engine.get_physics_frames()
		residency_events.append(row)
	func died(actor:Node3D)->void:
		event("died",{"id":actor.get_meta("world_zombie_id",0),"position":actor.global_position})
	func observe_residents()->void:
		if not is_instance_valid(host):return
		var current:Dictionary={}
		for actor:Node3D in host.zombies.residents:
			if not is_instance_valid(actor):continue
			var id:int=actor.get_meta("world_zombie_id",0)
			var row:={"id":id,"position":actor.global_position,"alive":actor.alive,"distance":actor.global_position.distance_to(host.player.global_position)}
			current[id]=row
			if not resident_snapshot.has(id):event("admitted",row)
			if not observed_actors.has(actor.get_instance_id()):
				observed_actors[actor.get_instance_id()]=true;actor.died.connect(died.bind(actor))
		for id:int in resident_snapshot:
			if current.has(id):continue
			var row:Dictionary=resident_snapshot[id].duplicate()
			row.stored_state=host.zombies.population.store.resident(id).get("state",-1)
			event("retired",row)
		resident_snapshot=current
	func _process(delta:float)->void:
		process_end=Time.get_ticks_usec()
		if manual_draw:draw_without_present.call_deferred(delta)
	func draw_without_present(delta:float)->void:RenderingServer.force_draw(false,delta)
	func begin_draw()->void:draw_begin=Time.get_ticks_usec();draw_work=work()
	func stage(label:String,ms:float)->void:stages[label]=float(stages.get(label,0.0))+ms
	func end_draw()->void:
		var now:=Time.get_ticks_usec()
		var completed_work:=work()
		if is_instance_valid(host):
			for corpse:Node in host.corpse_loot.active.values():
				if not corpse.ragdoll_profile.has("end_us") or known_transitions.has(corpse.get_instance_id()):continue
				known_transitions[corpse.get_instance_id()]=true
				var event:Dictionary=corpse.ragdoll_profile.duplicate();event.phase=phase;event.frame=Engine.get_process_frames()
				event.corpse_id=corpse.get_meta("corpse_identity",0);event.resident_id=corpse.get_meta("world_zombie_id",0)
				event.initialization_us=corpse.initialization_us.duplicate()
				transitions.append(event)
				if phase!="setup":
					for part:String in corpse.collision_clouds:
						var points:PackedVector3Array=corpse.collision_clouds[part]
						if clouds.size()>=512 or cloud_vertices+points.size()>524288:cloud_overflow=true;continue
						clouds.append({"corpse_id":event.corpse_id,"part":part,"phase":phase,"points":points});cloud_vertices+=points.size()
				corpse.collision_clouds.clear()
		if previous and phase!="setup" and is_instance_valid(host) and rows.size()<12000:
			var row:={"phase":phase,"at_us":now,"frame_ms":(now-previous)/1000.0,
				"process_frame":Engine.get_process_frames(),"drawn_frame":Engine.get_frames_drawn(),"window_focused":get_window().has_focus(),
				"before_process_ms":(process_begin-previous)/1000.0,"process_ms":(process_end-process_begin)/1000.0,
				"draw_ms":(now-draw_begin)/1000.0,"physics_ms":physics_us/1000.0,"physics_tail_ms":tail_us/1000.0,
				"pre_draw_ms":(draw_begin-process_end)/1000.0,"physics_ticks":physics_ticks,"zombie_frame_us":zombie_phases,
				"render_setup_ms":RenderingServer.get_frame_setup_time_cpu(),
				"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),
				"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"render_objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				"render_primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				"pipeline_draw":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW),
				"pipeline_specialization":Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION),
				"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
				"position":host.player.position,"zombies":host.zombies.residents.size(),
				"zombie_us":host.zombies.update_phase_us.duplicate(),"corpse_us":host.corpse_loot.update_profile.duplicate(),
				"terrain_ms":stages,"loading":host.loading_active,"physics_active":Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
				"physics_pairs":Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),"physics_islands":Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)}
			FrameTrace.add_work(row,"",previous_work,completed_work)
			FrameTrace.add_work(row,"draw",draw_work,completed_work)
			FrameTrace.add_work(row,"process_draw",process_work,draw_work)
			if diagnostics:
				row.render_markers=render_trace.capture(RenderingServer.get_rendering_device()) if RenderingServer.is_on_render_thread() else {}
				row.forest_us=host.vegetation.last_process_us;row.ecosystem_us=host.ecosystem.last_process_us;row.cover_us=host.ground_cover.last_process_us
				row.native_process={}
				for key:String in ["blocks","_model_horizon","resident_lights"]:
					var owner:Node=host.structures.get(key)
					if is_instance_valid(owner):row.native_process[key]=owner.process_frame_profile()
			rows.append(row)
		previous_work=completed_work
		previous=now;physics_us=0;physics_ticks=0;zombie_phases={};tail_us=0;stages={}
	func _exit_tree()->void:
		if manual_draw:RenderingServer.render_loop_enabled=true
		if detached_present:RenderingServer.viewport_attach_to_screen(get_viewport().get_viewport_rid(),Rect2(Vector2.ZERO,get_viewport().get_visible_rect().size),get_window().get_window_id())
		RenderingServer.frame_pre_draw.disconnect(begin_draw)
		RenderingServer.frame_post_draw.disconnect(end_draw)

var game:Node
var observer:Observer
var evidence:=""
var slot:="Hidden_Meadow"
var failures:=0
var route:Array[Dictionary]=[]
var population_legs:Array[Dictionary]=[]
func water_render_coverage()->void:
	var renderer:Node3D=game.lakes._render_pages
	var covered:Dictionary={};var valid:=true
	for page:Dictionary in renderer.pages.values():
		if page.node==null or not page.node.visible:continue
		var indices:=0
		for coordinate:Vector3i in page.members:
			var member:Dictionary=page.members[coordinate]
			var node:MeshInstance3D=member.node.get_ref()
			valid=valid and is_instance_valid(node) and node==game.lakes._meshes.get(coordinate) and not node.visible and not covered.has(coordinate)
			covered[coordinate]=true;indices+=member.arrays[Mesh.ARRAY_INDEX].size()
		valid=valid and page.node.mesh.surface_get_array_index_len(0)==indices
	for coordinate:Vector3i in game.lakes._meshes:
		var node:MeshInstance3D=game.lakes._meshes[coordinate]
		valid=valid and (covered.has(coordinate)!=node.visible)
	check(valid,"Every published water owner is drawn exactly once with the same triangle count")
var render_probe_rows:Array[Dictionary]=[]
var render_probe_phase:=""
var render_probe_start:=0
var render_probe_work:=PackedInt64Array()
func render_probe_begin()->void:
	render_probe_start=Time.get_ticks_usec();render_probe_work=observer.work()
func render_probe_end()->void:
	if render_probe_phase.is_empty():return
	render_probe_rows.append({"phase":render_probe_phase,"draw_us":Time.get_ticks_usec()-render_probe_start,"setup_ms":RenderingServer.get_frame_setup_time_cpu(),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	Observer.FrameTrace.add_work(render_probe_rows.back(),"draw",render_probe_work,observer.work())
func render_ablation()->Array[Dictionary]:
	# Post-route diagnosis only: freeze simulation, remove one render group, then
	# restore its exact visibility. Retain raw samples; never mix with route cadence.
	var groups:Dictionary={};var pending:Array[Node]=[game];var visited:=0
	while not pending.is_empty() and visited<100000:
		var node:Node=pending.pop_back();pending.append_array(node.get_children());visited+=1
		if not node is GeometryInstance3D or not node.is_visible_in_tree():continue
		var key:=str(game.get_path_to(node)).get_slice("/",0)
		if not groups.has(key):groups[key]=[]
		groups[key].append(node)
	if not check(pending.is_empty() and groups.size()<=32,"Render probe fits its node/group bounds"):return []
	RenderingServer.frame_pre_draw.connect(render_probe_begin)
	RenderingServer.frame_post_draw.connect(render_probe_end)
	var order:Array=groups.keys();order.push_front("water_unbatched");order.push_front("baseline");order.push_back("baseline")
	var original_draw_pages:bool=game.lakes._render_pages.draw_pages
	for repeat in 2:
		if repeat:order.reverse()
		for key:String in order:
			if key=="water_unbatched":game.lakes._render_pages.set_draw_pages(false)
			for node:GeometryInstance3D in groups.get(key,[]):node.hide()
			for tick in 16:await process_frame
			render_probe_phase=str(repeat)+":"+key
			for tick in 90:await process_frame
			render_probe_phase=""
			for node:GeometryInstance3D in groups.get(key,[]):node.show()
			if key=="water_unbatched":game.lakes._render_pages.set_draw_pages(original_draw_pages)
	RenderingServer.frame_pre_draw.disconnect(render_probe_begin)
	RenderingServer.frame_post_draw.disconnect(render_probe_end)
	return render_probe_rows
func render_inventory()->Dictionary:
	var pending:Array[Node]=[game];var groups:Dictionary={};var visited:=0
	while not pending.is_empty() and visited<100000:
		var node:Node=pending.pop_back();pending.append_array(node.get_children());visited+=1
		if not node is GeometryInstance3D or not node.is_visible_in_tree():continue
		var mesh:Mesh;var instances:=1
		if node is MeshInstance3D:mesh=node.mesh
		elif node is MultiMeshInstance3D and node.multimesh!=null:
			mesh=node.multimesh.mesh;instances=node.multimesh.instance_count if node.multimesh.visible_instance_count<0 else node.multimesh.visible_instance_count
		if mesh==null:continue
		var key:=str(game.get_path_to(node)).get_slice("/",0)
		if not groups.has(key):groups[key]={"nodes":0,"surfaces":0,"instances":0,"shadow_nodes":0,"script":str(game.get_node(key).get_script().resource_path) if game.get_node(key).get_script()!=null else game.get_node(key).get_class()}
		groups[key].nodes+=1;groups[key].surfaces+=mesh.get_surface_count();groups[key].instances+=instances
		if node.cast_shadow!=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:groups[key].shadow_nodes+=1
	return {"groups":groups,"visited":visited,"truncated":not pending.is_empty(),"scope":"Post-route visible scene geometry counts, not actual frustum/occlusion draw submissions. No instance-buffer readback."}
func construct_cloud(stage:Node3D,reducer:RefCounted,points:PackedVector3Array,reduced:bool)->Dictionary:
	var began:=Time.get_ticks_usec()
	var input:=points
	if reduced:input=reducer.prepare_collision_cloud(points).points
	var prepared:=Time.get_ticks_usec()
	var body:=StaticBody3D.new();body.collision_layer=0;body.collision_mask=0;stage.add_child(body)
	var shape:=ConvexPolygonShape3D.new();shape.margin=.003;shape.points=input
	var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
	var finished:=Time.get_ticks_usec()
	body.free()
	return {"points":input.size(),"prepare_us":prepared-began,"construction_us":finished-prepared,"total_us":finished-began}
func compare_clouds()->Array[Dictionary]:
	# All construction is outside the measured route. Alternate order and use
	# fresh resources: each pair cooks the exact same captured posed vertices.
	var result:Array[Dictionary]=[];var stage:=Node3D.new();root.add_child(stage)
	var reducer:RefCounted=ClassDB.instantiate("NativeZombieAnatomy")
	for index in observer.clouds.size():
		var captured:Dictionary=observer.clouds[index];var points:PackedVector3Array=captured.points
		var unique:Dictionary={}
		for point:Vector3 in points:unique[point]=true
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(points.to_byte_array())
		var row:={"part":captured.part,"corpse_id":captured.corpse_id,"phase":captured.phase,"input_points":points.size(),"exact_unique_points":unique.size(),"sha256":hash.finish().hex_encode(),"pairs":[]}
		for repeat in 3:
			var pair:Dictionary={}
			for reduced:bool in ([false,true] if (repeat+index)%2==0 else [true,false]):pair["reduced" if reduced else "original"]=construct_cloud(stage,reducer,points,reduced)
			row.pairs.append(pair)
		result.append(row)
	stage.free();observer.clouds.clear();return result
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func check(value:bool,label:String)->bool:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
	return value
func ready()->bool:
	var deadline:=Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		game.app_focused=true
		if game.startup_complete and not game.loading_active and not game.terrain.pending_edit:return true
		await process_frame
	return false
func walk(phase:String,key:int,ticks:int)->void:
	DisplayServer.window_set_title("TerraForest — performance replay: "+phase)
	observer.phase=phase
	var start:Vector3=game.player.position
	var blocked_ticks:=0
	if key:game.controls.set_key(key,true,Time.get_ticks_usec())
	for tick in ticks:
		game.app_focused=true
		if not game._movement_input_available() or game.session_menu.pauses_world():blocked_ticks+=1
		game.yaw=.2*sin(TAU*tick/float(ticks));game.player.rotation.y=game.yaw
		await physics_frame
	if key:game.controls.set_key(key,false,Time.get_ticks_usec())
	route.append({"phase":phase,"ticks":ticks,"start":start,"end":game.player.position,"distance":start.distance_to(game.player.position),"living":game.zombies.residents.size(),"corpses":game.corpse_loot.active.size()})
	check(blocked_ticks==0 and (not key or start.distance_to(game.player.position)>1.0),"Route leg %s keeps gameplay input available and completes movement"%phase)
	population_legs.append({"phase":phase,"residents":observer.resident_snapshot.duplicate(true),"corpse_ids":game.corpse_loot.active.keys(),"population":game.zombies.population.status()})
	print("RESIDENCY_LEG ",JSON.stringify(route.back()))
	observer.phase="setup"
func run()->void:
	if not check(DisplayServer.get_name()!="headless","Rendered frame cadence is available"):quit(1);return
	DisplayServer.window_set_title("TerraForest — performance replay: loading saved world")
	if OS.get_cmdline_user_args().has("--windowed-probe"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1920,1080))
		await process_frame;await process_frame
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):evidence=arg.get_slice("=",1)
		if arg.begins_with("--residency-source="):slot=arg.get_slice("=",1)
	if evidence.is_empty() or not preload("res://demo/world_launch.gd").valid_slot(slot):quit(2);return
	var source:="user://worlds/"+slot+".trw"
	if not check(FileAccess.file_exists(source),"Existing player source is available"):quit(1);return
	var original:=FileAccess.get_sha256(source)
	seed(1703)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray([
		"--world-slot="+slot,"--snapshot-readonly","--temporary","--no-derived-cache","--gameplay-construction","--ground-cover","--actors","--vehicle-fleet"]),true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
	game.lakes._render_pages.enabled=not OS.get_cmdline_user_args().has("--original-water-render-probe")
	game.lakes._render_pages.set_draw_pages(not OS.get_cmdline_user_args().has("--unbatched-water"))
	root.add_child(game)
	if not check(await ready(),"Player world loads read-only"):game.free();quit(1);return
	# Foreground activation is a setup action, never a per-frame focus override.
	# Windows may leave a background-launched fullscreen window unfocused.
	var previous_process_mode:int=game.process_mode;game.process_mode=Node.PROCESS_MODE_DISABLED
	var interactive:=not OS.get_cmdline_user_args().has("--isolated-render")
	if interactive:root.grab_focus()
	await process_frame;await process_frame
	game.process_mode=previous_process_mode
	if interactive and not check(root.has_focus(),"Visible replay has focus before measurement"):
		game.shutdown_requested=true;game.terrain.shutdown();game.free();quit(1);return
	if OS.get_cmdline_user_args().has("--no-occlusion-probe"):root.use_occlusion_culling=false
	if OS.get_cmdline_user_args().has("--no-vsync-probe"):DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	game.player_view.entry.finish();game.session_menu.set_open(false)
	game.session_menu.developer_hud.mouse_access=true
	game.zombies.profiling_enabled=true
	game.zombies.capture_collision_clouds=true
	if OS.get_cmdline_user_args().has("--residency-diagnostics"):
		game.ground_cover.profiling_enabled=true;game.vegetation.renderer.profiling_enabled=true
		game.structures.blocks.set_process_profiling_enabled(true)
	if OS.get_cmdline_user_args().has("--residency-work-diagnostics"):game.ground_cover.profiling_enabled=true
	observer=Observer.new();observer.host=game;root.add_child(observer)
	game.terrain.stage_measured.connect(observer.stage)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for site:int in 2:
		var point:=Vector3(1882,44.05,1491) if site==0 else Vector3(1815,44.05,1844)
		game.teleport(point,point.y)
		if not check(await ready(),"Hotspot %d collision is ready"%site):break
		game.player_view.entry.finish();game.fly=false;game._clear_motion();game.needs_floor_spawn=false
		await walk("site_%d_idle"%site,0,600)
		await walk("site_%d_out"%site,KEY_S if site==0 else KEY_A,600)
		await walk("site_%d_back"%site,KEY_W if site==0 else KEY_D,600)
	check(observer.rows.size()>0 and observer.rows.size()<12000,"Bounded full cadence retained without truncation")
	if observer.manual_draw or observer.detached_present:check(observer.rows.any(func(row:Dictionary)->bool:return row.draw_calls>1000 and row.gpu_ms>0),"Presentation diagnostic retains actual scene rendering")
	check(observer.residency_events.size()<4096,"Bounded identity events retained without truncation")
	check(not observer.cloud_overflow and not observer.clouds.is_empty(),"Bounded posed collision corpus retained without truncation")
	observer.phase="setup";game.process_mode=Node.PROCESS_MODE_DISABLED
	if OS.get_cmdline_user_args().has("--capture-replay-view"):
		await RenderingServer.frame_post_draw
		var pixels:Image=root.get_texture().get_image();var capture:=pixels.save_jpg_to_buffer(.8)
		if check(capture.size()<=1024*1024,"Replay framebuffer fits its admitted 1 MiB output"):
			FileAccess.open(evidence.path_join("replay_view.jpg"),FileAccess.WRITE).store_buffer(capture)
	water_render_coverage()
	var inventory:=render_inventory() if observer.diagnostics or OS.get_cmdline_user_args().has("--render-ablation") else {}
	var ablation:Array=[]
	if OS.get_cmdline_user_args().has("--render-ablation"):ablation=await render_ablation()
	var collision_comparison:=compare_clouds()
	check(FileAccess.get_sha256(source)==original,"Original player save is unchanged")
	FileAccess.open(evidence.path_join("physics_residency.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"schema":1,"source":slot,"source_sha256":original,"seed":1703,"route":route,"samples":observer.rows,"ragdoll_transitions":observer.transitions,"clock_anchor":observer.clock_anchor,
		"residency_events":observer.residency_events,"population_legs":population_legs,"admission_trace":game.zombies.population.admission_trace,
		"collision_comparison":collision_comparison,
		"render_inventory":inventory,"render_ablation":ablation,"diagnostics":observer.diagnostics or OS.get_cmdline_user_args().has("--residency-work-diagnostics"),"manual_no_present":observer.manual_draw,"detached_present":observer.detached_present,"fps_cap":Engine.max_fps,"water_render_pages":game.lakes._render_pages.statistics(),
		"viewport":root.size,"window_mode":DisplayServer.window_get_mode(),"physics_hz":Engine.physics_ticks_per_second,"vsync":DisplayServer.window_get_vsync_mode(),
		"engine_settings":{"workers":ProjectSettings.get_setting("threading/worker_pool/max_threads",-1),"logical_processors":OS.get_processor_count(),"occlusion_rays_per_thread":ProjectSettings.get_setting("rendering/occlusion_culling/occlusion_rays_per_thread",512),"occlusion_enabled":root.use_occlusion_culling,"threaded_cull_minimum_instances":ProjectSettings.get_setting("rendering/limits/spatial_indexer/threaded_cull_minimum_instances",1000)},
		"scope":"Fixed physics-tick inputs on two saved-world hotspots; setup teleports are outside measurement. Physics tail includes engine queues and stepping. Actual source is read-only; this is a representative workload, not reconstruction of unrecorded human inputs."}))
	game.terrain.stage_measured.disconnect(observer.stage);observer.free()
	game.shutdown_requested=true;game.terrain.shutdown();game.free();await process_frame;await process_frame
	print("PHYSICS_RESIDENCY failures=",failures);quit(failures)
