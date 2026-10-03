# SPDX-License-Identifier: 0BSD
# Deliberately opt-in: GPU readback changes timing. Pair with an uninstrumented run.
extends RefCounted
var game: Node
var current: Dictionary={}
var phases: Array=[]
var images: Array=[]
var save_errors: Array=[]
var thresholds: Array=[0,150,500,1000,2000,2950]
var next_capture:=0
var output: String="res://reports/mining_visual"

func attach(world: Node) -> void:
	game=world
	game.terrain.backend.enable_diagnostics()
	game.terrain.work_measured.connect(func(row: Dictionary): event("worker_result",row))
	game.terrain.density_ray_received.connect(func(row: Dictionary): event("target_query",row))
	game.terrain.edit_measured.connect(func(row: Dictionary): event("edit_draw",row))
	game.terrain.stage_measured.connect(func(label: String,ms: float):
		if ms>=5: event("cpu_stage",{"label":label,"duration_ms":ms}))
	RenderingServer.frame_post_draw.connect(after_draw)

func event(kind: String, data: Dictionary) -> void:
	if current.is_empty(): return
	current.events.append({"ms":(Time.get_ticks_usec()-int(current.started_us))/1000.0,"kind":kind,"data":data.duplicate(true)})
	if kind=="edit_draw" and data.get("changed",false) and not current.has("first_draw_ms"):
		current.first_draw_ms=(Time.get_ticks_usec()-int(current.started_us))/1000.0
		current.capture_first=true

func begin(label: String, started: int, destination: Vector3) -> void:
	next_capture=0
	current={"phase":label,"started_us":started,"destination":[destination.x,destination.y,destination.z],"samples":[],"events":[],"captures":[],"capture_first":false}
	# Samples and images share this phase object until finish().
	phases.append(current)

func key_array(keys) -> Array:
	var result: Array=[]
	for key: Vector3i in keys: result.append([key.x,key.y,key.z])
	return result

func tile_state(key: Vector3i) -> Dictionary:
	var terrain=game.terrain
	var tile: Dictionary=terrain.tiles.get(key,{})
	return {"key":[key.x,key.y,key.z],"resident":not tile.is_empty(),"active":tile.get("active",false),"dirty":tile.get("dirty",false),"requested":terrain.requested_keys.has(key),"activation":terrain.activation_keys.has(key),"in_flight":terrain.in_flight.has(key),"staged":terrain.staging_versions.has(key),"preparing":not terrain.preparation.is_empty() and terrain.preparation.data.key==key,"paused":terrain._has_paused_preparation(key)}

func snapshot() -> Dictionary:
	var terrain=game.terrain
	var point: Vector3=terrain.interaction_target
	var chain: Array=[]
	if point.is_finite():
		for size: int in [16,32,64,128,256]:
			var key:=Vector3i(floori(point.x/size)*size,floori(point.z/size)*size,size)
			var owner:=tile_state(key)
			owner["children"]=[]
			if size>16:
				var half: int=size/2
				for z in range(2):
					for x in range(2): owner.children.append(tile_state(Vector3i(key.x+x*half,key.y+z*half,half)))
			chain.append(owner)
	var paused: Array=[]
	for p: Dictionary in terrain.paused_preparations: paused.append({"key":str(p.data.key),"piece_at":p.piece_at})
	var staged: Array=[]
	for data: Dictionary in terrain.staging: staged.append({"kind":data.get("kind",""),"key":str(data.key)})
	var ready: Dictionary=terrain.preparation
	return {"ms":(Time.get_ticks_usec()-int(current.started_us))/1000.0,"query_pending":not game.terrain_pick_request.is_empty(),"query_cached":not game.terrain_pick_cache.is_empty(),"hit":not game.latest_hit.is_empty(),"focused":game.app_focused,"held":Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),"pending_edit":terrain.pending_edit,"target":str(point),"hierarchy":chain,"visible":key_array(terrain.visible_cut),"activation":key_array(terrain.activation_keys.keys()),"worker":terrain.backend.diagnostic_queue_snapshot(),"staging":staged,"preparation":{} if ready.is_empty() else {"key":str(ready.data.key),"piece_at":ready.piece_at},"paused":paused,"batch_remaining":terrain.batch_remaining,"native_revision":terrain.native_revision,"published_revision":terrain.published_revision,"schedule_timer":terrain.schedule_timer}

func after_draw() -> void:
	if current.is_empty(): return
	var begin_us:=Time.get_ticks_usec()
	var sample:=snapshot()
	current.samples.append(sample)
	var reason: String=""
	if next_capture<thresholds.size() and sample.ms>=thresholds[next_capture]:
		reason="at_%dms"%thresholds[next_capture]
		next_capture+=1
	if current.capture_first:
		reason+="_first_changed_draw"
		current.capture_first=false
	if not reason.is_empty():
		var readback:=Time.get_ticks_usec()
		var image: Image=game.get_viewport().get_texture().get_image()
		var name: String="%s_%02d.png"%[current.phase,current.captures.size()]
		var capture: Dictionary={"file":name,"ms":sample.ms,"reason":reason,"sample_index":current.samples.size()-1,"readback_ms":(Time.get_ticks_usec()-readback)/1000.0,"width":image.get_width(),"height":image.get_height()}
		current.captures.append(capture)
		images.append({"image":image,"file":name})
	sample["observer_ms"]=(Time.get_ticks_usec()-begin_us)/1000.0

func end() -> void:
	current={}

func finish() -> void:
	RenderingServer.frame_post_draw.disconnect(after_draw)
	DirAccess.make_dir_recursive_absolute(output)
	# Encode only after the workload; retain at most seven full-size images per phase.
	for captured: Dictionary in images:
		if captured.image.save_png(output+"/"+captured.file)!=OK: save_errors.append(captured.file)
	images.clear()
	var report:=FileAccess.open(output+"/trace.json",FileAccess.WRITE)
	if report==null: push_error("Cannot save visual mining trace");return
	report.store_string(JSON.stringify({"schema":1,"phases":phases,"save_errors":save_errors,"scope":"Diagnostic run with GPU readback and per-frame state sampling: NOT a performance acceptance result. Draw events indicate publication callbacks, not pixel-level proof; inspect captured frames. Exact worker owner identity is sampled at draw boundaries; sub-owner work is not instrumented."},"  "))
	report.close()
