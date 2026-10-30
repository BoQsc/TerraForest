extends SceneTree

var game:Node3D
var output:="res://reports/overview_terrain_coverage"
var failures:=0
var samples:PackedVector3Array
var sampled:=false
const SAVE:="user://worlds/recipe_generated_4644d8cfc8f97e43.trw"

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()

func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func run()->void:
	var options:=PackedStringArray(["--world-slot=recipe_generated_4644d8cfc8f97e43","--snapshot-readonly","--temporary","--gameplay-construction","--ground-cover","--vehicle-fleet"])
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):output=argument.trim_prefix("--view-output=")
		if argument.begins_with("--derived-cache="):options.append(argument)
	DirAccess.make_dir_recursive_absolute(output)
	var original_hash:=FileAccess.get_sha256(SAVE)
	if original_hash.is_empty():push_error("Missing disposable populated fixture");quit(1);return
	load("res://addons/world_runtime/session_options.gd").set_arguments(options,true)
	var load_started:=Time.get_ticks_usec()
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+150000
	while game.loading_active and Time.get_ticks_msec()<deadline and game.terrain.latest_error.is_empty():
		game.app_focused=true;await process_frame
	check(not game.loading_active and game.terrain.latest_error.is_empty(),"read-only populated fixture loads")
	var loading_ms:float=(Time.get_ticks_usec()-load_started)/1000.0
	check(game.terrain.root_coverage==64,"play begins with all 64 actual terrain regions published")
	game.set_physics_process(false);game._clear_motion();game.player_view.set_overview(true);game.player_view.overview_distance=768.0
	game.terrain.backend.enable_diagnostics()
	var timeline:=[]
	var frames:Array[float]=[]
	var previous:=Time.get_ticks_usec()
	var coverage_retained:=true
	for frame in 1800:
		game.app_focused=true;await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		if frame>60:frames.append((now-previous)/1000.0)
		previous=now
		coverage_retained=coverage_retained and game.terrain.root_coverage==64
		if frame%120==0:
			var row:={"frame":frame,"roots":game.terrain.root_coverage,"tiles":game.terrain.tiles.size(),"worker":game.terrain.backend.diagnostic_queue_snapshot(),"brush":game.terrain.foreground_brush,"paused":game.terrain.diagnostics_pause_streaming,"pending_edit":game.terrain.pending_edit,"error":game.terrain.latest_error,"cache_bytes":game.terrain.cache_bytes,"in_flight":str(game.terrain.in_flight.keys()),"requested":game.terrain.requested_keys.size(),"staging":game.terrain.staging.size()}
			timeline.append(row);print("COVERAGE_PROGRESS ",JSON.stringify(row))
	root.get_texture().get_image().save_png(output.path_join("normal.png"))
	var terrain=game.terrain
	check(coverage_retained,"refinement never withdraws whole-world coverage")
	check(terrain.cache_bytes<=terrain.cache_byte_limit,"populated overview terrain payload stays within its existing budget")
	var points:=PackedVector3Array()
	for along in 8:
		for across in 8:points.append(Vector3(across*256+128,0,along*256+128))
	var token:int=load("res://addons/volumetric_terrain/surface_tokens.gd").allocate()
	terrain.surface_batch_ready.connect(func(received:int,positions:PackedVector3Array,_normals:PackedVector3Array,_epoch:int,_revision:int):
		if received==token:samples=positions;sampled=true)
	check(terrain.request_surface_batch(points,token),"native surface diagnostic admitted")
	deadline=Time.get_ticks_msec()+15000
	while not sampled and Time.get_ticks_msec()<deadline:await process_frame
	check(sampled and samples.size()==points.size(),"native surface diagnostic completes")
	var coverage:=[]
	for key:Vector3i in terrain.visible_cut:
		var tile:Dictionary=terrain.tiles[key]
		var bounds:=AABB()
		var have_bounds:=false
		var parts:Array=tile.bricks.values() if tile.has("bricks") else [tile]
		for part:Dictionary in parts:
			if not part.node is MeshInstance3D:continue
			var part_bounds:AABB=part.node.global_transform*part.node.get_aabb()
			bounds=bounds.merge(part_bounds) if have_bounds else part_bounds;have_bounds=true
		coverage.append({"key":[key.x,key.y,key.z],"triangles":tile.triangles,"active":tile.active,"visible":tile.node.is_visible_in_tree(),"bounds":[bounds.position.x,bounds.position.y,bounds.position.z,bounds.size.x,bounds.size.y,bounds.size.z],"step":tile.step})
	var heights:=[]
	for position:Vector3 in samples:heights.append([position.x,position.y,position.z])
	terrain.material.set_shader_parameter("show_lod",true)
	for frame in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("lod.png"))
	terrain.material.set_shader_parameter("show_lod",false)
	frames.sort()
	var result:={"coverage":coverage,"surface_samples":heights,"roots":terrain.root_coverage,"root_total":terrain.roots.size(),"camera":str(game.player_view.third_camera.global_position),"focus":str(terrain.focus),"generator":terrain.backend.world_generator,"timeline":timeline,"loading_ms":loading_ms,"frame_p95_ms":frames[ceili(frames.size()*0.95)-1],"frame_max_ms":frames[-1],"cache_bytes":terrain.cache_bytes}
	result["coarse_edits"]=await verify_coarse_edits()
	game.shutdown_requested=true;await terrain.shutdown_after_edits();game.free();await process_frame
	check(FileAccess.get_sha256(SAVE)==original_hash,"fixture remains unchanged")
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"diagnostic never captures mouse")
	result["failures"]=failures
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	print("OVERVIEW_TERRAIN_COVERAGE failures=",failures)
	quit(1 if failures else 0)

func verify_coarse_edits()->Array:
	var terrain=game.terrain
	var key:=Vector3i(768,256,256)
	var rows:=[]
	check(terrain.visible_cut.has(key),"edit regression starts with a visible coarse root, not absent terrain")
	if not terrain.visible_cut.has(key) or samples.size()!=64:return rows
	var point:Vector3=samples[11]-Vector3.UP*0.4
	for iteration:int in 8:
		var started:=Time.get_ticks_usec()
		var revision:int=terrain.published_revision
		var accepted:bool=terrain.edit(load("res://addons/volumetric_terrain/mesh_codec.gd").brush(point,point,2.5,0,false,1),point-Vector3.ONE*7.5,point+Vector3.ONE*7.5)
		check(accepted,"coarse excavation accepted "+str(iteration))
		var deadline:=Time.get_ticks_msec()+3000
		var covered:=true
		while terrain.pending_edit and Time.get_ticks_msec()<deadline:
			await process_frame
			covered=covered and terrain.root_coverage==64
		await RenderingServer.frame_post_draw
		var elapsed:float=(Time.get_ticks_usec()-started)/1000.0
		check(not terrain.pending_edit and terrain.published_revision==revision+1 and covered,"coarse excavation publishes once without losing terrain coverage")
		check(elapsed<=150.0,"coarse public-edit-to-draw remains within 150 ms")
		rows.append({"edit":iteration,"public_edit_to_draw_ms":elapsed,"native_build_ms":terrain.last_total_build_ms,"commit_ms":terrain.last_commit_ms})
		point.y-=0.5
		for frame:int in 8:await process_frame
	return rows
