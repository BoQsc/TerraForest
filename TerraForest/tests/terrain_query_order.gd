# SPDX-License-Identifier: 0BSD
extends SceneTree
class Probe:
	extends "res://addons/volumetric_terrain/terrain_backend.gd"
	var served: Array[int]=[]
	func _execute_density_batch(job: Dictionary) -> void: served.append(job.token)
	func _execute_density_query(job: Dictionary) -> void: served.append(job.token)
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void:
	var backend=Probe.new()
	backend.jobs.assign([{"kind":"mesh"},{"kind":"relight"},{"kind":"density_batch","token":1},{"kind":"density_ray","token":2}])
	backend._service_density_query()
	check(backend.served==[1] and backend.jobs.size()==3,"one batch bypasses background work without discarding it")
	backend._service_density_query()
	check(backend.served==[1,2],"ray and batch queries preserve their relative order")
	for barrier in ["edit","save","load","reset","future_unknown"]:
		backend.jobs.assign([{"kind":"mesh"},{"kind":barrier},{"kind":"density_batch","token":3}])
		backend._service_density_query()
		check(backend.served==[1,2] and backend.jobs.size()==3,"query does not cross "+barrier)
	backend.jobs.assign([{"kind":"density_batch","token":4}]);backend.stopping=true
	backend._service_density_query()
	check(backend.served==[1,2] and backend.jobs.size()==1,"stopping leaves cancellation to shutdown")
	quit(1 if failures else 0)
