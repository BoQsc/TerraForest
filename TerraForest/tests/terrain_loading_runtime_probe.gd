# SPDX-License-Identifier: 0BSD
extends "res://tests/terrain_worker_publication_probe.gd"

# Real scheduler, worker, preparation and coverage; no manually selected cut.
# Headless: measures readiness/publication only, not rendered frame pacing.
func run() -> void:
	Engine.max_fps=60
	world=Stream.new();root.add_child(world);world.set_process(false)
	world.backend.region_terrain=true
	world.backend.profile_regions=true
	world.backend.cache_path="user://loading_runtime_probe/%d"%OS.get_process_id()
	world.focus=Vector3(1200,100,1334)
	var flying:=OS.get_cmdline_user_args().has("--flying")
	world.require_collision=not flying
	check(world.start(StandardMaterial3D.new(),true)==OK,"real stream starts")
	check(await pump_until(func(): return world.world_ready),"real world ready")
	var replayed:=0
	if OS.get_cmdline_user_args().has("--replay-history"):
		var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mining_short_replay.json"))
		# Setup only: worker is idle, no presentations exist yet. Measured edits
		# below still use the public transaction and real scheduler.
		var replay_ok:=true
		for edit: Dictionary in fixture.history:
			var point:=Vector3(edit.a[0],edit.a[1],edit.a[2])
			replay_ok=replay_ok and Codec.reply_ok(world.backend.native.execute(Codec.brush(point,point,edit.radius,0,edit.add,1)))
			replayed+=1
		check(replay_ok,"saved failing mining history replays successfully")
		world._read_stats(world.backend.native.execute(Codec.command(0)))
		world._read_modified(world.backend.native.execute(Codec.command(10)))
	var root_key:=Vector3i(1024,1280,256)
	check(world.backend.submit({"kind":"mesh","key":root_key,"epoch":world.epoch,"stamp":0,"base":true}),"initial coarse coverage admitted")
	check(await pump_until(func(): return world.tiles.has(root_key)),"initial coarse coverage published")
	world._update_cut()
	check(world.visible_cut.has(root_key),"real planner displays initial coarse root")
	var initial_geometry:=geometry_digest(world.tiles[root_key])
	world.set_brush_active(true)
	var started:=Time.get_ticks_usec()
	var deadline:=Time.get_ticks_msec()+3000
	var coverage_preserved:=true
	while not world.player_region_ready(world.focus) and Time.get_ticks_msec()<deadline:
		world._process(1.0/60.0)
		coverage_preserved=coverage_preserved and world.covered_roots.has(root_key)
		await process_frame
	var ready:=world.player_region_ready(world.focus)
	var readiness_ms: float=(Time.get_ticks_usec()-started)/1000.0
	check(coverage_preserved,"initial world coverage remains complete during handover")
	check(ready,"held mining button permits local collision activation within three seconds")
	var edits: Array=[]
	var paced:=OS.get_cmdline_user_args().has("--paced-travel")
	var travel_started:=Time.get_ticks_usec()
	if ready:
		for step in range(24 if paced else 4):
			var due_us: int=travel_started+step*125000 if paced else Time.get_ticks_usec()
			while Time.get_ticks_usec()<due_us:
				world._process(1.0/60.0)
				await process_frame
			var point:=Vector3(1200+step*(2 if paced else 8),0,1334)
			var input_us:=Time.get_ticks_usec()
			var height: PackedByteArray=world.backend.native.execute(Codec.point_command(point))
			check(Codec.reply_ok(height),"travel target height available")
			point.y=height.decode_float(12)
			world.focus=point
			var ready_before:=world.player_region_ready(point)
			var revision: int=world.published_revision
			check(world.edit(Codec.brush(point,point,4,0,false,1),point-Vector3.ONE*9,point+Vector3.ONE*9),"travel mining admitted")
			deadline=Time.get_ticks_msec()+2000
			while world.pending_edit and Time.get_ticks_msec()<deadline:
				world._process(1.0/60.0)
				await process_frame
			check(not world.pending_edit and world.published_revision==revision+1,"travel mining changes and publishes terrain")
			check(world.covered_roots.has(root_key),"travel mining retains root coverage")
			edits.append({"step":step,"ready_before":ready_before,"arrival_lag_ms":(input_us-due_us)/1000.0,"input_through_publication_ms":(Time.get_ticks_usec()-input_us)/1000.0,"publish_ms":world.last_latency_ms,"worker_ms":world.last_total_build_ms})
	var latencies: Array[float]=[]
	var ready_count:=0
	var max_arrival_lag:=0.0
	for row: Dictionary in edits:
		latencies.append(row.input_through_publication_ms)
		if row.ready_before: ready_count+=1
		max_arrival_lag=maxf(max_arrival_lag,row.arrival_lag_ms)
	latencies.sort()
	var p95: float=latencies[mini(latencies.size()-1,ceili(latencies.size()*.95)-1)] if not latencies.is_empty() else INF
	if paced:
		check(edits.size()==24 and ready_count==24,"paced travel keeps every mining destination ready")
		check(p95<=150.0,"paced input-through-publication p95 remains within 150ms")
		check(max_arrival_lag<=50.0,"paced travel does not accumulate more than 50ms arrival lag")
	var result: Dictionary={"checks":checks,"ready":ready,"readiness_ms":readiness_ms,"paced":paced,"travel_ms":(Time.get_ticks_usec()-travel_started)/1000.0,"input_p95_ms":p95,"ready_destinations":ready_count,"max_arrival_lag_ms":max_arrival_lag,"edits":edits,"resident_tiles":world.tiles.size(),"visible_tiles":world.visible_cut.size(),"scope":"Real terrain scheduler and worker, coarse root initially resident, held brush readiness then travel/mining. Paced mode: 24 two-metre steps every 125ms (nominal 16m/s, 8 edits/s); immediate mode: four 8m steps without travel delay. Arrival lag exposes inability to maintain the nominal pace. Headless regression, not graphical FPS or endurance. Input-through-publication includes synchronous height query."}
	result["replayed_edits"]=replayed
	result["flying"]=flying
	if OS.get_cmdline_user_args().has("--distant-check"):
		world.set_brush_active(false)
		world.require_collision=false
		world.focus=Vector3(1200,1200,1334)
		world.schedule_timer=0
		var distant_started:=Time.get_ticks_usec()
		deadline=Time.get_ticks_msec()+4000
		var stale_exposed:=false
		var kept_coverage:=true
		while Time.get_ticks_msec()<deadline:
			world._process(1.0/60.0)
			kept_coverage=kept_coverage and world.covered_roots.has(root_key)
			stale_exposed=stale_exposed or (world.visible_cut.has(root_key) and world.tiles[root_key].dirty)
			if world.visible_cut.has(root_key) and not world.tiles[root_key].dirty: break
			await process_frame
		check(kept_coverage and not stale_exposed,"distant handover preserves coverage and never exposes the stale parent")
		check(world.visible_cut.has(root_key) and not world.tiles[root_key].dirty,"real distant scheduler publishes current coarse terrain")
		check(geometry_digest(world.tiles[root_key])!=initial_geometry,"distant representation includes geometry changes from mining")
		result["distant_handover_ms"]=(Time.get_ticks_usec()-distant_started)/1000.0
	world.shutdown();world.free();await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	var suffix: String=("_paced" if paced else "")+("_history" if replayed else "")
	if flying: suffix+="_flying"
	var file:=FileAccess.open("res://reports/terrain_loading_runtime_probe%s.json"%suffix,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("LOADING_RUNTIME ",JSON.stringify(result))
	quit(1 if failures else 0)

func geometry_digest(entry: Dictionary) -> String:
	var digest:=HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	var ids: Array=entry.bricks.keys()
	ids.sort()
	for id: int in ids:
		var arrays: Array=entry.bricks[id].arrays
		var vertices: PackedByteArray=arrays[Mesh.ARRAY_VERTEX].to_byte_array()
		var indices: PackedByteArray=arrays[Mesh.ARRAY_INDEX].to_byte_array()
		digest.update(PackedInt32Array([id,vertices.size(),indices.size()]).to_byte_array())
		if not vertices.is_empty(): digest.update(vertices)
		if not indices.is_empty(): digest.update(indices)
	return digest.finish().hex_encode()
