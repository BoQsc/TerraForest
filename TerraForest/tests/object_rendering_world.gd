# SPDX-License-Identifier: 0BSD
extends SceneTree
## Read-only player world, 1,000 persistent-model records, normal gameplay ticks.
const Packs=preload("res://addons/structures/pack_registry.gd")
var game: Node
var folder:=""
var source:="user://worlds/Hidden_Meadow.trw"
var source_hash:=""
var origin:=Vector3(1882,64,1491)
var checks:=0
var failures:=0
var gate:=false
var mixed_packs:=false
var added_object_count:=1000
var definitions: Array=[]
var expected_counts: Dictionary={}
var report: Dictionary={"schema":1,"scope":"Read-only Hidden_Meadow; collision test floor with 1000 native pack objects; normal gameplay, AI, pickups, terrain, water, vegetation, actors and vehicle fleet remain enabled","legs":[]}
class Observer extends Node:
	var host: Node
	var phase:="setup"
	var rows: Array=[]
	var previous:=0
	var physics_ticks:=0
	var invalid_ticks:=0
	var max_zombies:=0
	var max_pickups:=0
	var stages: Dictionary={}
	func stage(label: String,ms: float) -> void:
		if phase=="setup": return
		var key:=phase+"/"+label
		if not stages.has(key): stages[key]=[]
		if stages[key].size()<20000: stages[key].append(ms)
	func _input(_event: InputEvent) -> void: get_viewport().set_input_as_handled()
	func _ready() -> void: process_priority=1000000; process_physics_priority=1000000
	func _physics_process(_delta: float) -> void:
		if phase=="setup": return
		physics_ticks+=1
		if not host.is_physics_processing() or host.loading_active or host.player_hud.inventory_open or host.session_menu.pauses_world() or host.player_life.dead or host.fly or not host.zombies.population_enabled or not host.pickups.physics_enabled or not host.ground_enabled or host.actors.pool==null or not host.world_vehicle.fleet_enabled: invalid_ticks+=1
		max_zombies=maxi(max_zombies,host.zombies.residents.size())
		max_pickups=maxi(max_pickups,int(host.pickups.physics.statistics().active))
	func _process(_delta: float) -> void:
		host.app_focused=true
		var now:=Time.get_ticks_usec()
		if phase!="setup" and previous>0 and rows.size()<20000:
			rows.append([phase,(now-previous)/1000.0,RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),float(host.object_inspector.stats.get("query_layout_us",0)),host.player.position.x,host.player.position.y,host.player.position.z])
		previous=now
var observer: Observer
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="): folder=arg.trim_prefix("--check-evidence-dir=")
		if arg=="--require-60fps": gate=true
		if arg=="--mixed-packs": mixed_packs=true
		if arg=="--ground-level": origin.y=44.25
		if arg=="--control-no-added-objects": added_object_count=0
	report.stage_height=origin.y
	report.added_object_count=added_object_count
	if added_object_count==0: report.scope="CONTROL without added props; same read-only world, collision floor, route and enabled gameplay systems"
	run.call_deferred()
func check(value: bool,label: String) -> bool:
	checks+=1
	if not value: failures+=1
	print("PASS " if value else "FAIL ",label); return value
func ticks(count: int) -> void:
	for tick in count: game.app_focused=true; await physics_frame
func percentile(values: Array,quantile: float) -> float:
	if values.is_empty(): return 0
	var sorted:=values.duplicate(); sorted.sort(); return float(sorted[mini(sorted.size()-1,int(ceil((sorted.size()-1)*quantile)))])
