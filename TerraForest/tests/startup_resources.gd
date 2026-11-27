# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var beats:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func authoring_probe(resources:RefCounted)->WeakRef:
	# Keep the iterator's strong Resource reference out of the lifetime check.
	for resource:Resource in resources.retained:
		if resource.resource_path=="res://addons/structures/packs/homestead_01/models/bed.tres":return weakref(resource)
	return null
func temporary_authoring(owner:Node)->WeakRef:
	var resources=preload("res://addons/world_runtime/startup_resources.gd").new()
	if not await resources.prepare_authoring(owner):return null
	return authoring_probe(resources)
func run()->void:
	Engine.max_fps=60
	process_frame.connect(func():beats+=1)
	var owner:=Node.new();root.add_child(owner)
	var released_input:WeakRef=await temporary_authoring(owner)
	for frame in 3:await process_frame
	check(released_input!=null and released_input.get_ref()==null,"raw authoring mesh is released after its preparation scope returns")
	var cancelled_resources=preload("res://addons/world_runtime/startup_resources.gd").new()
	check(cancelled_resources.begin_independent("res://demo/world.gd") and not cancelled_resources.independent_pending.is_empty(),"independent presentation prefetch submits a bounded window")
	check(cancelled_resources.independent_queue.all(func(path:String):return not path.ends_with(".gd") and not path.begins_with("res://addons/structures/")),"independent loads exclude scripts and planning prefabs")
	cancelled_resources.cancelled=true
	var cancelled_ok:bool=await cancelled_resources.finish_independent(owner)
	check(not cancelled_ok and cancelled_resources.independent_pending.is_empty() and cancelled_resources.independent_queue.is_empty(),"cancel drains independent handles without submitting the remaining queue")
	check(cancelled_resources.independent_started<=cancelled_resources.PREFETCH_LIMIT,"cancelled prefetch remains within its admission window")
	cancelled_resources=null
	var cancelled_authoring=preload("res://addons/world_runtime/startup_resources.gd").new()
	process_frame.connect(func():cancelled_authoring.cancelled=true,CONNECT_ONE_SHOT)
	var authoring_ok:bool=await cancelled_authoring.prepare_authoring(owner)
	check(not authoring_ok and not cancelled_authoring.authoring_prepared,"cancel during authoring preparation prevents planning readiness")
	check(cancelled_authoring.retained.size()<=cancelled_authoring.PREFETCH_LIMIT,"authoring cancellation drains only the bounded submitted window")
	cancelled_authoring=null
	var resources=preload("res://addons/world_runtime/startup_resources.gd").new()
	var ok:bool=await resources.prepare(owner,"res://demo/world.gd")
	check(ok and not resources.retained.is_empty(),"startup retains successfully loaded resources")
	check(resources.authoring_count==0,"ordinary world loading avoids redundant authoring preparation")
	check(resources.peak_pending>1 and resources.peak_pending<=resources.PREFETCH_LIMIT,"cold resources use a bounded prefetch window")
	check(beats>5,"cold loading yields to the UI between real work")
	check(await resources.prepare(owner,"res://addons/world_runtime/world_generation_plan.gd"),"planning preparation retains authoring resources")
	check(resources.authoring_count==preload("res://addons/structures/pack_registry.gd").objects.size()+4,"planning retains all validated pack inputs and base furniture")
	var source_mesh:=authoring_probe(resources)
	check(source_mesh!=null,"raw authoring mesh remains owned during preparation")
	resources.retained.clear();resources=null;owner.free()
	var options=preload("res://addons/world_runtime/session_options.gd")
	options.set_arguments(PackedStringArray(["--startup-fixture"]),true)
	var job=preload("res://addons/world_runtime/scene_job.gd").new();root.add_child(job)
	job.start_path("res://addons/world_runtime/generation_coordinator.gd",PackedStringArray())
	job.cancel()
	var deadline:=Time.get_ticks_msec()+5000
	while not job.done and Time.get_ticks_msec()<deadline:await process_frame
	check(job.done and job.code==2,"cancel during startup prevents generation")
	check(options.arguments()==PackedStringArray(["--startup-fixture"]) and ProjectSettings.get_setting(options.OFFSCREEN,false),"cancel preserves owning session arguments")
	check(job.task==null and job.viewport==null,"cancel leaves no task or render viewport")
	job.free();options.reset()
	var planning=preload("res://addons/world_runtime/scene_job.gd").new();root.add_child(planning)
	var recipe=preload("res://addons/world_runtime/world_recipe.gd")
	planning.start_path("res://addons/world_runtime/generate_world_task.gd",PackedStringArray(["--world-seed=1703","--world-generator=29","--world-recipe="+Marshalls.raw_to_base64(recipe.encode(recipe.DEFAULTS))]),false)
	deadline=Time.get_ticks_msec()+15000
	while not planning.done and (planning.task==null or planning.task.planning_worker==null) and Time.get_ticks_msec()<deadline:await process_frame
	check(planning.task!=null and planning.task.planning_worker!=null,"production generation starts a real planning worker")
	planning.cancel();deadline=Time.get_ticks_msec()+45000
	while not planning.done and Time.get_ticks_msec()<deadline:await process_frame
	check(planning.done and planning.code==2,"cancelling during planning drains prefetch and joins the worker")
	check(planning.task==null and planning.viewport==null,"cancelled planning leaves no task or world behind")
	planning.free()
	for frame in 3:await process_frame
	print("STARTUP_RESOURCES checks=",checks," failures=",failures);quit(1 if failures else 0)
