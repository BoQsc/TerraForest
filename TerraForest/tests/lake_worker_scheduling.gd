# SPDX-License-Identifier: 0BSD
extends SceneTree
class Probe extends "res://addons/volumetric_terrain/terrain_backend.gd":
	var served: Array=[]
	func _execute_lake_slice(job: Dictionary) -> void: served.append(job.token)
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
	var worker=Probe.new()
	for barrier: String in ["edit","save","load","reset","partition","unknown"]:
		worker.jobs.assign([{"kind":"mesh"},{"kind":barrier},{"kind":"lake_slice","token":1}])
		worker._service_lake_slice()
		check(worker.served.is_empty() and worker.jobs.size()==3,"lake read does not cross "+barrier)
	worker.jobs.assign([{"kind":"mesh"},{"kind":"surface_batch"},{"kind":"lake_slice","token":1},{"kind":"lake_slice","token":2}])
	worker._service_lake_slice()
	check(worker.served==[1] and worker.jobs.size()==3 and worker.jobs[0].kind=="mesh","one slice advances while background work remains queued")
	worker.jobs.clear()
	var volume: RefCounted=ClassDB.instantiate("NativeLakeVolume")
	var job: Dictionary={"kind":"lake_slice","builder":volume,"token":volume.get_instance_id(),"epoch":0,"revision":0,"density_revision":0}
	check(worker.submit(job) and not worker.submit(job.duplicate()),"only one lake reservation is admitted")
	worker.jobs.clear();worker._push({"kind":"lake_slice"})
	check(not worker.submit(job.duplicate()),"unconsumed completion retains reservation")
	worker.poll()
	check(worker.submit(job.duplicate()),"consuming completion releases reservation")
	worker.jobs.clear();worker._push({"kind":"lake_slice"});worker.poll()
	check(not worker.submit({"kind":"lake_slice","builder":null}),"invalid lake builder rejected")
	worker=null
	quit(1 if failures else 0)