func run() -> void:
	if not check(DisplayServer.get_name()!="headless" and FileAccess.file_exists(source),"renderer and existing read-only source available"): quit(1); return
	source_hash=FileAccess.get_sha256(source); report.source_sha256=source_hash
	report.runtime_sha256={}
	for path: String in ["res://addons/structures/pack_render_mesh.gd","res://addons/structures/pack_registry.gd","res://addons/player_runtime/object_inspector.gd","res://addons/structures/structures_world.gd"]: report.runtime_sha256[path]=FileAccess.get_sha256(path)
	seed(1703)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot=Hidden_Meadow","--snapshot-readonly","--temporary","--no-derived-cache","--gameplay-construction","--ground-cover","--actors","--vehicle-fleet"]),true)
	ProjectSettings.set_setting("terraforest/pistol_trial_settings_path","")
	var started:=Time.get_ticks_msec()
	game=load("res://demo/world.tscn").instantiate(); game.temporary_world=true; game.background_fps=60; root.add_child(game)
	observer=Observer.new(); observer.host=game; root.add_child(observer)
	game.terrain.stage_measured.connect(observer.stage)
	var deadline:=Time.get_ticks_msec()+120000
	while game.loading_active and Time.get_ticks_msec()<deadline: game.app_focused=true; await process_frame
	report.loading_ms=Time.get_ticks_msec()-started
	if not check(game.startup_complete and not game.loading_active,"ordinary saved world loads without modifying its source"): await finish(); return
	game.player_view.entry.finish(); game.session_menu.set_open(false)
	if game.session_menu.developer: game.session_menu.toggle_developer()
	game.fly=false; game.needs_floor_spawn=false
	game.session_menu.developer_hud.hidden_by_user=true; game.session_menu.developer_hud.refresh()
	check(game.ground_enabled and game.actors.pool!=null and game.world_vehicle.fleet_enabled and game.zombies.population_enabled and game.pickups.physics_enabled,"normal simulation features enabled")
	# Keep fixture support independent of saved-world block paging. The ordinary
	# terrain/building systems continue running beneath this in-memory platform.
	var floor_body:=StaticBody3D.new(); floor_body.collision_layer=2; floor_body.collision_mask=0
	floor_body.position=origin+Vector3(2,-.5,38)
	var floor_shape:=BoxShape3D.new(); floor_shape.size=Vector3(65,1,85)
	var floor_collision:=CollisionShape3D.new(); floor_collision.shape=floor_shape; floor_body.add_child(floor_collision)
	var floor_mesh:=BoxMesh.new(); floor_mesh.size=floor_shape.size
	var floor_material:=StandardMaterial3D.new(); floor_material.albedo_color=Color(.32,.34,.29); floor_material.roughness=1.0; floor_mesh.material=floor_material
	var floor_visual:=MeshInstance3D.new(); floor_visual.mesh=floor_mesh; floor_body.add_child(floor_visual); game.add_child(floor_body)
	definitions=Packs.objects.values() if mixed_packs else Packs.objects_for_pack("terraforest.outdoor_01")
	report.pack_mix="all Homestead 01-10 and Outdoor 01" if mixed_packs else "Outdoor 01"
	var count:=0; var assets: Array=[]
	for row: Dictionary in definitions:
		var path: String=row.directory+"/models/"+row.id+".tres"; var mesh: ArrayMesh=load(path); var triangles:=0
		for surface in mesh.get_surface_count(): triangles+=mesh.surface_get_array_index_len(surface)/3
		var render_mesh: Mesh=preload("res://addons/structures/pack_render_mesh.gd").prepare(mesh)
		assets.append({"id":row.key,"sha256":FileAccess.get_sha256(path),"triangles":triangles,"surfaces":mesh.get_surface_count(),"render_surfaces":render_mesh.get_surface_count(),"lod_levels":render_mesh.get_meta("pack_lod_levels",0)})
	report.assets=assets
	for index in added_object_count:
		var column:=index%25; var x:=float(column-12 if column<12 else column-10)*2.2
		var point:=origin+Vector3(x,0,float(index/25)*1.9)
		var row: Dictionary=definitions[index%definitions.size()]; var batch: Node3D=game.structures.model(row.key)
		if batch.insert_instance(game.model_tool.records(Transform3D(Basis.IDENTITY,point),batch),AABB())>0:
			count+=1; expected_counts[row.key]=int(expected_counts.get(row.key,0))+1
	check(count==added_object_count,"all requested objects inserted: "+str(added_object_count)+"; no shadow reduction")
	place_player(Vector3(1,.03,68),0)
	await ticks(300)
	if not check(game.player.is_on_floor() and absf(game.player.position.y-origin.y)<.2,"player stands on real collision before timing"): await finish(); return
	var spawned:=0
	for i in 4:
		if game.zombies.spawn_at(origin+Vector3(-28,.05,24+i*8),false,true)!=null: spawned+=1
	for i in 2: game.actors.spawn(origin+Vector3(32,.1,28+i*8))
	report.added_zombies=spawned
	check(not game.zombies.residents.is_empty(),"live zombie residents participate in normal AI")
	check(game.player_hud.inventory.grant(224,24,game.player_hud.inventory.snapshot().revision).ok,"supply ordinary moving-item workload")
	await ticks(180)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps=0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var actor_steps: int=game.actors.simulation_steps
	for names_on in [false,true]:
		for returning in [false,true]:
			await walk(names_on,returning)
	check(observer.invalid_ticks==0 and observer.physics_ticks>=2400,"every measured physics tick keeps ordinary gameplay systems running")
	check(game.actors.simulation_steps-actor_steps>=2400 and observer.max_zombies>0 and observer.max_pickups>0,"actor simulation, live AI and physical drops execute during walking")
	check(observer.rows.size()>1000 and observer.rows.size()<20000,"complete bounded frame trace retained")
	report.physics_ticks=observer.physics_ticks; report.invalid_ticks=observer.invalid_ticks; report.max_zombies=observer.max_zombies; report.max_physical_drops=observer.max_pickups
	report.actor_steps=game.actors.simulation_steps-actor_steps; report.gpu=RenderingServer.get_video_adapter_name(); report.viewport=str(root.size)
	report.model_horizon=game.structures._model_horizon.statistics() if game.structures._model_horizon!=null else {}
	check(bool(report.model_horizon.get("ready",false)) and report.model_horizon.get("error","") == "" and int(report.model_horizon.get("records",-1))==int(report.model_horizon.get("rendered",-2)) and int(report.model_horizon.get("pending_uploads",-1))==0,"all native model records have rendered representations without pending uploads")
	var counts: Dictionary={}
	var intact:=true
	for row: Dictionary in definitions:
		counts[row.key]=game.structures.model(row.key).get_ids().size()
		intact=intact and counts[row.key]>=expected_counts.get(row.key,0)
	report.object_counts=counts
	check(intact,"all "+str(added_object_count)+" added object records remain resident through walking")
	report.stages={}
	for key: String in observer.stages:
		report.stages[key]={"samples":observer.stages[key].size(),"p95_ms":percentile(observer.stages[key],.95),"p99_ms":percentile(observer.stages[key],.99)}
	report.source_unchanged=FileAccess.get_sha256(source)==source_hash
	check(report.source_unchanged,"player save hash is unchanged")
	await finish()
