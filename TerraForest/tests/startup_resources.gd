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
func run()->void:
	process_frame.connect(func():beats+=1)
	var owner:=Node.new();root.add_child(owner)
	var resources=preload("res://addons/world_runtime/startup_resources.gd").new()
	var ok:bool=await resources.prepare(owner,"res://demo/world.gd")
	check(ok and not resources.retained.is_empty(),"startup retains successfully loaded resources")
	check(beats>5,"cold loading yields to the UI between real work")
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
	for frame in 3:await process_frame
	print("STARTUP_RESOURCES checks=",checks," failures=",failures);quit(1 if failures else 0)
