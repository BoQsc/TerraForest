# SPDX-License-Identifier: 0BSD
extends SceneTree
# Real walking/physics with normal streaming and actors. Only input admission is
# overridden for the nonactivating test window; no position replay or paused world.
class WalkingWorld extends "res://demo/world.gd":
	func _movement_input_available() -> bool:
		return not loading_active and not shutdown_requested and not session_menu.visible_ui() and not player_hud.inventory_open and not player_view.entry.active and not player_life.dead and not world_editor_active()
var game: Node
var output := ""
var slot := "Homestead_Valley"
var control := false
var approach_review := false
var stone_page_states := {}
var stone_page_transitions: Array=[]
var preparation: Array=[]
var invalid_play_frames := 0
var capture_start := Vector3.ZERO
var previous_control := false
var fern_trial := false
var fern_cluster_trial := false
var rows: Array[Dictionary] = []
var phase := "loading"
var travelled := 0.0
var previous := Vector3.ZERO
var last_frame := 0
var captures := StreamPeerBuffer.new()
var evidence_bytes := 0
var failures: Array[String] = []
var captured := 0
var physics_frames := 0
var initial_cover := {}
var grounded_frames := 0
var source_hash := ""
var runtime_hashes := {}
var capture_times: Array[int] = []
var capture_images: Array[Image] = []
var walking_context: Image
var initial_forest := {}
var detail_render_pages := {}
var asynchronous := preload("res://tests/fixtures/vegetation_capture.gd").new()
var capture_frame_ids: Array[int] = []
var capture_hashes: Array[String] = []
var capture_count := 48
var fullframe_port := 0
var fullframe_token := ""
var fullframe_peer := StreamPeerTCP.new()
var near_review := false
var near_candidate:ArrayMesh
var near_baseline:ArrayMesh
var near_cost_mode := "candidate"
var near_page_states:Dictionary={}
var near_page_transitions:Array=[]
var near_band_frames:=0
var post_walk_near_control:Dictionary={}

func check_near_after_walk() -> void:
	# All physical movement and timing have finished. This separate frozen
	# comparison checks nearby appearance and the camera negative control.
	game.process_mode=Node.PROCESS_MODE_DISABLED;Engine.time_scale=0.0
	var saved_shaders:Dictionary={}
	var mats:Array=game.ground_cover.foliage_materials.duplicate()
	for mesh in [near_candidate,near_baseline]:
		for surface in mesh.get_surface_count():
			if not mats.has(mesh.surface_get_material(surface)):mats.append(mesh.surface_get_material(surface))
	for mat:ShaderMaterial in mats:
		saved_shaders[mat]=mat.shader
		var frozen:=Shader.new();frozen.code=mat.shader.code.replace("shader_type spatial;","shader_type spatial;\nuniform float comparison_time=0.0;").replace("TIME","comparison_time")
		mat.shader=frozen;mat.set_shader_parameter("cover_clock",1000000.0);mat.set_shader_parameter("comparison_time",0.0)
	var camera:Camera3D=game.camera
	var prior_local:=camera.transform
	var eye:=camera.global_position
	camera.global_transform=Transform3D(Basis.looking_at(Vector3(0,-1.6,-1.1)),eye)
	for mat:ShaderMaterial in mats:mat.set_shader_parameter("cover_eye",camera.global_position)
	var reference:=PackedByteArray()
	for candidate in [false,true]:
		select_near(candidate)
		for batch in game.ground_cover.batches:batch.update_surface_lod()
		for frame in 20:await RenderingServer.frame_post_draw
		var view:=root.get_texture().get_image();view.convert(Image.FORMAT_RGB8)
		var pixels:=view.get_region(Rect2i(0,320,1920,580)).get_data()
		if not candidate:reference=pixels
		else:post_walk_near_control["near_pixels_equal"]=pixels==reference
	var fixed_local:=camera.transform
	var fixed_global:=camera.global_transform
	var negative:Array=[]
	for iteration in 3:
		camera.global_position=eye;camera.look_at(eye+Vector3(0,-1.6,-1.1))
		for frame in 2:await RenderingServer.frame_post_draw
		var view:=root.get_texture().get_image();view.convert(Image.FORMAT_RGB8)
		negative.append({"same_transform":var_to_bytes(camera.global_transform)==var_to_bytes(fixed_global),"same_pixels":view.get_region(Rect2i(0,320,1920,580)).get_data()==reference})
	camera.transform=fixed_local
	for frame in 8:await RenderingServer.frame_post_draw
	var restored:=root.get_texture().get_image();restored.convert(Image.FORMAT_RGB8)
	post_walk_near_control["legacy_assignments"]=negative
	post_walk_near_control["exact_local_restore"]=restored.get_region(Rect2i(0,320,1920,580)).get_data()==reference
	check(post_walk_near_control.near_pixels_equal,"nearby pixels match baseline after normal gameplay")
	check(post_walk_near_control.exact_local_restore,"exact local camera restore preserves nearby pixels")
	camera.transform=prior_local
	for mat in saved_shaders:mat.shader=saved_shaders[mat]
	game.process_mode=Node.PROCESS_MODE_INHERIT;Engine.time_scale=1.0

