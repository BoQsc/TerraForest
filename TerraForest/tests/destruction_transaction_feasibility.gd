# SPDX-License-Identifier: 0BSD
extends "res://tests/terrain_worker_publication_probe.gd"
## Test-only coalesced native-worker prototype. Production's four-stroke limit
## is untouched. Four envelope corners select the exact affected region set;
## the backend receives all 256 ordered sphere edits and rebuilds each region once.
class CohortBackend extends "res://addons/volumetric_terrain/terrain_backend.gd":
	var cohort:Array[PackedByteArray]=[]
	var submitted_commands:=0
	func submit(job:Dictionary,priority:bool=false)->bool:
		if job.get("kind","")=="edit":
			job=job.duplicate()
			job.commands=cohort
			job.command=cohort[0]
			submitted_commands=cohort.size()
		return super.submit(job,priority)

func run()->void:
	world=FixedCut.new();world.backend=CohortBackend.new()
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--feasibility-generator="):world.backend.world_generator=int(argument.get_slice("=",1))
	root.add_child(world);world.set_process(false);world.material=StandardMaterial3D.new()
	world.backend.disk_cache.enabled=false
	check(world.backend.start(true)==OK,"prototype worker starts without saved world or cache")
	check(await pump_until(func():return world.world_ready),"prototype native world is ready")
	for z in [1280,1296]:
		for x in [1280,1296]:world.visible_cut.append(Vector3i(x,z,16))
	for key in world.visible_cut:
		check(world.backend.submit({"kind":"mesh","key":key,"epoch":world.epoch,"stamp":0,"base":false}),"prototype original region admitted")
	check(await pump_until(func():return world.tiles.size()==4),"all four original visual/collision regions published")
	var heights:Array[float]=[]
	world.height_received.connect(func(_point:Vector3,height:float,_token:int):heights.append(height))
	world.request_height(Vector3(1296,0,1296),1)
	check(await pump_until(func():return not heights.is_empty()),"prototype uses real terrain height")
	if heights.is_empty():world.shutdown();world.free();quit(1);return
	var commands:Array[PackedByteArray]=[]
	for z in 16:
		for x in 16:
			var point:=Vector3(1290+x*.75,heights[0],1290+z*.75)
			commands.append(Codec.brush(point,point,3.5,0,false,0))
	world.backend.cohort=commands
	var corners:Array[PackedByteArray]=[commands[0],commands[15],commands[240],commands[255]]
	var old:Dictionary=world.tiles.duplicate()
	var before:=await physics_hits(old,"prototype original collision")
	var stage_max:Dictionary={}
	var stage_total:Dictionary={}
	var stage_count:Dictionary={}
	var publication:Dictionary={}
	world.stage_measured.connect(func(label:String,ms:float):
		stage_max[label]=maxf(float(stage_max.get(label,0.0)),ms)
		stage_total[label]=float(stage_total.get(label,0.0))+ms
		stage_count[label]=int(stage_count.get(label,0))+1
		if label=="atomic publish":
			publication.tick=Engine.get_physics_frames()
			publication.at_us=Time.get_ticks_usec())
	var began:=Time.get_ticks_usec();var tick:=Engine.get_physics_frames()
	check(world.edit(corners[0],Vector3(1281.5,heights[0]-8.5,1281.5),Vector3(1309.75,heights[0]+8.5,1309.75),began,corners),"coalesced prototype admitted")
	check(await pump_until(func():return not world.pending_edit),"coalesced native worker and actual physics publication complete")
	var elapsed_us:=int(publication.get("at_us",Time.get_ticks_usec()))-began
	var publication_tick:=int(publication.get("tick",Engine.get_physics_frames()))
	print("DESTRUCTION_PUBLICATION_STAGES ",JSON.stringify({"stage_total_ms":stage_total,"stage_count":stage_count,"note":"Nested stage totals overlap; do not add them together or treat polling waits as CPU execution."}))
	check(world.backend.submitted_commands==256 and world.latest_member_changes.size()==256,"all 256 ordered sphere commands executed")
	check(world.published_revision==1 and world.batch_remaining==0,"one atomic terrain publication replaces the cohort")
	var after:=await physics_hits(world.tiles,"prototype replacement collision")
	var lowered:=0
	for i in before.size():
		if after[i]<before[i]-.01:lowered+=1
	check(lowered==4,"all four original surface queries see excavated collision")
	print("DESTRUCTION_TRANSACTION_FEASIBILITY ",JSON.stringify({"commands":256,"regions":4,"elapsed_us":elapsed_us,"trigger_tick":tick,"deadline_tick":tick+1,"publication_tick":publication_tick,"field_ms":world.last_edit_ms,"worker_build_ms":world.last_total_build_ms,"worker_queue_ms":world.last_queue_ms,"publication_ms":world.last_commit_ms,"stage_max_ms":stage_max,"scope":"Best-case overlapping cohort, native field and one rebuild per region, actual incremental Jolt preparation/publication. No blocks, damage, effects, GPU render or end-to-end acceptance; production limits unchanged."}))
	check(publication_tick<=tick+1 and elapsed_us<=16667,"coalesced exact terrain meets the next-physics-tick deadline")
	world.shutdown();world.free();await process_frame
	print("DESTRUCTION_TRANSACTION_FEASIBILITY failures=",failures);quit(1 if failures else 0)
