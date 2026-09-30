extends SceneTree
var gate_mutex:=Mutex.new()
var stop_queries:=false
var cases: Array[Dictionary]=[]
func _initialize() -> void: run.call_deferred()
func query_loop(native) -> Dictionary:
	var ray:=PackedByteArray();ray.resize(36);ray.encode_u32(0,23)
	for i in range(6): ray.encode_float(4+i*4,[100.0,1.02,100.0,100.0,0.98,100.0][i])
	ray.encode_u32(28,256);ray.encode_u32(32,0)
	var durations: Array[float]=[];var errors:=0
	while true:
		gate_mutex.lock();var stop: bool=stop_queries;gate_mutex.unlock()
		if stop: break
		var start:=Time.get_ticks_usec();var reply: PackedByteArray=native.execute(ray)
		durations.append((Time.get_ticks_usec()-start)/1000.0)
		if reply.size()!=40 or reply.decode_u32(8)!=0 or reply.decode_u32(16)!=0: errors+=1
		OS.delay_usec(1000)
	return {"query_ms":durations,"query_errors":errors}
func run_case(count: int,repetition: int) -> void:
	var native=ClassDB.instantiate("TerrainCore")
	gate_mutex.lock();stop_queries=false;gate_mutex.unlock()
	var thread:=Thread.new();var thread_ok: bool=thread.start(query_loop.bind(native))==OK
	var submitted:=0;var finished:=0;var errors:=0;var rejected:=0
	var pending: Dictionary={};var seen: Dictionary={}
	var captures: Array[float]=[];var polls: Array[float]=[];var completion: Array[float]=[]
	var geometry_bytes:=0;var peak_packet_bytes:=0;var max_pending:=0
	var start:=Time.get_ticks_usec();var deadline:=Time.get_ticks_msec()+30000
	while finished<count and Time.get_ticks_msec()<deadline:
		while submitted<count and pending.size()<2:
			var token:=submitted;var cell:=token%64
			var begin:=Time.get_ticks_usec()
			var admitted: bool=native.experimental_snapshot_submit(960+(cell%8)*32,960+(cell/8)*32,32,token,0)
			captures.append((Time.get_ticks_usec()-begin)/1000.0)
			if not admitted: rejected+=1;break
			pending[token]=begin;submitted+=1;max_pending=maxi(max_pending,pending.size())
		var begin:=Time.get_ticks_usec();var rows: Array=native.experimental_snapshot_poll();polls.append((Time.get_ticks_usec()-begin)/1000.0)
		var packet_bytes:=0
		for row: Dictionary in rows:
			if not pending.has(row.token) or seen.has(row.token): errors+=1;continue
			completion.append((Time.get_ticks_usec()-int(pending[row.token]))/1000.0)
			pending.erase(row.token);seen[row.token]=true;finished+=1
			if row.status!=0 or row.stale or row.positions.is_empty() or row.indices.is_empty(): errors+=1
			packet_bytes+=row.positions.size()+row.indices.size()
		geometry_bytes+=packet_bytes;peak_packet_bytes=maxi(peak_packet_bytes,packet_bytes)
		await process_frame
	var elapsed: float=(Time.get_ticks_usec()-start)/1000.0
	gate_mutex.lock();stop_queries=true;gate_mutex.unlock()
	var queries: Dictionary=thread.wait_to_finish() if thread_ok else {"query_ms":[],"query_errors":1}
	native.experimental_snapshot_stop();native=null
	var query_failures:=0;var main_failures:=0
	for duration: float in queries.query_ms:
		if duration>50.0: query_failures+=1
	for duration: float in captures+polls:
		if duration>16.667: main_failures+=1
	var correctness: bool=thread_ok and errors==0 and queries.query_errors==0 and submitted==count and finished==count and pending.is_empty() and seen.size()==count and queries.query_ms.size()>0
	var row: Dictionary={"count":count,"repetition":repetition,"submitted":submitted,"finished":finished,"correctness":correctness,"rejected":rejected,"max_pending":max_pending,"query_gate_failures":query_failures,"main_call_gate_failures":main_failures,"capture_ms":captures,"poll_ms":polls,"completion_ms":completion,"run_ms":elapsed,"geometry_bytes":geometry_bytes,"peak_packet_bytes":peak_packet_bytes}
	row.merge(queries);cases.append(row)
	print("CASE ",count,"/",repetition," complete=",finished," correct=",correctness," query failures=",query_failures," main-call failures=",main_failures)
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	if not ClassDB.class_exists("TerrainCore"): quit(1);return
	Engine.max_fps=60 # Consumer cadence only; headless is not a graphics benchmark.
	for repetition in range(2):
		for count in [64,256]: await run_case(count,repetition)
	var failures:=0
	for row: Dictionary in cases:
		failures+=int(not row.correctness)+row.query_gate_failures+row.main_call_gate_failures
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/command.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases":cases,"failures":failures,"query_gate_ms":50.0,"main_call_gate_ms":16.667},"  "));file.close()
	quit(0 if failures==0 else 1)