func select_near(candidate:bool) -> void:
	near_cost_mode="candidate" if candidate else "baseline"
	var cover:Node=game.ground_cover
	var mesh:ArrayMesh=near_candidate if candidate else near_baseline
	var previous_mesh:ArrayMesh=cover.preview_meshes[2]
	for surface in previous_mesh.get_surface_count():cover.foliage_materials.erase(previous_mesh.surface_get_material(surface))
	for surface in mesh.get_surface_count():cover.foliage_materials.append(mesh.surface_get_material(surface))
	cover.preview_meshes[2]=mesh;cover.grass_material=mesh.surface_get_material(0)
	check(cover.batches[2].configure_asset("ground_cover/2/v1",mesh),"near comparison changes only grass mesh")
	check(preload("res://addons/world_ecosystem/filtered_grass.gd").configure_batch(cover.batches[2],mesh),"near comparison retains native surface LOD")

func _initialize() -> void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value: failures.append(message)
	print("CHECK ","PASS " if value else "FAIL ",message)

func write_bytes(name: String, bytes: PackedByteArray) -> void:
	evidence_bytes+=bytes.size()
	if evidence_bytes>16*1024*1024:
		push_error("Gameplay evidence exceeds admitted capture cap");quit(1);return
	FileAccess.open(output.path_join(name),FileAccess.WRITE).store_buffer(bytes)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new();event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()

func ready_within(predicate: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<end:
		await process_frame;game.app_focused=true
	return predicate.call()

func physics_tick() -> void:
	physics_frames+=1
	if game.player.is_on_floor():grounded_frames+=1

func playable() -> bool:
	return game.startup_complete and not game.loading_active and not game.loading_layer.visible and not game.waiting_spawn and not game.needs_floor_spawn and not game.player_life.dead and not game.player_view.entry.pending and not game.player_view.entry.active and not game.player_view.entry.waking

func observe_preparation(label: String) -> void:
	var state := {"stage":label,"time_ms":Time.get_ticks_msec(),"position":str(game.player.position),"loading":game.loading_active,"life":game.player_life.state.snapshot(),"messages":game.recent_action_messages.duplicate()}
	preparation.append(state);print("PREPARATION ",JSON.stringify(state))

func approach_heading() -> float:
	# Select an ordinary walkable departure while the normal pause menu is open.
	# Do not disable enemies, collisions or change health to force a passing walk.
	var space: PhysicsDirectSpaceState3D=game.get_world_3d().direct_space_state
	var best := -INF;var heading := 0.0
	for direction in 16:
		var angle := direction*TAU/16.0
		var forward := Vector3(-sin(angle),0,-cos(angle))
		var clear_steps := 0;var separation := 96.0
		for step in range(1,9):
			var point: Vector3=game.player.position+forward*step*6.0
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*20,point-Vector3.UP*20,7,[game.player.get_rid()]))
			if hit.is_empty() or hit.normal.y<0.85 or game.lakes.depth_at(hit.position)>0.05:break
			var obstacle := space.intersect_ray(PhysicsRayQueryParameters3D.create(game.player.position+Vector3.UP,hit.position+Vector3.UP,7,[game.player.get_rid()]))
			if not obstacle.is_empty():break
			clear_steps+=1
			for actor in game.zombies.residents:
				if is_instance_valid(actor) and actor.alive:separation=minf(separation,point.distance_to(actor.global_position))
		var score := clear_steps*100.0+separation
		if score>best:best=score;heading=angle
	preparation.append({"stage":"departure_heading","yaw":heading,"clear_samples":int(best/100.0),"score":best})
	return heading

