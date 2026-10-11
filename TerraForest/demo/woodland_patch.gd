# SPDX-License-Identifier: 0BSD
extends SceneTree
const Tokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
var game: Node3D
var failures:=0
var checks:=0
var replies: Dictionary={}
var inspect:=false
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func sample(points: PackedVector3Array) -> Dictionary:
	var token:=Tokens.allocate();var deadline:=Time.get_ticks_msec()+15000
	while not game.terrain.request_surface_batch(points,token):
		if Time.get_ticks_msec()>deadline:return {}
		await process_frame
	while not replies.has(token):
		if Time.get_ticks_msec()>deadline:return {}
		await process_frame
	var reply: Dictionary=replies[token];replies.erase(token);return reply
func wait_cover() -> void:
	var deadline:=Time.get_ticks_msec()+20000
	while (not game.ground_cover._dirty.is_empty() or not game.ground_cover._requests.is_empty() or not game.ground_cover._support_job.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
func stop() -> void:
	game.shutdown_requested=true
	await game.terrain.shutdown_after_edits();game.free();await process_frame
	quit(1 if failures else 0)
func run() -> void:
	inspect="--woodland-inspect" in OS.get_cmdline_user_args()
	var smoke: bool="--woodland-smoke" in OS.get_cmdline_user_args()
	var path: String=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--derived-cache="):path=arg.trim_prefix("--derived-cache=")
	if not path.begins_with("user://woodland_patch_") or not preload("res://addons/volumetric_terrain/derived_cache.gd")._safe_component(path.trim_prefix("user://")) or DirAccess.dir_exists_absolute(path):
		push_error("Use the woodland preview launcher with a fresh isolated cache");quit(2);return
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.ground_enabled=true
	game.max_fps=60;game.background_fps=60
	root.add_child(game)
	game.terrain.backend.disable_snapshot_writes("Disposable woodland art preview")
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"temporary forest world ready")
	if game.loading_active:await stop();return
	game.set_physics_process(false);game._clear_motion()
	game.terrain.surface_batch_ready.connect(func(token,points,normals,_epoch,_revision):replies[token]={"points":points,"normals":normals})
	# Straddle four existing32m owners, respecting256 authored records per owner.
	var center:=Vector3(roundf(game.player.position.x/32.0)*32,0,roundf(game.player.position.z/32.0)*32)
	var cover=game.ground_cover
	deadline=Time.get_ticks_msec()+20000
	while cover.resident.size()<49 and Time.get_ticks_msec()<deadline:await process_frame
	cover.set_process(false)
	# Drain existing support work before staging the patch.
	deadline=Time.get_ticks_msec()+10000
	while not cover._requests.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	var rng:=RandomNumberGenerator.new();rng.seed=1703
	var counts: Array[int]=[0,0,0,0,0,0,0,0];var placed_ids:=PackedInt64Array();var owners: Dictionary={}
	for row in 32:
		var points:=PackedVector3Array()
		for col in 32:
			points.append(center+Vector3((col-15.5)*0.45+rng.randf_range(-0.12,0.12),0,(row-15.5)*0.45+rng.randf_range(-0.12,0.12)))
		var surface: Dictionary=await sample(points)
		if surface.is_empty():check(false,"patch terrain sampling completed");await stop();return
		for col in 32:
			var point: Vector3=surface.points[col]
			if surface.normals[col].y<0.82:continue
			var local: Vector3=point-center
			# Gentle open footpath; fern clusters flank it, mixed grass elsewhere.
			if absf(local.x-sin(local.z*0.35)*0.9)<0.55:continue
			var clustered: bool=sin(local.x*0.9)*cos(local.z*0.65)>0.55
			var species: int=1 if clustered and rng.randf()<0.42 else (0 if rng.randf()<0.025 else 2)
			var scale: float=rng.randf_range(0.85,1.4)
			var pose:=Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),point-Vector3.UP*0.03)
			var accent: float=rng.randf()
			if species==2:
				if accent<0.015: species=3+rng.randi_range(0,2)
				elif accent<0.04: species=6
				elif accent<0.07: species=7
			var id: int=cover.removed.add(species,pose)
			if id==0:check(false,"authored patch stays within capacity");await stop();return
			counts[species]+=1;placed_ids.append(id)
			owners[Vector2i(floori(point.x/32),floori(point.z/32))]=true
	check(placed_ids.size()>=700 and owners.size()<=4,"dense patch admitted within four bounded owners")
	for key in owners:cover._dirty[key]=true
	cover.set_process(true);await wait_cover()
	var published_authored:=0
	for key in owners:
		for species in cover.resident.get(key,[]):
			for id in species.ids:
				if id>=4294967296:published_authored+=1
	check(published_authored==placed_ids.size() and cover.rejected_batches==0,"all patch items publish through normal support, picking and render batches")
	var views:=PackedVector3Array([center,center+Vector3(0,0,7),center+Vector3(5,0,4)])
	var heights: Dictionary=await sample(views)
	if heights.is_empty():check(false,"viewpoint sampling completed");await stop();return
	var label:=Label.new();label.position=Vector2(400,32);label.add_theme_font_size_override("font_size",22)
	label.text="WOODLAND DENSITY REVIEW / disposable world\n%d grass clumps · %d plants · %d stones / 14.4 × 14.4 m\nWASD move · mouse look · H remove/place · G fly"%[counts[2],counts[1],counts[0]]
	label.text+="\n%d rare flowers / %d bushes / %d twig clusters"%[counts[3]+counts[4]+counts[5],counts[6],counts[7]]
	root.add_child(label)
	DirAccess.make_dir_recursive_absolute("res://reports/woodland_patch")
	for view in 2:
		game.camera.global_position=heights.points[view+1]+Vector3.UP*1.65
		game.camera.look_at(heights.points[0]+Vector3.UP*0.3)
		for frame in 30:await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/woodland_patch/player_%d.png"%view)
	var presentation: Dictionary=preload("res://addons/presentation/fullscreen_policy.gd").measurement(root)
	check(presentation.fair_graphical_sample and Engine.max_fps==60,"full resolution1080p cap60")
	# A short observation after screenshot readback settles, not an optimization
	# loop or sustained qualification. Keep a missed18.5ms p95 gate visible.
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	for frame in 30:await RenderingServer.frame_post_draw
	var frames: Array[float]=[];var gpu: Array[float]=[];var previous:=Time.get_ticks_usec()
	for frame in 120:
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec();frames.append((now-previous)/1000.0);previous=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	frames.sort();gpu.sort()
	var result:={"checks":checks,"failures":failures,"counts_by_species":counts,"authored":placed_ids.size(),"published_authored":published_authored,"area_m2":14.4*14.4,"owners":owners.size(),"center":[center.x,center.z],"presentation":presentation,"scope":"Dense visual review on actual forest terrain, interactive authored identities. Published count is supported resident records, not a count of pixels or frustum visibility. Not a global density change or performance qualification."}
	result["short_cost"]={"frames":120,"frame_p95_ms":frames[113],"frame_max_ms":frames[119],"gpu_p95_ms":gpu[113],"frame_p95_gate_ms":18.5,"frame_gate_pass":frames[113]<=18.5,"gpu":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name()}
	if "--grass-texture-compare" in OS.get_cmdline_user_args():
		var before: PackedByteArray=cover.removed.capture_storage_snapshot()
		var comparisons: Array=[]
		cover.grass_material.set_shader_parameter("wind_strength",0.0)
		for mode in [false,true,false]:
			check(cover.set_grass_texture(mode),"optional grass material toggles")
			label.text="GRASS TEXTURE REVIEW / "+("SUBTLE" if mode else "OFF")+" / F7 toggles in play preview"
			for frame in 40:await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/woodland_patch/texture_%d.png"%comparisons.size())
			for frame in 20:await RenderingServer.frame_post_draw
			var costs: Array[float]=[]
			for frame in 90:
				await RenderingServer.frame_post_draw
				costs.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			costs.sort();comparisons.append({"enabled":mode,"gpu_p50_ms":costs[44],"gpu_p95_ms":costs[85]})
		check(cover.removed.capture_storage_snapshot()==before and not cover.grass_texture_enabled,"texture comparison preserves placements and restores default off")
		cover.grass_material.set_shader_parameter("wind_strength",1.0)
		result["texture_comparison"]=comparisons
		result["checks"]=checks;result["failures"]=failures
	var file:=FileAccess.open("res://reports/woodland_patch/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("WOODLAND_PATCH ",JSON.stringify(result))
	if (not inspect and not smoke) or failures:label.free();await stop();return
	# Restore regular player control at the path entrance. Edits remain disposable.
	game.player.position=heights.points[1]+Vector3.UP*0.12;game.player.velocity=Vector3.ZERO;game.fly=false
	game.camera.position=Vector3(0,1.68,0);game.camera.rotation=Vector3.ZERO
	game.player.rotation.y=0;game.set_physics_process(true)
	if smoke:
		for frame in 60:await physics_frame
		check(game.camera.position.is_equal_approx(Vector3(0,1.68,0)) and absf(game.player.position.y-heights.points[1].y)<0.5,"preview hands off at normal eye height with ground collision")
		print("WOODLAND_HANDOFF failures=",failures)
		label.free();await stop();return
	game.background_fps=15;game._refresh_frame_cap()
	label.text+="\nEdits are discarded on close."
