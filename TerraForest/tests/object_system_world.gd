# SPDX-License-Identifier: 0BSD
extends SceneTree
const Packs=preload("res://addons/structures/pack_registry.gd")
var game: Node
var checks:=0
var failures:=0
var folder:=""
var origin:=Vector3.ZERO
var metrics: Dictionary={"scope":"Temporary ordinary game, authored mansion fixture above terrain; not generated-site terrain-fit or long-run qualification","legs":[]}
class Cadence extends Node:
	var host: Node
	var sampling:=false
	var previous:=0
	var frames: Array[float]=[]
	var draws: Array[float]=[]
	var query_us: Array[float]=[]
	func _process(_delta: float) -> void:
		host.app_focused=true
		var now:=Time.get_ticks_usec()
		if sampling and previous>0 and frames.size()<5000:
			frames.append((now-previous)/1000.0)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			query_us.append(float(host.object_inspector.stats.get("query_layout_us",0)))
		previous=now
	func reset() -> void: frames.clear(); draws.clear(); query_us.clear(); previous=0
	func percentile(values: Array[float], quantile: float) -> float:
		if values.is_empty(): return 0
		var sorted:=values.duplicate(); sorted.sort(); return sorted[mini(sorted.size()-1,int(ceil((sorted.size()-1)*quantile)))]
	func result() -> Dictionary:
		return {"frames":frames.size(),"p50_ms":percentile(frames,.50),"p95_ms":percentile(frames,.95),"p99_ms":percentile(frames,.99),"worst_ms":percentile(frames,1),"draw_calls_p95":percentile(draws,.95),"inspection_query_layout_us_p95":percentile(query_us,.95)}
var observer: Cadence
func check(ok: bool,label: String) -> bool:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label); return ok
func _initialize() -> void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	ProjectSettings.set_setting("terraforest/pistol_trial_settings_path","")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="): folder=arg.trim_prefix("--check-evidence-dir=")
	run.call_deferred()
func key(code: int,pressed: bool=true) -> void:
	var event:=InputEventKey.new(); event.physical_keycode=code; event.keycode=code; event.pressed=pressed
	Input.parse_input_event(event); Input.flush_buffered_events()
func aim(feet: Vector3,point: Vector3) -> void:
	game.player.position=origin+feet; game.player.velocity=Vector3.ZERO; game.camera.position=Vector3(0,1.62,0); game.camera.look_at(origin+point)
	game.app_focused=true; game.fly=false; game.needs_floor_spawn=false; game.structures.set_model_focus(game.player.position); game.structures.blocks.set_focus(game.player.position)
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func ticks(count: int) -> void:
	for i in count: game.app_focused=true; await physics_frame
