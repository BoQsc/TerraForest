# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	var game=load("res://demo/structures.tscn").instantiate();root.add_child(game);game.set_process(false)
	for prop in game.props: prop.free()
	game.props.clear()
	var blank=ClassDB.instantiate("NativeBlockWorld");game.buildings.restore_snapshot(blank.capture_snapshot());blank.free()
	var asset=ClassDB.instantiate("NativeBlockPrefab");asset.compose_frontage([load("res://addons/structures/prefabs/brick_cottage.tres")],64,8,3,1703)
	var ok: bool=game.buildings.configure_streaming(true,192,128,16*1024*1024,16*1024*1024)
	game.buildings.set_focus(Vector3(10,3,0));ok=ok and game.buildings.place_prefab(asset,Vector3i.ZERO,0,false)
	var deadline:=Time.get_ticks_msec()+10000
	while not game.buildings.is_idle() and Time.get_ticks_msec()<deadline: await process_frame
	ok=ok and game.buildings.is_idle()
	var intervals:=PackedFloat64Array();var gaps:=0;var max_mesh_bytes:=0;var max_cache_bytes:=0;var max_chunks:=0
	var previous:=Time.get_ticks_usec();var start:=previous
	var gap_examples: Array[Dictionary]=[]
	for frame in 720:
		var t: float=float(frame%360)/359.0
		var x: float=lerpf(10,750,t) if frame<360 else lerpf(750,10,t)
		game.camera.position=Vector3(x,4,0);game.camera.look_at(Vector3(x+(20 if frame<360 else -20),4,0))
		game.buildings.set_focus(Vector3(x,3,0))
		await process_frame
		var now:=Time.get_ticks_usec();intervals.append((now-previous)/1000.0);previous=now
		var s: Dictionary=game.buildings.streaming_stats()
		max_mesh_bytes=maxi(max_mesh_bytes,s.mesh_payload_bytes);max_cache_bytes=maxi(max_cache_bytes,s.cache_capacity_bytes)
		max_chunks=maxi(max_chunks,game.buildings.stats().mesh_chunks)
		# Probe occupied roadside structures, not only the empty street corridor.
		if not game.buildings.is_collision_region_ready(AABB(Vector3(x-4,0,-20),Vector3(8,12,40))):
			gaps+=1
			if gap_examples.size()<8: gap_examples.append({"frame":frame,"x":x,"collision":game.buildings.collision_stats()})
	var elapsed_ms: float=(Time.get_ticks_usec()-start)/1000.0
	intervals.sort()
	ok=ok and max_mesh_bytes<=16*1024*1024 and max_cache_bytes<=16*1024*1024 and max_chunks<=128
	var result:={"bounds_passed":ok,"collision_gap_frames":gaps,"gap_examples":gap_examples,"max_mesh_bytes":max_mesh_bytes,"max_cache_bytes":max_cache_bytes,"max_chunks":max_chunks,"frame_p95_ms":intervals[683],"frame_max_ms":intervals[-1],"elapsed_ms":elapsed_ms,"distance":1480,"average_speed_mps":1480000.0/elapsed_ms,"streaming":game.buildings.streaming_stats(),"collision":game.buildings.collision_stats(),"scope":"720-frame isolated camera traverse out and back, 1920x1080 fullscreen Forward+ capped 60 FPS. Roadside readiness probes; no player/vehicle physics, terrain, vegetation or thermal claim."}
	game.label.text="128 cottages · streamed street traversal\nCamera test · terrain and entities excluded"
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/settlement_travel.png")
	var file:=FileAccess.open("res://reports/settlement_travel.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print(JSON.stringify(result));game.free();quit(0 if ok else 1)