func collect_frame() -> void:
	var now := Time.get_ticks_usec()
	if not playable():invalid_play_frames+=1
	travelled+=game.player.position.distance_to(previous);previous=game.player.position
	if rows.size()<6000:
		rows.append({"phase":phase,"frame_ms":(now-last_frame)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"position":[previous.x,previous.y,previous.z],"yaw":game.player.rotation.y,"grounded":game.player.is_on_floor(),"speed":game.player.velocity.length(),"cover_us":game.ground_cover.last_process_us,"batch_us":game.ground_cover.batches[2].render_frame_profile().process_us,"cover_pages":game.ground_cover.batches[2].render_stats().resident_batches,"actors":game.zombies.residents.size()})
		rows[-1]["trees"]=game.vegetation.renderer.roots.size()
		rows[-1]["forest_cells"]=game.ecosystem.resident.size()
		rows[-1]["near_cost_mode"]=near_cost_mode
	if near_review and phase=="capture_walk":
		var metric:float=game.ground_cover.grass_material.get_shader_parameter("near_lod_metric")
		var found_band:=false
		for page in game.ground_cover.batches[2].get_children():
			if not page is MultiMeshInstance3D or not page.visible:continue
			var box:AABB=page.global_transform*page.multimesh.get_aabb()
			if not game.camera.is_position_in_frustum(box.get_center()):continue
			var eye:Vector3=game.camera.global_position
			var d:float=eye.distance_to(eye.clamp(box.position,box.end))
			if d>35:continue
			var full:bool=d<.02*metric
			var id:int=page.get_instance_id()
			if near_page_states.has(id) and near_page_states[id]!=full:
				near_page_transitions.append({"capture_index":captured,"page":id,"baseline_full":full,"distance":d,"bounds_min":str(box.position),"bounds_size":str(box.size),"screen_center":str(game.camera.unproject_position(box.get_center()))})
			near_page_states[id]=full
			# Test-only witness from real native instance buffers; never runtime work.
			if not found_band and captured<capture_count:
				for i in page.multimesh.instance_count:
					var origin:Vector3=(page.global_transform*page.multimesh.get_instance_transform(i)).origin
					var distance:float=origin.distance_to(eye)
					if distance>.01705*metric and distance<.0198*metric and game.camera.is_position_in_frustum(origin):found_band=true;break
		if found_band:near_band_frames+=1
	if approach_review and phase=="capture_walk":
		var mesh: ArrayMesh=game.ground_cover.preview_meshes[0]
		var camera: Camera3D=game.camera
		var metric: float=root.size.x*float(ProjectSettings.get_setting("rendering/scaling_3d/scale",1.0))/(root.mesh_lod_threshold*camera.get_camera_projection().get_lod_multiplier())
		for child in game.ground_cover.batches[0].get_children():
			if child is MultiMeshInstance3D and child.visible:
				var center: Vector3=child.global_transform*child.multimesh.get_aabb().get_center()
				if not game.camera.is_position_in_frustum(center):continue
				var box: AABB=child.global_transform*child.multimesh.get_aabb()
				var eye: Vector3=camera.global_position
				var distance := eye.distance_to(eye.clamp(box.position,box.end))
				var scale: Vector3=child.global_basis.get_scale().abs()
				var threshold: float=mesh.get_meta("surface_lod_error")*metric*maxf(scale.x,maxf(scale.y,scale.z))*child.lod_bias
				# Witness the engine's internal mesh LOD as well as native page choices.
				# Shadow-casting pages keep both surfaces and never select a far-only page.
				var shape := "opaque" if distance<threshold else "proxy"
				var id: int=child.get_instance_id()
				if stone_page_states.has(id) and stone_page_states[id]!=shape and stone_page_transitions.size()<512:
					stone_page_transitions.append({"frame":Engine.get_frames_drawn(),"capture_index":captured,"previous":stone_page_states[id],"current":shape,"aabb_distance":distance,"threshold":threshold,"center":str(center),"position":str(game.player.position)})
				stone_page_states[id]=shape
	last_frame=now

