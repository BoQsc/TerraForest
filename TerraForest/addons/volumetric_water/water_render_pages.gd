# SPDX-License-Identifier: 0BSD
extends Node3D
## Draw membership is independent of the authoritative 4 m water owners.
## Edits immediately expose the original, current meshes; optional consolidation
## never delays query/terrain publication or reads geometry back from the GPU.
const CACHE_BYTES:=32*1024*1024
const PAGE_BYTES:=512*1024
const JOB_BYTES:=4*1024*1024
var enabled:=true:
	set(value):
		if enabled==value:return
		enabled=value
		if not enabled:clear()
var draw_pages:=true
var material:Material
var pages:Dictionary={}
var dirty:Dictionary={}
var retained_bytes:=0
var task:=-1
var job:RefCounted
var tickets:Array[Dictionary]=[]
var published:=0
var stale:=0
var fallback:=0
var worker_us:=0

static func page_key(owner:Vector3i)->Vector3i:
	return Vector3i(floori(owner.x/4.0),floori(owner.y/4.0),floori(owner.z/4.0))

func _unbatch(page:Dictionary)->void:
	page.ready=false
	if page.node!=null:page.node.hide()
	for member:Dictionary in page.members.values():
		var node:MeshInstance3D=member.node.get_ref()
		if is_instance_valid(node) and not node.is_queued_for_deletion():node.show()

func set_draw_pages(value:bool)->void:
	draw_pages=value
	for page:Dictionary in pages.values():
		if not page.get("ready",false):continue
		page.node.visible=value
		for member:Dictionary in page.members.values():
			var node:MeshInstance3D=member.node.get_ref()
			if is_instance_valid(node):node.visible=not value

func commit(changes:Dictionary)->void:
	if not enabled:return
	# This runs in the same main-thread call as the water/query commit. Remove
	# obsolete membership before restoring visibility, including a deleted owner.
	var touched:Dictionary={}
	for coordinate:Vector3i in changes:
		var key:=page_key(coordinate)
		if not pages.has(key):pages[key]={"members":{},"bytes":0,"revision":0,"node":null}
		var page:Dictionary=pages[key];var next:Dictionary=changes[coordinate]
		if page.members.has(coordinate):
			var old:Dictionary=page.members[coordinate]
			retained_bytes-=old.bytes;page.bytes-=old.bytes;page.members.erase(coordinate)
		if next.get("node")!=null:
			next.node.show()
			var arrays:Array=next.arrays
			var size:int=arrays[Mesh.ARRAY_VERTEX].size()*48+arrays[Mesh.ARRAY_INDEX].size()*4
			if size>0 and retained_bytes+size<=CACHE_BYTES and size<=PAGE_BYTES:
				page.members[coordinate]={"node":weakref(next.node),"arrays":arrays,"bytes":size}
				retained_bytes+=size;page.bytes+=size
			else:fallback+=1
		touched[key]=true
	for key:Vector3i in touched:
		var page:Dictionary=pages[key];page.revision+=1;_unbatch(page)
		if page.members.is_empty():
			if page.node!=null:page.node.queue_free()
			pages.erase(key);dirty.erase(key)
		else:dirty[key]=true

func step()->void:
	if task>=0:
		if not WorkerThreadPool.is_task_completed(task):return
		WorkerThreadPool.wait_for_task_completion(task);task=-1
		var meshes:Array=job.result();worker_us+=int(job.statistics().worker_us)
		for index in tickets.size():
			var ticket:Dictionary=tickets[index]
			if not pages.has(ticket.key) or pages[ticket.key].revision!=ticket.revision:stale+=1;continue
			var page:Dictionary=pages[ticket.key]
			if index>=meshes.size() or meshes[index]==null:fallback+=1;continue
			var valid:=true
			for member:Dictionary in page.members.values():
				var source:MeshInstance3D=member.node.get_ref()
				if not is_instance_valid(source) or source.is_queued_for_deletion():valid=false;break
			if not valid:fallback+=1;continue
			if page.node==null:
				var node:=MeshInstance3D.new();node.name="WaterRenderPage"
				node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				node.material_override=material;node.position=Vector3(ticket.key)*16
				add_child(node);page.node=node
			page.node.mesh=meshes[index]
			for member:Dictionary in page.members.values():member.node.get_ref().visible=not draw_pages
			page.ready=true;page.node.visible=draw_pages;published+=1
		job=null;tickets.clear()
	if not enabled or dirty.is_empty():return
	var input:Array=[];var bytes:=0
	for key:Vector3i in dirty.keys():
		var page:Dictionary=pages[key]
		if page.members.size()<2 or page.bytes>PAGE_BYTES:dirty.erase(key);continue
		if input.size()>=16 or bytes+page.bytes>JOB_BYTES:break
		var members:Array=[]
		for coordinate:Vector3i in page.members:
			members.append({"arrays":page.members[coordinate].arrays,"offset":Vector3(coordinate*4-key*16)})
		input.append(members);bytes+=page.bytes
		tickets.append({"key":key,"revision":page.revision});dirty.erase(key)
	if input.is_empty():return
	job=ClassDB.instantiate("NativeWaterRenderPages")
	if not job.configure(input):fallback+=tickets.size();tickets.clear();job=null;return
	task=WorkerThreadPool.add_task(job.prepare,false,"Consolidate water render pages")
	if task<0:fallback+=tickets.size();tickets.clear();job=null

func clear()->void:
	# The owned job retains only immutable packets. Invalidate its tickets without
	# waiting during a reload; its result is reaped by step or final teardown.
	for page:Dictionary in pages.values():
		_unbatch(page)
		if page.node!=null:page.node.queue_free()
	pages.clear();dirty.clear();retained_bytes=0
	for ticket:Dictionary in tickets:ticket.revision=-1

func statistics()->Dictionary:
	var active:=0;var owners:=0
	for page:Dictionary in pages.values():
		owners+=page.members.size()
		if page.node!=null and page.node.visible:active+=1
	return {"enabled":enabled,"draw_pages":draw_pages,"pages":pages.size(),"active":active,"owners":owners,"retained_bytes":retained_bytes,"cache_limit":CACHE_BYTES,"pending":dirty.size(),"worker_pending":task>=0,"published":published,"stale":stale,"fallback":fallback,"worker_us":worker_us}

func _exit_tree()->void:
	if task>=0:WorkerThreadPool.wait_for_task_completion(task);task=-1
	job=null
