# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	var terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.diagnostics_pause_streaming=true;terrain.backend.disk_cache.enabled=false
	terrain.backend.world_generator=2;terrain.focus=Vector3(800,60,1310);root.add_child(terrain)
	var vegetation=load("res://addons/vegetation/vegetation_world.gd").new();root.add_child(vegetation)
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(800,60,1310)
	check(vegetation.enable_trunk_collision() and vegetation.initialize()==OK,"renderer and trunk storage initialize")
	var ecosystem=load("res://addons/world_ecosystem/world_ecosystem.gd").new()
	ecosystem.terrain=terrain;ecosystem.vegetation=vegetation;ecosystem.camera=camera
	ecosystem.stream_radius=64;ecosystem.max_resident_cells=9;ecosystem.density=1
	root.add_child(ecosystem)
	check(terrain.start(StandardMaterial3D.new(),true)==OK,"temporary worker world starts")
	var deadline:=Time.get_ticks_msec()+15000
	while ecosystem.resident.size()<9 and Time.get_ticks_msec()<deadline: await process_frame
	check(ecosystem.resident.size()==9 and vegetation.renderer.roots.size()>2,"live scheduler populates nine vegetation owners")
	if vegetation.renderer.roots.size()<2:
		ecosystem.free();terrain.shutdown();terrain.free();vegetation.free();camera.free();quit(1);return
	var before: Dictionary={}
	var target: int=-1
	for id: int in vegetation.renderer.roots:
		var transform: Transform3D=vegetation.renderer.roots[id].t
		before[id]=transform
		if target<0 and Vector2(transform.origin.x-800,transform.origin.z-1310).length()<25: target=id
	if target<0: target=before.keys()[0]
	var center: Vector3=before[target].origin+Vector3(0,.2,0)
	var submitted:=Time.get_ticks_usec()
	check(terrain.construct_road_bed(center-Vector3(2,0,0),center+Vector3(2,0,0),2,8,12),"paving at existing root accepted by live worker")
	deadline=Time.get_ticks_msec()+10000
	while terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
	var published:=Time.get_ticks_usec()
	check(not terrain.pending_edit and terrain.last_edit_outcome.get("status","")=="published","road edit publishes")
	deadline=Time.get_ticks_msec()+5000
	while (vegetation.renderer.roots.has(target) or ecosystem._resample.size()>0 or ecosystem._requests.size()>0) and Time.get_ticks_msec()<deadline: await process_frame
	var reconciled:=Time.get_ticks_usec()
	check(not vegetation.renderer.roots.has(target) and not vegetation.trunk_collision.get_ids().has(target),"actual async surface result removes paved root and trunk")
	var neighbors:=0
	var intact:=true
	for id: int in before:
		var pos: Vector3=before[id].origin
		if Vector2(pos.x-center.x,pos.z-center.z).length()<10: continue
		neighbors+=1
		intact=intact and vegetation.renderer.roots.has(id) and vegetation.renderer.roots[id].t==before[id] and vegetation.trunk_collision.get_ids().has(id)
	check(neighbors>0 and intact,"roots outside small road footprint retain transforms and trunk records")
	check(ecosystem.rejected_batches==0 and ecosystem._resample.is_empty(),"live resampling drains without rejected batches")
	print("ROAD_VEGETATION_LIVE ",{"initial_roots":before.size(),"remaining_roots":vegetation.renderer.roots.size(),"verified_neighbors":neighbors,"edit_ms":(published-submitted)/1000.0,"after_publication_ms":(reconciled-published)/1000.0,"stale_results":ecosystem.stale_results,"scope":"Nine owners, real worker and signals, terrain mesh streaming paused; record membership, not visible fade or collider proxy contact."})
	check(terrain.construct_graded_bed(center-Vector3(2,0,0),center+Vector3(2,0,0),2,8,12,1),"stone repaint accepted by live worker")
	deadline=Time.get_ticks_msec()+10000
	while terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
	check(not terrain.pending_edit and terrain.last_edit_outcome.get("status","")=="published","stone material edit publishes")
	deadline=Time.get_ticks_msec()+5000
	while (not vegetation.renderer.roots.has(target) or not ecosystem._requests.is_empty() or not ecosystem._resample.is_empty()) and Time.get_ticks_msec()<deadline: await process_frame
	check(vegetation.renderer.roots.size()==before.size() and vegetation.renderer.roots.has(target) and vegetation.trunk_collision.get_ids().has(target),"live stone resampling restores original root membership")
	intact=true
	for id: int in before:
		intact=intact and vegetation.renderer.roots.has(id) and vegetation.renderer.roots[id].t==before[id] and vegetation.trunk_collision.get_ids().has(id)
	check(intact and ecosystem.rejected_batches==0,"restored roots retain original transforms and collision membership")
	ecosystem.free();terrain.shutdown();terrain.free();vegetation.free();camera.free()
	quit(0 if failures==0 else 1)
