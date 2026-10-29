# SPDX-License-Identifier: 0BSD
extends SceneTree
class Probe:
	extends "res://addons/volumetric_terrain/terrain_backend.gd"
	var served: Array[int]=[]
	func _execute_density_batch(job: Dictionary) -> void: served.append(job.token)
	func _execute_density_query(job: Dictionary) -> void: served.append(job.token)
	func _execute_surface_batch(job:Dictionary)->void:served.append(job.token)
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
	backend.stopping=false;backend.served.clear();backend.jobs.assign([{"kind":"mesh"},{"kind":"relight"},{"kind":"height"}])
	for token in range(10,18):backend.jobs.append({"kind":"surface_batch","token":token})
	backend._service_surface_batches(100000)
	check(backend.served==[10,11,12,13] and backend.jobs.size()==7 and backend.jobs[0].kind=="mesh","four surface batches bypass background work without removing it")
	backend._service_surface_batches(0)
	check(backend.served==[10,11,12,13,14] and backend.jobs.size()==6,"elapsed budget stops after a single bounded batch")
	for barrier in ["edit","save","load","reset","material_edit","density_ray","density_batch","placement_target","lake_slice","future_unknown"]:
		backend.served.clear();backend.jobs.assign([{"kind":"mesh"},{"kind":barrier},{"kind":"surface_batch","token":20}])
		backend._service_surface_batches()
		check(backend.served.is_empty() and backend.jobs.size()==3,"surface sampling does not cross "+barrier)
	backend.jobs.assign([{"kind":"mesh","interaction_mesh":true},{"kind":"surface_batch","token":21}])
	backend._service_surface_batches()
	check(backend.served.is_empty() and backend.jobs.size()==2,"urgent interaction collision remains ahead of vegetation")
	backend.jobs.assign([{"kind":"surface_batch","token":22}]);backend.stopping=true
	backend._service_surface_batches()
	check(backend.served.is_empty() and backend.jobs.size()==1,"surface sampling respects shutdown")
	print("TERRAIN_QUERY_ORDER failures=",failures)
	quit(1 if failures else 0)
