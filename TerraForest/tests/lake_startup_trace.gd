# SPDX-License-Identifier: 0BSD
extends SceneTree
var started: int
var events: Array=[]
var slices:=0
var outcomes: Dictionary={}
var worker_ms:=0.0
var worker_max_ms:=0.0
var queue_max_ms:=0.0
func _initialize() -> void:run.call_deferred()
func run() -> void:
	started=Time.get_ticks_usec()
	var game=load("res://demo/world.tscn").instantiate()
	game.terrain.lake_slice_ready.connect(func(_token: int,status: int,_epoch: int,_revision: int):
		slices+=1;outcomes[str(status)]=outcomes.get(str(status),0)+1)
	game.lakes.lake_ready.connect(func(id: int):events.append({"id":id,"ms":(Time.get_ticks_usec()-started)/1000.0}))
	game.terrain.lake_slice_profiled.connect(func(work: float,queue: float,_status: int):
		worker_ms+=work;worker_max_ms=maxf(worker_max_ms,work);queue_max_ms=maxf(queue_max_ms,queue))
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	game.set_physics_process(false);game._clear_motion()
	var world_ready_ms: float=(Time.get_ticks_usec()-started)/1000.0
	var rows: Array=[];deadline=Time.get_ticks_msec()+25000
	var next_sample:=0
	while Time.get_ticks_msec()<deadline:
		await process_frame
		var now:=Time.get_ticks_msec()
		if now<next_sample:continue
		next_sample=now+100
		var stats: Dictionary=game.lakes.statistics()
		rows.append({"ms":(Time.get_ticks_usec()-started)/1000.0,"worker":game.terrain.backend.status(),"queued":game.terrain.backend.queued(),"lake_ready":stats.ready,"lake_total":stats.lakes,"lake_slices":slices})
		if stats.ready==4 and game.terrain.backend.status()=="idle" and game.terrain.backend.queued()==0:break
	var volumes: Array=[]
	for id in game.lakes._lakes:
		var item: Dictionary=game.lakes._lakes[id]
		# Only immutable published volumes are inspected; builder belongs to worker.
		volumes.append({"id":id,"cells":item.cells,"statistics":item.volume.statistics() if item.volume!=null else {}})
	var report:={"worker_ms":worker_ms,"worker_max_ms":worker_max_ms,"queue_max_ms":queue_max_ms,"world_ready_ms":world_ready_ms,"events":events,"slices":slices,"outcomes":outcomes,"rows":rows,"volumes":volumes,"final":game.lakes.statistics(),"slot":game.terrain.save_slot,"scope":"Startup attribution only: facade completion counts, published immutable volume stats, 10Hz worker status sampling. Status sampling does not measure worker CPU time. No changes to lake scheduling or persistent cache."}
	DirAccess.make_dir_recursive_absolute("res://reports/lake_startup")
	var file:=FileAccess.open("res://reports/lake_startup/trace.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("LAKE_STARTUP ",JSON.stringify({"worker_ms":worker_ms,"worker_max_ms":worker_max_ms,"queue_max_ms":queue_max_ms,"world_ready_ms":world_ready_ms,"events":events,"slices":slices,"outcomes":outcomes,"final":report.final}))
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit()
