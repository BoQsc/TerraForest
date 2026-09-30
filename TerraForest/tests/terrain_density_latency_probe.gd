extends SceneTree
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
var samples: Array[Dictionary]=[]
var checks: Array[Dictionary]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"passed":ok,"name":label});print("PASS " if ok else "FAIL ",label)
func run_case(size: int,load_count: int,repetition: int) -> void:
	var backend=Backend.new();backend.disk_cache.enabled=false
	check(backend.start(true)==OK,"backend starts %d/%d/%d" % [size,load_count,repetition])
	var ready:=false;var deadline:=Time.get_ticks_msec()+15000
	while not ready and Time.get_ticks_msec()<deadline:
		for result: Dictionary in backend.poll():
			if result.kind=="startup": ready=true
		await process_frame
	check(ready,"startup ready")
	for i in range(load_count):
		check(backend.submit({"kind":"mesh","key":Vector3i(768+i*size,768,size),"epoch":0,"stamp":0,"base":false}),"mesh load admitted")
	var submitted: Dictionary={}
	var queued_before: int=backend.queued()
	var active_before: String=backend.status()
	for token in range(8):
		submitted[token]=Time.get_ticks_usec()
		check(backend.submit({"kind":"density_ray","from":Vector3(1288,1.02,1288),"to":Vector3(1288,0.98,1288),"budget":256,"token":token,"epoch":0,"revision":0}),"query load admitted")
	var received:=0;var meshes:=0;var mesh_ms:=0.0
	deadline=Time.get_ticks_msec()+15000
	while received<8 and Time.get_ticks_msec()<deadline:
		for result: Dictionary in backend.poll():
			if result.kind=="mesh":
				meshes+=1;mesh_ms+=float(result.get("worker_ms",0))
				check(not result.has("error") and not result.get("cancelled",false),"mesh load completes")
			elif result.kind=="density_ray":
				received+=1
				check(result.status=="hit","query still correct under load")
				samples.append({"size":size,"load_count":load_count,"repetition":repetition,"token":result.token,"queued_before":queued_before,"active_before":active_before,"queue_ms":result.queue_ms,"query_ms":result.query_ms,"delivery_ms":(Time.get_ticks_usec()-int(result.worker_finished_us))/1000.0,"total_ms":(Time.get_ticks_usec()-int(submitted[result.token]))/1000.0,"preceding_mesh_ms":mesh_ms})
		await process_frame
	check(received==8 and meshes==load_count,"all accepted work accounted for")
	backend.stop()
func run() -> void:
	for repetition in range(3):
		await run_case(16,0,repetition)
		for size in [16,64,256]:
			for count in [1,4]: await run_case(size,count,repetition)
	var correctness_failures:=0
	for row: Dictionary in checks:
		if not row.passed: correctness_failures+=1
	# Early interactive rejection gate, not a claim of 60 FPS qualification.
	var latency_failures:=0
	for row: Dictionary in samples:
		if row.total_ms>50.0: latency_failures+=1
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/terrain_density_latency_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"samples":samples,"correctness_failures":correctness_failures,"latency_failures":latency_failures,"failures":correctness_failures+latency_failures,"gate_ms":50.0,"scope":"Headless CPU worker scheduling test, fresh worlds, disk cache disabled, eight-query bursts behind 0/1/4 mesh jobs. No 1080p rendering, player polling cadence or FPS qualification."},"  "));file.close()
	print("Latency failures: ",latency_failures," / ",samples.size())
	quit(0 if correctness_failures+latency_failures==0 else 1)