func run() -> void:
	if not check(DisplayServer.get_name()!="headless","rendered player-facing object check"): quit(1); return
	var started:=Time.get_ticks_msec()
	game=load("res://demo/world.tscn").instantiate(); game.temporary_world=true; game.background_fps=60; game.terrain.backend.disk_cache.enabled=false; root.add_child(game)
	var deadline:=Time.get_ticks_msec()+90000
	while game.loading_active and Time.get_ticks_msec()<deadline: game.app_focused=true; await process_frame
	metrics.loading_ms=Time.get_ticks_msec()-started
	if not check(not game.loading_active and game.startup_complete,"ordinary temporary world loads all packs and container providers"): await finish(); return
	game.set_physics_process(false); game._clear_motion(); game.app_focused=true; game.player_view.entry.finish()
	if game.session_menu.developer: game.session_menu.toggle_developer()
	key(KEY_QUOTELEFT); key(KEY_QUOTELEFT,false); await ticks(2)
	check(game.session_menu.developer,"short Backtick tap retains the developer switch")
	key(KEY_QUOTELEFT); key(KEY_QUOTELEFT,false); await ticks(2)
	for flying in [true,false]:
		key(KEY_QUOTELEFT); await ticks(24); key(KEY_1); key(KEY_1,false); key(KEY_QUOTELEFT,false); await ticks(2)
		check(game.fly==flying,"original Backtick / 1 flight choice remains available")
	key(KEY_QUOTELEFT); await ticks(24); key(KEY_2); key(KEY_2,false); key(KEY_QUOTELEFT,false); await ticks(3)
	check(game.session_menu.developer and game.player_hud.developer_slot==4 and game.object_inspector.enabled,"hold Backtick then 2 selects Objects / inspection")
	check(not game.object_inspector.nearby_names,"inspection begins with only the aimed object")
	key(KEY_ALT); await ticks(2)
	check(game.session_menu.developer_hud.mouse_access and not game.object_inspector.nearby_names,"Alt exposes controls without enabling labels")
	var names_toggle: CheckBox
	for control: Node in game.session_menu.developer_hud.content.get_children():
		if control is CheckBox and control.text=="Show nearby object names": names_toggle=control
	check(names_toggle!=null,"Objects controls expose the label toggle")
	if names_toggle!=null: names_toggle.button_pressed=true
	key(KEY_ALT,false); await ticks(2)
	check(game.object_inspector.nearby_names and not game.session_menu.developer_hud.mouse_access,"selected names mode survives Alt release (isolated window keeps cursor uncaptured)")
	var manor: Resource
	for prefab: Resource in game.structure_prefabs:
		if prefab.resource_name.begins_with("Homestead Manor"): manor=prefab
	if not check(manor!=null,"normal Building prefab menu includes Homestead Manor"): await finish(); return
	var outdoor:=false
	for entry: Dictionary in game.model_tool.catalog: outdoor=outdoor or entry.get("pack")=="Outdoor 01"
	check(outdoor,"ordinary Objects menu discovers Outdoor 01 from its folder")
	await scatter_sample()
	origin=Vector3(Vector3i(game.player.position))+Vector3(-19,30,-16)
	var transaction: RefCounted=ClassDB.instantiate("NativePrefabPlacement")
	var placed: Dictionary=transaction.place(game.structures.blocks,manor,Vector3i(origin),0,game.structures.model_collections(),[])
	if not check(placed.get("ok",false),"actual-world mansion placement: "+str(placed.get("reason",""))): await finish(); return
	game.structures.blocks.set_collision_radius(80); game.structures.blocks.flush_bakes()
	aim(Vector3(30.5,1.02,22.8),Vector3(34,1.5,26.5)); await ticks(60)
	game.object_inspector.clock=0; await ticks(3)
	check(game.object_inspector.labels.size()>0 and game.object_inspector.labels.size()<=24,"native scene furnishings receive bounded on-camera names")
	var separated:=true; var labels: Array=game.object_inspector.labels
	for i in labels.size():
		for j in range(i+1,labels.size()): separated=separated and not labels[i].rect.intersects(labels[j].rect)
	check(separated,"visible names do not overlap")
	check(game.session_menu.developer_hud.panel.get_global_rect().end.x<=root.get_visible_rect().size.x,"Objects panel fits the viewport with all pack names")
	check(not game.model_tool.preview.visible,"inspection suppresses the placement ghost")
	var before_click: PackedByteArray=game.structures.capture_storage_snapshot()
	for pressed in [true,false]:
		var click:=InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=pressed; Input.parse_input_event(click); Input.flush_buffered_events()
	check(game.structures.capture_storage_snapshot()==before_click,"inspection click leaves aimed object intact")
	await capture("object_names")
	# Use a real outdoor container and E through the normal input path.
	var batch: Node3D=game.structures.model(Packs.by_item[821].key)
	var id: int=batch.get_ids()[0]; var record: PackedFloat32Array=batch.get_instance(id); var point:=Vector3(record[3],record[7],record[11])-origin
	if game.session_menu.developer: game.session_menu.toggle_developer()
	aim(point+Vector3(0,0,-1.5),point+Vector3.UP*.20); await ticks(30)
	key(KEY_E); key(KEY_E,false); await ticks(3)
	check(game.pack_storage.opened and game.pack_storage.identity==id,"E opens an aimed outdoor duffel in ordinary gameplay")
	if game.pack_storage.opened:
		check(game.player_hud.inventory.grant(225,3,game.player_hud.inventory.snapshot().revision).ok,"supply stack for container transfer")
		var slot:=-1
		for i in game.player_hud.inventory.snapshot().slots.size():
			if game.player_hud.inventory.snapshot().slots[i].item==225: slot=i; break
		if slot>=0 and slot<10:
			check(game.player_hud.inventory.transfer(slot,10,3,game.player_hud.inventory.snapshot().revision).ok,"move supplied cloth into visible backpack grid")
			slot=10
		game.pack_storage.refresh()
		var data: Dictionary=game.pack_storage.drag_data("player",slot)
		game.pack_storage.drop_stack("chest",0,data)
		check(game.pack_storage.store.snapshot(id).slots[0].item==225 and batch.is_removal_protected(id),"shared drag UI stores items and protects the duffel")
		await capture("outdoor_storage")
		key(KEY_ESCAPE); key(KEY_ESCAPE,false); await ticks(2)
		check(not game.pack_storage.opened and not game.player_hud.inventory_open and game.player_hud.enabled,"Esc closes storage and restores gameplay input")
	# Capture structure + container bytes, then recreate native owners in a fresh process below.
	var saved: Dictionary={"structures":game.structures.capture_storage_snapshot(),"containers":{}}
	for item_key: String in game.pack_storage.stores: saved.containers[item_key]=game.pack_storage.stores[item_key].capture_storage_snapshot()
	var bytes:=var_to_bytes(saved)
	check(bytes.size()<4*1024*1024,"bounded native save fixture under 4 MiB")
	FileAccess.open(folder.path_join("object_state.bin"),FileAccess.WRITE).store_buffer(bytes)
	metrics.state_sha256=FileAccess.get_sha256(folder.path_join("object_state.bin"))
	# Actual gameplay walking along the courtyard path; identical on/off samples.
	observer=Cadence.new(); observer.host=game; root.add_child(observer)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED); Engine.max_fps=0
	game.session_menu.developer_hud.hidden_by_user=true; game.session_menu.developer_hud.refresh()
	for labels_on in [false,true]: await walk_sample(labels_on)
	# One thousand more static objects: ten collections, no per-instance scripts.
	if not game.session_menu.developer: game.session_menu.toggle_developer()
	game.set_physics_process(false)
	var dense_origin:=origin+Vector3(-40,1,10)
	var count:=0
	for i in 1000:
		var row: Dictionary=Packs.by_item[820+i%10]; var collection: Node3D=game.structures.model(row.key)
		var pose:=Transform3D(Basis.IDENTITY,dense_origin+Vector3((i%25)*1.7,0,(i/25)*1.7))
		if collection.insert_instance(game.model_tool.records(pose,collection),AABB())>0: count+=1
	check(count==1000,"dense actual-game fixture adds 1000 objects in ten native collections")
	aim(Vector3(-18,4,4),Vector3(-18,1,30)); game.object_inspector.enabled=true; game.object_inspector.nearby_names=true
	await ticks(120); observer.reset(); observer.sampling=true; await ticks(240); observer.sampling=false
	var dense: Dictionary=observer.result(); dense.phase="1000 additional outdoor objects / labels on / stationary"; metrics.legs.append(dense)
	metrics.gpu=RenderingServer.get_video_adapter_name(); metrics.viewport=root.get_visible_rect().size; metrics.native_collections=game.structures.model_collections().size()
	await capture("object_density")
	print("OBJECT_SYSTEM_PERFORMANCE ",JSON.stringify(metrics))
	observer.free(); observer=null
	await finish()