func walk(label: String, seconds: float, turn_speed := 0.0) -> void:
	phase=label
	var end := Time.get_ticks_msec()+int(seconds*1000)
	var last := Time.get_ticks_usec()
	var frames := 0
	while Time.get_ticks_msec()<end:
		game.app_focused=true
		var now := Time.get_ticks_usec()
		game.player.rotation.y+=turn_speed*(now-last)/1000000.0;last=now
		await RenderingServer.frame_post_draw
		frames+=1
		if label=="capture_walk" and captured<capture_count:
			capture_frame_ids.append(Engine.get_frames_drawn())
			asynchronous.request(captured);captured+=1

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="):output=argument.trim_prefix("--check-evidence-dir=")
		if argument.begins_with("--gameplay-source-slot="):slot=argument.trim_prefix("--gameplay-source-slot=")
		if argument.begins_with("--fullframe-port="):fullframe_port=int(argument.trim_prefix("--fullframe-port="))
		if argument.begins_with("--lab-run-id="):fullframe_token=argument.trim_prefix("--lab-run-id=")
		if argument=="--opaque-control":control=true
		if argument=="--approach-review":approach_review=true
		if argument=="--near-transition-review":near_review=true
		if argument=="--previous-filter-control":previous_control=true
		if argument=="--fern-trial":fern_trial=true
		if argument=="--fern-cluster-trial":fern_cluster_trial=true
	if int(control)+int(previous_control)+int(fern_trial)+int(fern_cluster_trial)>1:push_error("Choose one gameplay control");quit(1);return
	if fullframe_port:capture_count=192
	if output.is_empty() or not slot.is_valid_identifier():push_error("Use admitted gameplay runner and existing source slot");quit(1);return
	write_bytes("vegetation_gameplay.gd",FileAccess.get_file_as_bytes("res://tests/vegetation_gameplay.gd"))
	write_bytes("vegetation_capture.gd",FileAccess.get_file_as_bytes("res://tests/fixtures/vegetation_capture.gd"))
	runtime_hashes["res://tests/fixtures/vegetation_capture.gd"]=FileAccess.get_sha256("res://tests/fixtures/vegetation_capture.gd")
	for path in ["res://addons/structures/bin/structures.windows.template_debug.x86_64.dll","res://addons/world_ecosystem/filtered_grass.gd","res://addons/world_ecosystem/filtered_grass.gdshader","res://addons/world_ecosystem/filtered_fern.gd","res://addons/world_ecosystem/filtered_fern.gdshader","res://addons/world_ecosystem/filtered_detail.gd","res://addons/world_ecosystem/filtered_stone.gdshader","res://addons/world_ecosystem/woodland_mesh.gd","res://addons/world_ecosystem/ground_cover.gd","res://addons/world_ecosystem/woodland.gdshader","res://tests/vegetation_gameplay.gd"]:
		runtime_hashes[path]=FileAccess.get_sha256(path)
	for name in ["filtered_fern.gd","filtered_fern.gdshader","filtered_detail.gd","filtered_stone.gdshader"]:write_bytes(name,FileAccess.get_file_as_bytes("res://addons/world_ecosystem/"+name))
	var save := "user://worlds/"+slot+".trw"
	if not FileAccess.file_exists(save):push_error("Source save unavailable");quit(1);return
	source_hash=FileAccess.get_sha256(save)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot="+slot,"--snapshot-readonly","--temporary","--no-derived-cache","--ground-cover","--gameplay-construction","--actors","--vehicle-fleet"]),true)
	game=WalkingWorld.new();game.name="TerraForest";game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
	if not await ready_within(func():return not game.loading_active and not game.needs_floor_spawn,90):
		check(false,"source world loaded");await finish();return
	observe_preparation("initial_source_ready")
	if approach_review:game.session_menu.set_open(true)
	if approach_review:
		# One explicit test setup relocation, before all measurement. Use normal
		# destination loading/floor snap, then ordinary collision and held input.
		# Saved combat/death/arrival state must not masquerade as a walking capture.
		if not await ready_within(playable,90):
			check(false,"source arrival/respawn completes before route setup");await finish();return
		game.teleport(Vector3(1740,0,1700))
		if not await ready_within(playable,90):
			check(false,"outdoor approach destination playable");await finish();return
		game.yaw=0.0;game.pitch=deg_to_rad(-12.0);game.player.rotation.y=game.yaw
		observe_preparation("outdoor_route_ready")
	# The render lab intentionally freezes its settled local scene. Ordinary-play
	# cost must include the complete forest rather than early startup's 216 cells.
	if not await ready_within(func():return game.ecosystem.coverage_status().ready,45):
		check(false,"whole source forest settles before gameplay measurement");await finish();return
	initial_forest=game.ecosystem.coverage_status()
	if near_review:
		near_candidate=game.ground_cover.preview_meshes[2]
		near_baseline=preload("res://addons/world_ecosystem/woodland_mesh.gd").build(2,true,true,false,true,false)
		preload("res://addons/world_ecosystem/woodland_mesh.gd").set_grass_detail(near_baseline.surface_get_material(0),game.ground_cover.grass_texture_enabled)
		for surface in near_baseline.get_surface_count():
			near_baseline.surface_get_material(surface).set_shader_parameter("distance_fade_start",92.0)
			near_baseline.surface_get_material(surface).set_shader_parameter("distance_fade_end",124.0)
		check(near_candidate.get_meta("near_lod_transition",false),"normal source enables per-plant near fade")
	check(initial_forest.owners==1024,"normal gameplay starts with all 1024 forest cells resident")
	if not (control or previous_control or fern_trial or fern_cluster_trial):
		var fern_mesh: ArrayMesh=game.ground_cover.preview_meshes[1]
		check(fern_mesh.get_surface_count()==2 and fern_mesh.surface_get_array_len(1)==28,"normal source uses seven far fronds without a test override")
		var far_material: ShaderMaterial=fern_mesh.surface_get_material(1)
		check(far_material.shader==preload("res://addons/world_ecosystem/filtered_fern.gdshader") and game.ground_cover.foliage_materials.has(far_material),"normal runtime owns the production fern shader and camera/clock updates")
		check(far_material.get_shader_parameter("distance_fade_start")==92.0 and far_material.get_shader_parameter("distance_fade_end")==124.0,"production far fern uses the normal visibility fade")
		for species in [0,3,4,5]:
			var detail_mesh: ArrayMesh=game.ground_cover.preview_meshes[species]
			check(detail_mesh.get_surface_count()==2 and detail_mesh.surface_get_array_len(1)==(4 if species==0 else 16),"normal source uses bounded far detail geometry: "+str(species))
			var detail_material: ShaderMaterial=detail_mesh.surface_get_material(1)
			var expected: Shader=preload("res://addons/world_ecosystem/filtered_stone.gdshader") if species==0 else preload("res://addons/world_ecosystem/filtered_fern.gdshader")
			check(detail_material.shader==expected and game.ground_cover.foliage_materials.has(detail_material),"production detail shader and clock ownership: "+str(species))
			check(detail_material.get_shader_parameter("distance_fade_start")==92.0 and detail_material.get_shader_parameter("distance_fade_end")==124.0,"production detail visibility fade: "+str(species))
	if control or previous_control or fern_trial or fern_cluster_trial:
		for species in [0,3,4,5]:
			var detail_mesh: ArrayMesh=game.ground_cover.preview_meshes[species]
			game.ground_cover.foliage_materials.erase(detail_mesh.surface_get_material(1))
			preload("res://addons/world_ecosystem/filtered_grass.gd").configure_batch(game.ground_cover.batches[species],detail_mesh,false)
			var detail := preload("res://tests/fixtures/detail_speckles.gd")
			detail.restore(detail_mesh,detail.capture(detail_mesh,species))
		var fern_mesh: ArrayMesh=game.ground_cover.preview_meshes[1]
		if fern_mesh.get_surface_count()==2:
			game.ground_cover.foliage_materials.erase(fern_mesh.surface_get_material(1))
			preload("res://addons/world_ecosystem/filtered_grass.gd").configure_batch(game.ground_cover.batches[1],fern_mesh,false)
			preload("res://tests/fixtures/grass_filtered.gd").restore(fern_mesh,preload("res://tests/fixtures/fern_filtered.gd").capture(fern_mesh))
	if control:
		var mesh: ArrayMesh=game.ground_cover.preview_meshes[2]
		var old_far: ShaderMaterial=mesh.surface_get_material(1)
		var filter := preload("res://tests/fixtures/grass_filtered.gd")
		filter.restore(mesh,filter.capture(mesh))
		preload("res://addons/world_ecosystem/filtered_grass.gd").configure_batch(game.ground_cover.batches[2],mesh,false)
		game.ground_cover.foliage_materials.erase(old_far)
	if previous_control:
		var mesh: ArrayMesh=game.ground_cover.preview_meshes[2]
		var material_index: int=game.ground_cover.foliage_materials.find(mesh.surface_get_material(1))
		if material_index<0:check(false,"previous filter has normal clock/camera owner");await finish();return
		var filter := preload("res://tests/fixtures/grass_filtered.gd")
		var saved := filter.capture(mesh)
		var surface := preload("res://addons/world_ecosystem/filtered_grass.gd")
		surface.configure_batch(game.ground_cover.batches[2],mesh,false)
		var previous_material := surface.apply(mesh,saved.arrays,saved.lods,saved.material,0.06,0.10)
		# Reuse the normal coordinator's camera/clock updates for this in-memory control.
		game.ground_cover.foliage_materials[material_index]=previous_material
	if fern_trial or fern_cluster_trial:
		var mesh: ArrayMesh=game.ground_cover.preview_meshes[1]
		var trial := preload("res://tests/fixtures/fern_filtered.gd")
		var far := trial.install(mesh,trial.capture(mesh),0.04,fern_cluster_trial)
		preload("res://addons/world_ecosystem/filtered_grass.gd").configure_batch(game.ground_cover.batches[1],mesh,true)
		game.ground_cover.foliage_materials.append(far)
		runtime_hashes["res://tests/fixtures/fern_filtered.gd"]=FileAccess.get_sha256("res://tests/fixtures/fern_filtered.gd")
		write_bytes("fern_filtered.gd",FileAccess.get_file_as_bytes("res://tests/fixtures/fern_filtered.gd"))
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(approach_review);game._clear_motion();game.fly=false
	game.camera.rotation.x=deg_to_rad(-12.0)
	await walk("settling",6.0)
	observe_preparation("after_settling")
	if not playable():check(false,"scene remains playable after settling");await finish();return
	if approach_review:
		game.yaw=approach_heading();game.player.rotation.y=game.yaw
	check(not game.fly and game.is_physics_processing() and game.ground_cover.is_processing(),"walking physics and normal cover streaming remain active")
	check(game.player.is_on_floor(),"player grounded before movement")
	initial_cover=game.ground_cover.batches[2].render_stats()
	for species in [0,3,4,5]:
		var source: ArrayMesh=game.ground_cover.preview_meshes[species]
		var pages := {"near":0,"far":0,"boundary":0}
		for child in game.ground_cover.batches[species].get_children(true):
			if not child is MultiMeshInstance3D:continue
			var active: Mesh=child.multimesh.mesh
			if active==source:pages.boundary+=1
			elif active==source.get_meta("surface_lod_far"):pages.far+=1
			elif active==source.get_meta("surface_lod_near"):pages.near+=1
		detail_render_pages[str(species)]=pages
		if not (control or previous_control or fern_trial or fern_cluster_trial):check(pages.far>0,"actual far detail draw pages present during physical gameplay: "+str(species))
	previous=game.player.position;last_frame=Time.get_ticks_usec()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	RenderingServer.frame_post_draw.connect(collect_frame);physics_frame.connect(physics_tick)
	asynchronous.begin(root.get_texture().get_rid(),Rect2i(0,0,1920,1080) if fullframe_port else asynchronous.REGION,capture_count)
	await ready_within(func():return asynchronous.ready or not asynchronous.errors.is_empty(),5.0)
	if not asynchronous.ready:check(false,"asynchronous capture setup: "+str(asynchronous.errors));await finish();return
	captures.put_u32(capture_count)
	capture_start=game.player.position
	game.session_menu.set_open(false)
	key(KEY_W if approach_review else KEY_D,true)
	await walk("capture_walk",6.0,0.0 if approach_review else 0.04)
	if approach_review:
		check(stone_page_transitions.any(func(row):return row.capture_index<capture_count),"visible stone LOD crossings exercised within captured physical approach")
		check(game.player.position.distance_to(capture_start)>8.0,"capture advances physically rather than waiting or turning in place")
	check(asynchronous.received==capture_count and not asynchronous.context.is_empty() and asynchronous.errors.is_empty(),"all bounded asynchronous captures complete before cost measurement")
	key(KEY_W if approach_review else KEY_D,false);key(KEY_W,true)
	if near_review:
		check(near_band_frames>100,"visible plants occupy the near fade band during physical capture")
		check(near_page_transitions.any(func(row):return row.capture_index<capture_count),"physical capture crosses the old rectangular near-LOD boundary")
		for group in 3:
			for sample in 4:
				select_near(sample in [1,2])
				await walk("warm_near",1.0)
				await walk("measure_near_%d_%d"%[group,sample],1.25)
		select_near(true)
	else:await walk("measure_walk",14.0)
	await walk("measure_turn",10.0,-0.10)
	key(KEY_W,false);key(KEY_D,true)
	await walk("measure_strafe",6.0)
	key(KEY_D,false)
	RenderingServer.frame_post_draw.disconnect(collect_frame);physics_frame.disconnect(physics_tick)
	if near_review:await check_near_after_walk()
	capture_times.assign(asynchronous.times)
	if not asynchronous.context.is_empty():walking_context=Image.create_from_data(1920,1080,false,Image.FORMAT_RGBA8,asynchronous.context)
	if not fullframe_port:
		for data: PackedByteArray in asynchronous.frames:
			if not data.is_empty():capture_images.append(Image.create_from_data(640,240,false,Image.FORMAT_RGBA8,data))
		asynchronous.frames.clear()
	asynchronous.context.clear();asynchronous.dispose()
	if walking_context:write_bytes("walking.png",walking_context.save_png_to_buffer())
	walking_context=null
	if fullframe_port:
		fullframe_peer.big_endian=false;fullframe_peer.connect_to_host("127.0.0.1",fullframe_port)
		check(await ready_within(func():fullframe_peer.poll();return fullframe_peer.get_status()==StreamPeerTCP.STATUS_CONNECTED,10),"full-frame analyzer connected")
		await stream_fullframe({"kind":"begin","output":output,"frames":capture_count,"width":1920,"height":1080})
	var image_index := 0
	for capture_index in (asynchronous.frames.size() if fullframe_port else capture_images.size()):
		var image: Image
		if fullframe_port:
			image=Image.create_from_data(1920,1080,false,Image.FORMAT_RGBA8,asynchronous.frames[capture_index])
			asynchronous.frames[capture_index]=PackedByteArray()
		else:image=capture_images[capture_index]
		image.convert(Image.FORMAT_RGB8)
		var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(image.get_data());capture_hashes.append(hash.finish().hex_encode())
		if fullframe_port:
			await stream_fullframe({"kind":"frame","case":"gameplay","frame":image_index},image.get_data())
		else:
			var bytes := image.save_webp_to_buffer(false)
			captures.put_u32(bytes.size());captures.put_data(bytes)
		image_index+=1
	capture_images.clear()
	if fullframe_port:await stream_fullframe({"kind":"end"})
	elif captured==capture_count:write_bytes("gameplay.frames",captures.data_array)
	check(captured==capture_count,"all planned frames captured while physically walking and turning")
	var consecutive := capture_frame_ids.size()==capture_count
	for index in range(1,capture_frame_ids.size()):consecutive=consecutive and capture_frame_ids[index]==capture_frame_ids[index-1]+1
	check(consecutive,"captured consecutive rendered frame identities")
	check(travelled>40.0,"normal gameplay travelled more than 40 metres")
	check(invalid_play_frames==0,"no loading cover, respawn or entry sequence during measured gameplay")
	check(grounded_frames>physics_frames*0.8,"grounded for at least 80 percent of movement physics ticks")
	check(FileAccess.get_sha256(save)==source_hash,"canonical save bytes unchanged")
	check(game.process_mode!=Node.PROCESS_MODE_DISABLED and game.zombies.residents.size()>0,"world and resident actors remain active")
	await finish()

