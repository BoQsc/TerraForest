# SPDX-License-Identifier: 0BSD
extends RefCounted
var retained:Array[Resource]=[]
var cancelled:=false
var slowest:Dictionary={}

func prepare(owner:Node,path:String,report:Callable=Callable())->bool:
	var decoded=JSON.parse_string(FileAccess.get_file_as_string("res://addons/world_runtime/startup_index.json"))
	if not decoded is Dictionary:return false
	var graph:Dictionary=decoded
	var ordered:Array[String]=[]
	var visited:Dictionary={}
	_collect(path,graph,visited,ordered)
	for dependency:String in graph.get(path,[]):
		if dependency.ends_with(".gd") and not ResourceLoader.has_cached(dependency):ordered.append(dependency)
	ordered.append(path)
	var deadline:=Time.get_ticks_usec()+8000
	for index in ordered.size():
		if cancelled:return false
		var started:=Time.get_ticks_usec()
		var resource:Resource
		var target:=ordered[index]
		if target.ends_with(".gd") or ResourceLoader.has_cached(target):resource=load(target)
		else:
			if ResourceLoader.load_threaded_request(target)!=OK:return false
			while ResourceLoader.load_threaded_get_status(target)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:await owner.get_tree().process_frame
			if ResourceLoader.load_threaded_get_status(target)!=ResourceLoader.THREAD_LOAD_LOADED:return false
			resource=ResourceLoader.load_threaded_get(target)
		if resource==null:return false
		var elapsed:=(Time.get_ticks_usec()-started)/1000.0
		if elapsed>float(slowest.get("ms",0)):slowest={"path":target,"ms":elapsed}
		retained.append(resource)
		if Time.get_ticks_usec()>=deadline:
			if report.is_valid():report.call(index+1,ordered.size())
			await owner.get_tree().process_frame
			deadline=Time.get_ticks_usec()+8000
	if report.is_valid():report.call(ordered.size(),ordered.size())
	return true

func _collect(path:String,graph:Dictionary,visited:Dictionary,ordered:Array[String])->void:
	if visited.has(path) or ResourceLoader.has_cached(path):return
	visited[path]=true
	for dependency:String in graph.get(path,[]):_collect(dependency,graph,visited,ordered)
	if not path.ends_with(".gd"):ordered.append(path)