func walk_sample(labels_on: bool) -> void:
	game.set_physics_process(false); game._clear_motion(); game.object_inspector.enabled=labels_on; game.object_inspector.nearby_names=labels_on
	game.object_inspector.stats={}
	aim(Vector3(19,1.02,32),Vector3(19,2.64,12)); game.yaw=0; game.pitch=0; game.player.rotation.y=0; game.camera.rotation=Vector3.ZERO
	game.set_physics_process(true); await ticks(90)
	var start: Vector3=game.player.position
	observer.reset(); observer.sampling=true; game.controls.set_key(KEY_W,true,Time.get_ticks_usec()); await ticks(150); game.controls.set_key(KEY_W,false,Time.get_ticks_usec()); observer.sampling=false
	game._clear_motion(); game.set_physics_process(false)
	var result: Dictionary=observer.result(); result.phase="courtyard walk / names "+("on" if labels_on else "off"); result.distance=start.distance_to(game.player.position); metrics.legs.append(result)
	check(result.distance>3 and result.frames>30,"player traverses courtyard with names "+("on" if labels_on else "off"))
func scatter_sample() -> void:
	var spawn: Vector3=game.player.position
	var placed:=0
	for attempt in 12:
		var point:=spawn+Vector3(cos(attempt*TAU/12)*10,0,sin(attempt*TAU/12)*10)
		var ground: Dictionary=game.structures.blocks.raycast_scene(point+Vector3.UP*4,point-Vector3.UP*8,7,[game.player.get_rid()])
		if ground.is_empty() or ground.normal.y<.94 or ground.collider==game.structures.blocks or game.structures.model_collections().values().has(ground.collider): continue
		aim(ground.position+Vector3(0,3,1),ground.position); await ticks(30)
		await game.outdoor_scatter.scatter_at_aim(game)
		placed=int(game.outdoor_scatter.last_result.get("placed",0))
		if placed>0: break
	print("LIVE_OUTDOOR_SCATTER ",game.outdoor_scatter.last_result)
	check(placed>0 and placed<=20,"developer scatter places a bounded patch on actual supported terrain")
	game.player.position=spawn
func capture(name: String) -> void:
	await process_frame; await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(name+".png"))==OK,"capture "+name)
func finish() -> void:
	metrics.checks=checks; metrics.failures=failures
	FileAccess.open(folder.path_join("object_performance.json"),FileAccess.WRITE).store_string(JSON.stringify(metrics,"  "))
	if game!=null:
		game.shutdown_requested=true; check(await game.terrain.shutdown_after_edits(),"temporary world shuts down cleanly"); game.free()
	await process_frame; await process_frame
	print("OBJECT_SYSTEM_WORLD checks=",checks," failures=",failures); quit(1 if failures else 0)