func finish() -> void:
	key(KEY_W,false);key(KEY_D,false)
	for path: String in runtime_hashes:check(FileAccess.get_sha256(path)==runtime_hashes[path],"runtime source unchanged: "+path.get_file())
	var result := {"failures":failures,"opaque_control":control,"save_sha256":source_hash,"travelled_m":travelled,"physics_frames":physics_frames,"grounded_frames":grounded_frames,"capture_frames":captured,"rows":rows,"initial_cover":initial_cover,"final_cover":game.ground_cover.batches[2].render_stats() if game.ground_cover else {},"evidence_bytes":evidence_bytes,"scope":"Source gameplay with held W/D, physical collision, normal streaming and live actors. Scripted yaw steering and offscreen input admission only. Independent runs are not frame-identical. GPU comparison uses measure phases without image readback; capture_walk is excluded."}
	result["runtime_hashes"]=runtime_hashes;result["capture_times_ms"]=capture_times
	result["initial_forest"]=initial_forest
	result["detail_render_pages"]=detail_render_pages
	result["approach_review"]=approach_review
	result["near_transition_review"]=near_review
	result["near_band_capture_frames"]=near_band_frames
	result["near_page_transitions"]=near_page_transitions
	result["post_walk_near_control"]=post_walk_near_control
	result["stone_page_transitions"]=stone_page_transitions
	result["preparation"]=preparation;result["invalid_play_frames"]=invalid_play_frames
	result["route_setup"]="One pre-measurement normal teleport/floor-snap to (1740,0,1700); settle with normal pause menu; select clear departure away from resident enemies; no position changes during measurement" if approach_review else "saved pose"
	result["previous_filter_control"]=previous_control
	result["mode"]="fern_cluster_trial" if fern_cluster_trial else ("fern_trial" if fern_trial else ("previous_filtered" if previous_control else ("opaque" if control else "runtime_grass_fern_details")))
	result["capture_region"]=[0,0,1920,1080] if fullframe_port else [1280,340,640,240]
	result["capture_stride"]=1
	result["capture_method"]="Asynchronous RenderingDevice readback; full raw frames streamed after measurement when fullframe_port is present; otherwise cropped lossless packets."
	result["capture_frame_ids"]=capture_frame_ids
	result["capture_errors"]=asynchronous.errors
	result["capture_rgb_sha256"]=capture_hashes
	write_bytes("vegetation_gameplay.json",JSON.stringify(result).to_utf8_buffer())
	if near_review and failures.is_empty():write_bytes("RETAIN_READY","Uncommitted near-LOD candidate moving gameplay: retain ready for requested human playtest validation; release after approval/rejection and cold-retain verified evidence.\n".to_utf8_buffer())
	var identity := "res://tests/vegetation_gameplay.gd.uid"
	if not FileAccess.file_exists(identity):FileAccess.open(identity,FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	identity="res://tests/fixtures/vegetation_capture.gd.uid"
	if not FileAccess.file_exists(identity):FileAccess.open(identity,FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
	print("VEGETATION_GAMEPLAY failures=",failures.size());quit(0 if failures.is_empty() else 1)

func stream_fullframe(meta: Dictionary, pixels: PackedByteArray = PackedByteArray()) -> void:
	meta["token"]=fullframe_token;meta["bytes"]=pixels.size()
	var header := JSON.stringify(meta).to_utf8_buffer();fullframe_peer.put_u32(header.size())
	check(fullframe_peer.put_data(header)==OK and fullframe_peer.put_data(pixels)==OK,"raw viewport stream write")
	var deadline := Time.get_ticks_msec()+30000
	while fullframe_peer.get_available_bytes()==0 and Time.get_ticks_msec()<deadline:
		fullframe_peer.poll();await process_frame
	check(fullframe_peer.get_available_bytes()>0 and fullframe_peer.get_u8()==1,"raw viewport analysis acknowledgement")
