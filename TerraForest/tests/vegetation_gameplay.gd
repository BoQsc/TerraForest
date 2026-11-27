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

func collect_frame() -> void:
	var now := Time.get_ticks_usec()
	travelled+=game.player.position.distance_to(previous);previous=game.player.position
	if rows.size()<6000:
		rows.append({"phase":phase,"frame_ms":(now-last_frame)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),"cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"position":[previous.x,previous.y,previous.z],"yaw":game.player.rotation.y,"grounded":game.player.is_on_floor(),"speed":game.player.velocity.length(),"cover_us":game.ground_cover.last_process_us,"batch_us":game.ground_cover.batches[2].render_frame_profile().process_us,"cover_pages":game.ground_cover.batches[2].render_stats().resident_batches,"actors":game.zombies.residents.size()})
		rows[-1]["trees"]=game.vegetation.renderer.roots.size()
		rows[-1]["forest_cells"]=game.ecosystem.resident.size()
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
	# The render lab intentionally freezes its settled local scene. Ordinary-play
	# cost must include the complete forest rather than early startup's 216 cells.
	if not await ready_within(func():return game.ecosystem.coverage_status().ready,45):
		check(false,"whole source forest settles before gameplay measurement");await finish();return
	initial_forest=game.ecosystem.coverage_status()
	check(initial_forest.owners==1024,"normal gameplay starts with all 1024 forest cells resident")
	if not (control or previous_control or fern_trial or fern_cluster_trial):
		var fern_mesh: ArrayMesh=game.ground_cover.preview_meshes[1]
		check(fern_mesh.get_surface_count()==2 and fern_mesh.surface_get_array_len(1)==28,"normal source uses seven far fronds without a test override")
		var far_material: ShaderMaterial=fern_mesh.surface_get_material(1)
		check(far_material.shader==preload("res://addons/world_ecosystem/filtered_fern.gdshader") and game.ground_cover.foliage_materials.has(far_material),"normal runtime owns the production fern shader and camera/clock updates")
		check(far_material.get_shader_parameter("distance_fade_start")==100.0 and far_material.get_shader_parameter("distance_fade_end")==124.0,"production far fern uses the normal visibility fade")
		for species in [0,3,4,5]:
			var detail_mesh: ArrayMesh=game.ground_cover.preview_meshes[species]
			check(detail_mesh.get_surface_count()==2 and detail_mesh.surface_get_array_len(1)==(4 if species==0 else 16),"normal source uses bounded far detail geometry: "+str(species))
			var detail_material: ShaderMaterial=detail_mesh.surface_get_material(1)
			var expected: Shader=preload("res://addons/world_ecosystem/filtered_stone.gdshader") if species==0 else preload("res://addons/world_ecosystem/filtered_fern.gdshader")
			check(detail_material.shader==expected and game.ground_cover.foliage_materials.has(detail_material),"production detail shader and clock ownership: "+str(species))
			check(detail_material.get_shader_parameter("distance_fade_start")==100.0 and detail_material.get_shader_parameter("distance_fade_end")==124.0,"production detail visibility fade: "+str(species))
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
	game.session_menu.set_open(false);game._clear_motion();game.fly=false
	game.camera.rotation.x=deg_to_rad(-12.0)
	await walk("settling",6.0)
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
	key(KEY_D,true)
	await walk("capture_walk",6.0,0.04)
	check(asynchronous.received==capture_count and not asynchronous.context.is_empty() and asynchronous.errors.is_empty(),"all bounded asynchronous captures complete before cost measurement")
	key(KEY_D,false);key(KEY_W,true)
	await walk("measure_walk",14.0)
	await walk("measure_turn",10.0,-0.10)
	key(KEY_W,false);key(KEY_D,true)
	await walk("measure_strafe",6.0)
	key(KEY_D,false)
	RenderingServer.frame_post_draw.disconnect(collect_frame);physics_frame.disconnect(physics_tick)
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
	result["previous_filter_control"]=previous_control
	result["mode"]="fern_cluster_trial" if fern_cluster_trial else ("fern_trial" if fern_trial else ("previous_filtered" if previous_control else ("opaque" if control else "runtime_grass_fern_details")))
	result["capture_region"]=[0,0,1920,1080] if fullframe_port else [1280,340,640,240]
	result["capture_stride"]=1
	result["capture_method"]="Asynchronous RenderingDevice readback; full raw frames streamed after measurement when fullframe_port is present; otherwise cropped lossless packets."
	result["capture_frame_ids"]=capture_frame_ids
	result["capture_errors"]=asynchronous.errors
	result["capture_rgb_sha256"]=capture_hashes
	write_bytes("vegetation_gameplay.json",JSON.stringify(result).to_utf8_buffer())
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
