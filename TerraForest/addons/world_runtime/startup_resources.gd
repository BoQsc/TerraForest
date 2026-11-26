# SPDX-License-Identifier: 0BSD
extends RefCounted
var retained:Array[Resource]=[]
var cancelled:=false
var slowest:Dictionary={}
const PREFETCH_LIMIT:=4
var peak_pending:=0
var independent_queue:Array[String]=[]
var independent_pending:Dictionary={}
var independent_cursor:=0
var independent_started:=0
var independent_completed:=0
var independent_ok:=true

static func independent_asset(path:String)->bool:
	# Authored presentation assets only. Planner prefab factories and their
	# dynamic structure/exploration loads keep sole ownership of their resources.
	var extension:=path.get_extension().to_lower()
	if path.begins_with("res://addons/player_runtime/art/"):
		return extension in ["res","png","svg","trtex"]
	if path.begins_with("res://addons/audio_runtime/packs/"):
		return extension in ["wav","ogg","mp3"]
	return path=="res://addons/volumetric_water/textures/water_ripples_normal.png" or path=="res://addons/world_ecosystem/art/boulder_granite_v1.png"

func begin_independent(path:String)->bool:
	var decoded=JSON.parse_string(FileAccess.get_file_as_string("res://addons/world_runtime/startup_index.json"))
	if not decoded is Dictionary or not independent_pending.is_empty():return false
	var ordered:Array[String]=[];var visited:Dictionary={}
	_collect(path,decoded,visited,ordered)
	independent_queue.clear();independent_cursor=0;independent_started=0;independent_completed=0;independent_ok=true
	for target:String in ordered:
		if independent_asset(target):independent_queue.append(target)
	return advance_independent()

func advance_independent()->bool:
	if cancelled or not independent_ok:return false
	for target:String in independent_pending.keys():
		var status:=ResourceLoader.load_threaded_get_status(target)
		if status==ResourceLoader.THREAD_LOAD_IN_PROGRESS:continue
		if status!=ResourceLoader.THREAD_LOAD_LOADED:independent_ok=false;return false
		var resource:Resource=ResourceLoader.load_threaded_get(target)
		independent_pending.erase(target)
		if resource==null:independent_ok=false;return false
		retained.append(resource);independent_completed+=1
	while independent_cursor<independent_queue.size() and independent_pending.size()<PREFETCH_LIMIT:
		var target:=independent_queue[independent_cursor];independent_cursor+=1
		if ResourceLoader.has_cached(target):continue
		if ResourceLoader.load_threaded_request(target)!=OK:independent_ok=false;return false
		independent_pending[target]=Time.get_ticks_usec();independent_started+=1
	peak_pending=maxi(peak_pending,independent_pending.size())
	return true

func finish_independent(owner:Node)->bool:
	# Unsubmitted assets are left for ordinary ordered prepare(). Every submitted
	# handle must be consumed, including when planning fails or is cancelled.
	var count:=independent_pending.size()
	var drained:bool=await _drain(owner,independent_pending)
	independent_completed+=count
	independent_queue.clear()
	return drained and independent_ok and not cancelled

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

func _drain(owner:Node,pending:Dictionary)->bool:
	# Godot requests have no cancel operation. Consume every submitted handle
	# before dropping the preparation job, including cancellation/failure paths.
	var valid:=true
	for target:String in pending:
		while ResourceLoader.load_threaded_get_status(target)==ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await owner.get_tree().process_frame
		var resource:Resource=ResourceLoader.load_threaded_get(target)
		if resource!=null:retained.append(resource)
		else:valid=false
	pending.clear()
	return valid

func _collect(path:String,graph:Dictionary,visited:Dictionary,ordered:Array[String])->void:
	if visited.has(path) or ResourceLoader.has_cached(path):return
	visited[path]=true
	for dependency:String in graph.get(path,[]):_collect(dependency,graph,visited,ordered)
	if not path.ends_with(".gd"):ordered.append(path)
