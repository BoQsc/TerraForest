# SPDX-License-Identifier: 0BSD
extends RefCounted
var retained:Array[Resource]=[]
var cancelled:=false
var slowest:Dictionary={}
const PREFETCH_LIMIT:=4
var peak_pending:=0

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
	var pending:Dictionary={}
	var deadline:=Time.get_ticks_usec()+8000
	for index in ordered.size():
		if cancelled or not _prefetch(ordered,index,pending):
			await _drain(owner,pending);return false
		var started:=Time.get_ticks_usec()
		var resource:Resource
		var target:=ordered[index]
		if pending.has(target):
			started=pending[target]
			while ResourceLoader.load_threaded_get_status(target)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				await owner.get_tree().process_frame
				if cancelled:await _drain(owner,pending);return false
			if ResourceLoader.load_threaded_get_status(target)!=ResourceLoader.THREAD_LOAD_LOADED:
				await _drain(owner,pending);return false
			resource=ResourceLoader.load_threaded_get(target)
			pending.erase(target)
		else:resource=load(target)
		if resource==null:await _drain(owner,pending);return false
		var elapsed:=(Time.get_ticks_usec()-started)/1000.0
		if elapsed>float(slowest.get("ms",0)):slowest={"path":target,"ms":elapsed}
		retained.append(resource)
		if Time.get_ticks_usec()>=deadline:
			if report.is_valid():report.call(index+1,ordered.size())
			await owner.get_tree().process_frame
			deadline=Time.get_ticks_usec()+8000
	if report.is_valid():report.call(ordered.size(),ordered.size())
	return true

func _prefetch(ordered:Array[String],index:int,pending:Dictionary)->bool:
	# Keep imported resources in flight while the preceding resource is consumed.
	# Script compilation remains on the main thread after its indexed dependencies.
	for cursor in range(index,ordered.size()):
		if pending.size()>=PREFETCH_LIMIT:break
		var target:=ordered[cursor]
		if target.ends_with(".gd"):break
		if pending.has(target) or ResourceLoader.has_cached(target):continue
		if ResourceLoader.load_threaded_request(target)!=OK:return false
		pending[target]=Time.get_ticks_usec()
	peak_pending=maxi(peak_pending,pending.size())
	return true

func _drain(owner:Node,pending:Dictionary)->void:
	# Godot requests have no cancel operation. Consume every submitted handle
	# before dropping the preparation job, including cancellation/failure paths.
	for target:String in pending:
		while ResourceLoader.load_threaded_get_status(target)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await owner.get_tree().process_frame
		var resource:Resource=ResourceLoader.load_threaded_get(target)
		if resource!=null:retained.append(resource)
	pending.clear()

func _collect(path:String,graph:Dictionary,visited:Dictionary,ordered:Array[String])->void:
	if visited.has(path) or ResourceLoader.has_cached(path):return
	visited[path]=true
	for dependency:String in graph.get(path,[]):_collect(dependency,graph,visited,ordered)
	if not path.ends_with(".gd"):ordered.append(path)
