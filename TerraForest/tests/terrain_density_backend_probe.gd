extends SceneTree
const Backend = preload("res://addons/volumetric_terrain/terrain_backend.gd")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
var backend: RefCounted
var checks: Array[Dictionary]=[]
var received: Array[Dictionary]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"passed":ok,"name":label});print("PASS " if ok else "FAIL ",label)
func job(token: int,revision: int=0) -> Dictionary:
	return {"kind":"density_ray","from":Vector3(1288,1.02,1288),"to":Vector3(1288,0.98,1288),"budget":4096,"token":token,"epoch":7,"revision":revision}
func gather(count: int) -> void:
	var end := Time.get_ticks_msec()+5000
	while received.size()<count and Time.get_ticks_msec()<end:
		for result: Dictionary in backend.poll():
			if result.kind=="density_ray": received.append(result)
		await process_frame
func run() -> void:
	backend=Backend.new();backend.disk_cache.enabled=false
	check(backend.start(true)==OK,"persistent terrain backend starts")
	var started := false;var end := Time.get_ticks_msec()+5000
	while not started and Time.get_ticks_msec()<end:
		for result: Dictionary in backend.poll():
			if result.kind=="startup": started=true
		await process_frame
	check(started,"startup completes")
	for i in range(8):
		var request := job(i,999 if i==3 else 0)
		if i in [1,2]:
			request.from=Vector3(100,250,100);request.to=Vector3(110 if i==1 else 100.1,250,100);request.budget=1 if i==1 else 4096
		check(backend.submit(request),"query admitted %d" % i)
		request.token=9999;request.from=Vector3.ZERO
	check(not backend.submit(job(8)),"ninth unconsumed query rejected")
	await gather(8)
	check(received.size()==8,"every admitted query completes")
	var tokens: Dictionary={}
	for result: Dictionary in received:
		tokens[result.token]=true
		var expected := "work_limit" if result.token==1 else ("miss" if result.token==2 else ("stale" if result.token==3 else "hit"))
		check(result.status==expected and result.epoch==7 and (result.status=="hit" or not result.has("position")),"typed query outcome %d" % result.token)
	check(tokens.size()==8 and not tokens.has(9999),"caller mutation cannot alter queued request identity")
	received.clear()
	var edit := {"kind":"edit","command":Codec.brush(Vector3(1288,20,1288),Vector3(1288,20,1288),2,0,false,1),"tiles":[],"epoch":7,"ticket":1}
	check(backend.submit(edit),"mutation queued before queries")
	check(backend.submit(job(10),true),"query admitted with priority request behind mutation")
	check(backend.submit(job(11,1)),"query requesting next revision admitted")
	await gather(2)
	check(received.size()==2 and received[0].token==10 and received[0].status=="stale" and not received[0].has("position") and received[1].status=="hit" and received[1].revision==1,"mutation ordering and revision rejection preserved")
	var bad := job(30);bad.budget=0;check(not backend.submit(bad),"invalid query rejected before queue admission")
	bad=job(31);bad.from=Vector3(NAN,0,0);check(not backend.submit(bad),"nonfinite query rejected")
	check(Codec.decode_density_ray(PackedByteArray()).status=="error","malformed reply cannot become a miss")
	received.clear()
	for i in range(8): check(backend.submit(job(40+i,1)),"shutdown query admitted %d" % i)
	backend.stop()
	for result: Dictionary in backend.poll():
		if result.kind=="density_ray": received.append(result)
	check(received.size()==8 and backend._density_pending==0,"shutdown accounts for all accepted queries")
	check(not backend.submit(job(60,1)),"stopped backend rejects new query")
	var failures := 0
	for entry: Dictionary in checks:
		if not entry.passed: failures+=1
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/terrain_density_backend_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Real backend query queue, native execution, revision filtering and shutdown; no player consumption or latency/FPS qualification."},"  "));file.close()
	quit(0 if failures==0 else 1)
