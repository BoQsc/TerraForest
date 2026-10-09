# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	var game=load("res://demo/structures.tscn").instantiate();root.add_child(game)
	game.set_process(false)
	for prop in game.props: prop.free()
	game.props.clear()
	var blank=ClassDB.instantiate("NativeBlockWorld");game.buildings.restore_snapshot(blank.capture_snapshot());blank.free()
	var asset=ClassDB.instantiate("NativeBlockPrefab")
	var passed: bool=asset.compose_frontage([load("res://addons/structures/prefabs/brick_cottage.tres")],64,8,3,1703)
	game.camera.position=Vector3(384,250,360);game.camera.look_at(Vector3(384,0,0))
	game.camera.far=2000;game.buildings.set_focus(Vector3(384,5,0))
	for i in 10: await process_frame
	var start:=Time.get_ticks_usec()
	passed=passed and game.buildings.place_prefab(asset,Vector3i.ZERO,0,false)
	var insert_us:=Time.get_ticks_usec()-start
	var intervals:=PackedFloat64Array();var previous:=Time.get_ticks_usec()
	var deadline:=Time.get_ticks_msec()+15000;var max_chunks:=0;var max_upload_us:=0
	var slow_frames: Array[Dictionary]=[]
	while not game.buildings.is_idle() and Time.get_ticks_msec()<deadline:
		await process_frame
		var now:=Time.get_ticks_usec();intervals.append((now-previous)/1000.0);previous=now
		var uploads: Dictionary=game.buildings.streaming_stats()
		max_chunks=maxi(max_chunks,uploads.upload_last_chunks);max_upload_us=maxi(max_upload_us,uploads.upload_last_us)
		if intervals[-1]>25: slow_frames.append({"frame_ms":intervals[-1],"upload_us":uploads.upload_last_us,"upload_chunks":uploads.upload_last_chunks,"stats":game.buildings.stats()})
	var publication_ms: float=(Time.get_ticks_usec()-start)/1000.0
	passed=passed and game.buildings.is_idle()
	var stats: Dictionary=game.buildings.stats()
	passed=passed and stats.cells==asset.get_cell_count() and stats.mesh_chunks>0
	intervals.sort()
	var result:={"passed":passed,"insert_us":insert_us,"publication_ms":publication_ms,"publication_frames":intervals.size(),"max_upload_chunks_per_tick":max_chunks,"max_upload_us":max_upload_us,"frame_p95_ms":intervals[int((intervals.size()-1)*0.95)] if not intervals.is_empty() else 0,"frame_max_ms":intervals[-1] if not intervals.is_empty() else 0,"stats":stats,"scope":"128 cottage isolated structure fixture at 1920x1080 fullscreen Forward+, 60 FPS cap. Includes mesh publication; excludes terrain, vegetation, entities, sustained thermal qualification."}
	result["slow_frames"]=slow_frames;result["uploads"]=game.buildings.streaming_stats();result["collision"]=game.buildings.collision_stats()
	game.label.text="128 cottages · %d cells\nIsolated structure publication test\nTerrain / forest / entities excluded" % asset.get_cell_count()
	if DisplayServer.get_name()!="headless":
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/settlement_publication.png")
	var file:=FileAccess.open("res://reports/settlement_publication.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print(JSON.stringify(result));game.free();quit(0 if passed else 1)
