# SPDX-License-Identifier: 0BSD
extends SceneTree
## Repeatable grounded workload at two human-capture hotspots. Source stays read-only.
class Observer extends Node:
	var host:Node
	var phase:="setup"
	var rows:Array[Dictionary]=[]
	var previous:=0
	var process_begin:=0
	var process_end:=0
	var draw_begin:=0
	var physics_begin:=0
	var physics_us:=0
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
	func _ready()->void:
		process_priority=1000000;process_physics_priority=1000000
		get_tree().process_frame.connect(begin_process)
		get_tree().physics_frame.connect(begin_physics)
		RenderingServer.frame_pre_draw.connect(begin_draw)
		RenderingServer.frame_post_draw.connect(end_draw)
	func finish_tail(now:int)->void:
		if tail_begin:tail_us+=now-tail_begin;tail_begin=0
	func begin_process()->void:process_begin=Time.get_ticks_usec();finish_tail(process_begin)
	func begin_physics()->void:physics_begin=Time.get_ticks_usec();finish_tail(physics_begin)
	func _physics_process(_delta:float)->void:
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
	func _process(_delta:float)->void:process_end=Time.get_ticks_usec()
	func begin_draw()->void:draw_begin=Time.get_ticks_usec()
	func stage(label:String,ms:float)->void:stages[label]=float(stages.get(label,0.0))+ms
	func end_draw()->void:
		var now:=Time.get_ticks_usec()
		if is_instance_valid(host):
			for corpse:Node in host.corpse_loot.active.values():
				if not corpse.ragdoll_profile.has("end_us") or known_transitions.has(corpse.get_instance_id()):continue
				known_transitions[corpse.get_instance_id()]=true
				var event:Dictionary=corpse.ragdoll_profile.duplicate();event.phase=phase;event.frame=Engine.get_process_frames()
				event.corpse_id=corpse.get_meta("corpse_identity",0);event.resident_id=corpse.get_meta("world_zombie_id",0)
				transitions.append(event)
				if phase!="setup":
					for part:String in corpse.collision_clouds:
						var points:PackedVector3Array=corpse.collision_clouds[part]
						if clouds.size()>=512 or cloud_vertices+points.size()>524288:cloud_overflow=true;continue
						clouds.append({"corpse_id":event.corpse_id,"part":part,"phase":phase,"points":points});cloud_vertices+=points.size()
				corpse.collision_clouds.clear()
		if previous and phase!="setup" and is_instance_valid(host) and rows.size()<12000:
			rows.append({"phase":phase,"at_us":now,"frame_ms":(now-previous)/1000.0,
				"before_process_ms":(process_begin-previous)/1000.0,"process_ms":(process_end-process_begin)/1000.0,
				"draw_ms":(now-draw_begin)/1000.0,"physics_ms":physics_us/1000.0,"physics_tail_ms":tail_us/1000.0,
				"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
				"position":host.player.position,"zombies":host.zombies.residents.size(),
				"zombie_us":host.zombies.update_phase_us.duplicate(),"corpse_us":host.corpse_loot.update_profile.duplicate(),
				"terrain_ms":stages,"loading":host.loading_active,"physics_active":Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
				"physics_pairs":Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),"physics_islands":Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)})
		previous=now;physics_us=0;tail_us=0;stages={}
	func _exit_tree()->void:
		RenderingServer.frame_pre_draw.disconnect(begin_draw)
		RenderingServer.frame_post_draw.disconnect(end_draw)

var game:Node
var observer:Observer
var evidence:=""
var slot:="Hidden_Meadow"
var failures:=0
var route:Array[Dictionary]=[]
var population_legs:Array[Dictionary]=[]
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
		var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(points.to_byte_array())
		var row:={"part":captured.part,"corpse_id":captured.corpse_id,"phase":captured.phase,"input_points":points.size(),"sha256":hash.finish().hex_encode(),"pairs":[]}
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
	observer.phase=phase
	var start:Vector3=game.player.position
	if key:game.controls.set_key(key,true,Time.get_ticks_usec())
	for tick in ticks:
		game.app_focused=true
		game.yaw=.2*sin(TAU*tick/float(ticks));game.player.rotation.y=game.yaw
		await physics_frame
	if key:game.controls.set_key(key,false,Time.get_ticks_usec())
	route.append({"phase":phase,"ticks":ticks,"start":start,"end":game.player.position,"distance":start.distance_to(game.player.position),"living":game.zombies.residents.size(),"corpses":game.corpse_loot.active.size()})
	population_legs.append({"phase":phase,"residents":observer.resident_snapshot.duplicate(true),"corpse_ids":game.corpse_loot.active.keys(),"population":game.zombies.population.status()})
	print("RESIDENCY_LEG ",JSON.stringify(route.back()))
	observer.phase="setup"
func run()->void:
	if not check(DisplayServer.get_name()!="headless","Rendered frame cadence is available"):quit(1);return
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
	root.add_child(game)
	if not check(await ready(),"Player world loads read-only"):game.free();quit(1);return
	game.player_view.entry.finish();game.session_menu.set_open(false)
	game.session_menu.developer_hud.mouse_access=true
	game.zombies.profiling_enabled=true
	game.zombies.capture_collision_clouds=true
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
	check(observer.residency_events.size()<4096,"Bounded identity events retained without truncation")
	check(not observer.cloud_overflow and not observer.clouds.is_empty(),"Bounded posed collision corpus retained without truncation")
	observer.phase="setup";game.process_mode=Node.PROCESS_MODE_DISABLED
	var collision_comparison:=compare_clouds()
	check(FileAccess.get_sha256(source)==original,"Original player save is unchanged")
	FileAccess.open(evidence.path_join("physics_residency.json"),FileAccess.WRITE).store_string(JSON.stringify({
		"schema":1,"source":slot,"source_sha256":original,"seed":1703,"route":route,"samples":observer.rows,"ragdoll_transitions":observer.transitions,
		"residency_events":observer.residency_events,"population_legs":population_legs,
		"collision_comparison":collision_comparison,
		"viewport":root.size,"physics_hz":Engine.physics_ticks_per_second,"vsync":DisplayServer.window_get_vsync_mode(),
		"scope":"Fixed physics-tick inputs on two saved-world hotspots; setup teleports are outside measurement. Physics tail includes engine queues and stepping. Actual source is read-only; this is a representative workload, not reconstruction of unrecorded human inputs."}))
	game.terrain.stage_measured.disconnect(observer.stage);observer.free()
	game.shutdown_requested=true;game.terrain.shutdown();game.free();await process_frame;await process_frame
	print("PHYSICS_RESIDENCY failures=",failures);quit(failures)
