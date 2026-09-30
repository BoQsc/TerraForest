extends SceneTree
const Backend = preload("res://addons/volumetric_terrain/terrain_backend.gd")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")

class HeldBackend extends Backend:
	var entered := Semaphore.new()
	var resume_build := Semaphore.new()
	func _build(key: Vector3i, allow_base_cache: bool, expected_build_epoch: int, relight_cache: bool=false) -> Dictionary:
		if key==Vector3i(0,0,256):
			entered.post()
			resume_build.wait()
			return {"cancelled":true}
		return super._build(key,allow_base_cache,expected_build_epoch,relight_cache)

var checks: Array[Dictionary]=[]
var failures := 0
var backend := HeldBackend.new()
var results: Array[Dictionary]=[]

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks.append({"pass":ok,"name":label})
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)

func until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec()+15000
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		results.append_array(backend.poll())
		await process_frame
	return predicate.call()

func run() -> void:
	check(backend.start(true)==OK,"queue fixture starts real native worker")
	check(await until(func(): return results.any(func(row): return row.kind=="startup")),"worker initialized")
	check(backend.submit({"kind":"mesh","key":Vector3i(0,0,256),"epoch":0,"stamp":0}),"held job admitted")
	var entered := false
	var deadline := Time.get_ticks_msec()+15000
	while not entered and Time.get_ticks_msec()<deadline:
		entered=backend.entered.try_wait()
		await process_frame
	check(entered,"worker held before queued work begins")
	var survivor := Vector3i(800,1312,16)
	var invalidated := Vector3i(1280,1280,16)
	check(backend.submit({"kind":"mesh","key":survivor,"epoch":0,"stamp":7,"base":false}),"unaffected fine mesh queued")
	check(backend.submit({"kind":"mesh","key":invalidated,"epoch":0,"stamp":8,"base":false}),"intersecting fine mesh queued")
	var point := Vector3(1288,150,1288)
	for index in range(3):
		check(backend.submit({"kind":"edit","command":Codec.brush(point,point,2,0,true,1),"tiles":[],"epoch":0,"ticket":index,"geometry_lo":point-Vector3.ONE*7,"geometry_hi":point+Vector3.ONE*7},true),"priority edit advances cancellation epoch %d" % index)
	backend.mutex.lock()
	var preserved: Array=backend.jobs.filter(func(row): return row.kind=="mesh" and row.key==survivor)
	var refresh_lighting: bool=preserved.size()==1 and preserved[0].get("relight_cache",false)
	backend.mutex.unlock()
	check(refresh_lighting,"retained geometry rechecks lighting after intervening edits")
	backend.resume_build.post()
	check(await until(func(): return results.any(func(row): return row.kind=="mesh" and row.key==survivor)),"queued unaffected mesh makes progress after three priority edits")
	var kept: Array=results.filter(func(row): return row.kind=="mesh" and row.key==survivor)
	check(kept.size()==1 and not kept[0].get("cancelled",false) and not kept[0].has("error") and kept[0].stamp==7,"unaffected mesh completes with its original dependency stamp")
	var removed: Array=results.filter(func(row): return row.kind=="mesh" and row.key==invalidated)
	check(removed.size()==1 and removed[0].get("cancelled",false) and removed[0].stamp==8,"intersecting queued mesh is cancelled exactly once")
	backend.stop()
	check(not backend.thread.is_started(),"queue fixture joins worker")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/terrain_queue_progress.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	file.close()
	quit(0 if failures==0 else 1)