func place_player(local: Vector3,yaw: float) -> void:
	game._clear_motion(); game.player.position=origin+local; game.player.velocity=Vector3.ZERO; game.yaw=yaw; game.pitch=0.0; game.player.rotation.y=yaw; game.camera.rotation=Vector3.ZERO; game.camera.position=Vector3(0,1.62,0)
	game.needs_floor_spawn=false; game.app_focused=true; Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func drop_items() -> void:
	var state: Dictionary=game.player_hud.inventory.snapshot(); var slot:=-1
	for i in state.slots.size():
		if state.slots[i].item==224: slot=i; break
	if slot<0: return
	for i in 4:
		var point: Vector3=game.player.position+Vector3(.6,1.8+i*.15,0)
		var result: Dictionary=game.pickups.drop_stack(game.player_hud.inventory,slot,game.player_hud.inventory.snapshot().revision,point,1,true,Vector3(1,1,-1))
		check(result.ok,"ordinary physical drop admitted")
func walk(names_on: bool,returning: bool) -> void:
	place_player(Vector3(1,.03,13 if returning else 68),PI if returning else 0.0)
	game.object_inspector.enabled=names_on; game.object_inspector.nearby_names=names_on; game.object_inspector.stats={}
	await ticks(120)
	var phase:="names_"+("on" if names_on else "off")+("_return" if returning else "_out")
	print("OBJECT_RENDER_PHASE ",phase)
	var first:=observer.rows.size(); var start: Vector3=game.player.position; observer.phase=phase; observer.previous=0
	game.controls.set_key(KEY_W,true,Time.get_ticks_usec()); drop_items(); await ticks(600); game.controls.set_key(KEY_W,false,Time.get_ticks_usec())
	observer.phase="setup"; game._clear_motion()
	var times: Array=[]; var gpu: Array=[]; var cpu: Array=[]; var physics: Array=[]; var draws: Array=[]; var primitives: Array=[]; var missed:=0
	for index in range(first,observer.rows.size()):
		var row: Array=observer.rows[index]; times.append(row[1]); gpu.append(row[2]); cpu.append(row[3]); physics.append(row[4]); draws.append(row[5]); primitives.append(row[6]); missed+=int(row[1]>1000.0/60.0)
	var result: Dictionary={"phase":phase,"frames":times.size(),"distance":start.distance_to(game.player.position),"p50_ms":percentile(times,.5),"p95_ms":percentile(times,.95),"p99_ms":percentile(times,.99),"worst_ms":percentile(times,1),"gpu_p95_ms":percentile(gpu,.95),"render_cpu_p95_ms":percentile(cpu,.95),"physics_p95_ms":percentile(physics,.95),"draw_calls_p95":percentile(draws,.95),"primitives_p95":percentile(primitives,.95),"over_16_67_ms":missed}
	report.legs.append(result); print("OBJECT_RENDER_RESULT ",JSON.stringify(result))
	check(result.distance>45 and absf(game.player.position.y-origin.y)<.2 and game.player.is_on_floor(),"grounded player walks through dense scene: "+phase)
	if gate: check(result.p95_ms<=1000.0/60.0 and result.p99_ms<=1000.0/60.0,"60 FPS frame budget at p95 and p99: "+phase)
	if names_on:
		await process_frame; await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(folder.path_join(phase+".png"))==OK,"capture "+phase)
func finish() -> void:
	if observer!=null: observer.phase="setup"
	if game!=null:
		game._clear_motion(); game.shutdown_requested=true; check(await game.terrain.shutdown_after_edits(),"read-only gameplay shuts down cleanly"); game.free()
	report.checks=checks; report.failures=failures
	report.columns=["phase","frame_ms","gpu_ms","render_cpu_ms","physics_ms","draw_calls","primitives","last_inspection_us","x","y","z"]
	report.samples=observer.rows if observer!=null else []
	if observer!=null: observer.free()
	var encoded:=JSON.stringify(report)
	if encoded.length()>8*1024*1024: print("FAIL trace exceeds declared 8 MiB"); failures+=1
	else: FileAccess.open(folder.path_join("object_rendering.json"),FileAccess.WRITE).store_string(encoded)
	await process_frame; await process_frame
	print("OBJECT_RENDERING_WORLD checks=",checks," failures=",failures); quit(1 if failures else 0)
