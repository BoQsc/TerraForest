# SPDX-License-Identifier: 0BSD
extends "res://tests/terrain_worker_publication_probe.gd"

class QueryOrderProbe extends "res://addons/volumetric_terrain/terrain_backend.gd":
	var served: Array=[]
	func _execute_density_query(job: Dictionary) -> void:
		served.append(job.id)
	func _execute_mesh(job: Dictionary, interactive: bool=false) -> void:
		served.append(job.id)

# A target must be discoverable without creating any scene collision. Compare
# idle and queued terrain work to expose whether the query merely moves the wait.
func run() -> void:
	Engine.max_fps=60
	var ordering:=QueryOrderProbe.new()
	for barrier in ["edit","reset","load","save","partition","lake_slice","unknown"]:
		ordering.jobs.assign([{"kind":"mesh"},{"kind":barrier},{"kind":"density_ray","id":1}])
		ordering._service_density_query()
		check(ordering.served.is_empty() and ordering.jobs.size()==3,"query preserves barrier "+barrier)
	ordering.jobs.assign([{"kind":"mesh"},{"kind":"density_ray","id":1},{"kind":"density_ray","id":2}])
	ordering._service_density_query()
	check(ordering.served==[1] and ordering.jobs.size()==2,"one FIFO query per regional boundary")
	ordering.stopping=true
	ordering._service_density_query()
	check(ordering.served==[1],"stopping prevents cooperative queries")
	ordering=null
	ordering=QueryOrderProbe.new()
	for barrier in ["edit","reset","load","save","partition","lake_slice","unknown"]:
		ordering.jobs.assign([{"kind":"mesh"},{"kind":barrier},{"kind":"mesh","interaction_mesh":true,"id":3}])
		ordering._service_interaction_mesh()
		check(ordering.served.is_empty() and ordering.jobs.size()==3,"local mesh preserves barrier "+barrier)
	ordering.jobs.assign([{"kind":"surface_batch"},{"kind":"mesh","interaction_mesh":true,"id":3},{"kind":"mesh","interaction_mesh":true,"id":4}])
	ordering._service_interaction_mesh()
	check(ordering.served==[3] and ordering.jobs.size()==2,"one local mesh per background boundary")
	ordering.stopping=true
	ordering._service_interaction_mesh()
	check(ordering.served==[3],"shutdown prevents cooperative local builds")
	ordering.stopping=false
	ordering.jobs.assign([{"kind":"edit"}])
	check(ordering.submit({"kind":"mesh","key":Vector3i(0,0,16),"interaction_mesh":true},true),"interactive slot accepts first bounded tile")
	check(ordering.jobs.front().kind=="edit","priority submission itself cannot cross a queued mutation")
	check(ordering.submit({"kind":"mesh","key":Vector3i(16,0,16),"interaction_mesh":true},true),"interactive slot accepts second bounded tile")
	check(not ordering.submit({"kind":"mesh","key":Vector3i(32,0,16),"interaction_mesh":true},true),"interactive queue refuses unbounded third tile")
	check(not ordering.submit({"kind":"mesh","key":Vector3i(0,0,128),"interaction_mesh":true},true),"coarse container cannot masquerade as bounded interactive work")
	ordering=null
	var rows: Array=[]
	for queued in [false,true]:
		world=FixedCut.new();root.add_child(world);world.set_process(false)
		world.backend.region_terrain=true
		world.backend.disk_cache.enabled=false
		check(world.start(StandardMaterial3D.new(),true)==OK,"query world starts")
		check(await pump_until(func(): return world.world_ready),"query world ready")
		var hits: Array[Dictionary]=[]
		world.density_ray_received.connect(func(reply: Dictionary): hits.append(reply))
		if queued:
			for key in [Vector3i(1024,1024,256),Vector3i(1280,1024,256)]:
				check(world.backend.submit({"kind":"mesh","key":key,"epoch":world.epoch,"stamp":0,"base":false}),"background mesh admitted")
		var started:=Time.get_ticks_usec()
		check(world.request_density_ray(Vector3(1308,180,1260),Vector3(1308,60,1260),123,256),"collision-independent target query admitted")
		check(await pump_until(func(): return not hits.is_empty(),false),"target query returns")
		var row: Dictionary=hits[0] if not hits.is_empty() else {"status":"missing"}
		row["elapsed_ms"]=(Time.get_ticks_usec()-started)/1000.0
		row["background_queued"]=queued
		check(row.status=="hit","canonical field supplies target")
		check(row.has("normal") and is_equal_approx(row.normal.length(),1.0) and row.normal.y>0,"query supplies a finite outward unit normal")
		check(world.tiles.is_empty(),"query requires no published terrain or physics collision")
		check(float(row.elapsed_ms)<=150.0,"target query including delivery stays within 150ms")
		if queued:
			var local:=Vector3i(1296,1248,16)
			var local_started:=Time.get_ticks_usec()
			check(world.backend.submit({"kind":"mesh","key":local,"epoch":world.epoch,"stamp":0,"base":false,"interaction_mesh":true},true),"local build gets bounded interactive slot")
			check(await pump_until(func(): return world.tiles.has(local)),"local build reaches real scene publication")
			row["local_build_delivery_ms"]=(Time.get_ticks_usec()-local_started)/1000.0
			check(row.local_build_delivery_ms<=150,"local build bypasses background containers within 150ms")
			check(await pump_until(func(): return world.tiles.has(Vector3i(1024,1024,256)) and world.tiles.has(Vector3i(1280,1024,256))),"both background meshes finish after cooperative query")
			check(world.backend._density_pending==0,"query result releases bounded query slot")
		rows.append(row)
		world.shutdown();world.free();await process_frame
	var file:=FileAccess.open("res://reports/terrain_target_readiness_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"rows":rows,"scope":"Native density target query without published geometry, idle versus two queued regional mesh builds; no rendering or controller integration."},"  "));file.close()
	print("TARGET_READINESS ",JSON.stringify(rows))
	quit(1 if failures else 0)
