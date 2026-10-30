# SPDX-License-Identifier: 0BSD
extends SceneTree

class Terrain extends Node3D:
	var backend:={"world_generator":29}
	var world_ready:=true
	var pending_edit:=false
	var epoch:=1
	var published_revision:=1
	var pending:Dictionary={}
	func request_surface_page(points:PackedVector3Array,owner:Vector2i,token:int)->bool:
		pending[token]={"points":points,"owner":owner}
		return true

class Forest extends Node3D:
	var ready_to_render:=true
	var chunks:Dictionary={}
	var removals:=0
	func upsert_chunk(owner:String,ids:PackedInt64Array,poses:Array[Transform3D])->bool:
		chunks[owner]={"ids":ids,"poses":poses}
		return true
	func remove_chunk(owner:String)->void:
		chunks.erase(owner);removals+=1

var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	var ecosystem=load("res://addons/world_ecosystem/world_ecosystem.gd").new()
	var terrain:=Terrain.new();var forest:=Forest.new();var camera:=Camera3D.new()
	root.add_child(camera);camera.position=Vector3(1000,100,1000)
	ecosystem.terrain=terrain;ecosystem.vegetation=forest;ecosystem.camera=camera;ecosystem.world_coverage=true
	var scatter:RefCounted=ecosystem._scatter()
	for center:Vector2i in [Vector2i(15,15),Vector2i.ZERO,Vector2i(31,31),Vector2i(-2147483648,2147483647)]:
		var cells:Array=scatter.world_cells(center)
		var unique:Dictionary={}
		for cell:Vector2i in cells:unique[cell]=true
		var clamped:=Vector2i(clampi(center.x,0,31),clampi(center.y,0,31))
		check(cells.size()==1024 and unique.size()==1024 and cells[0]==clamped,"complete bounded nearest-first native owner list "+str(center))
	var peak_requests:=0
	var peak_admission:=0
	var frames:=0
	while not ecosystem.coverage_status().ready and frames<1500:
		var before:int=ecosystem.resident.size()
		ecosystem._step(1.0/60.0)
		peak_admission=maxi(peak_admission,ecosystem.resident.size()-before+terrain.pending.size())
		peak_requests=maxi(peak_requests,ecosystem._requests.size())
		for token:int in terrain.pending:
			var points:PackedVector3Array=terrain.pending[token].points.duplicate()
			var normals:=PackedVector3Array();normals.resize(points.size());normals.fill(Vector3.UP)
			for index in points.size():points[index].y=10
			ecosystem._surface_ready(token,points,normals,1,1)
		terrain.pending.clear();frames+=1
	check(ecosystem.coverage_status().ready and ecosystem.resident.size()==1024,"all world owners published without visiting them")
	check(peak_requests<=2 and peak_admission<=8,"bounded two surface jobs and eight admitted owners per frame")
	var identities:=0
	var exact:=true
	for key:Vector2i in ecosystem.resident:
		var expected:Dictionary=ecosystem._candidates(key)
		var actual:Dictionary=forest.chunks[ecosystem._owner(key)]
		exact=exact and actual.ids==expected.ids
		identities+=actual.ids.size()
	check(exact and identities<=36864,"canonical candidate identities preserved across entire world")
	var before:Dictionary=forest.chunks.duplicate(true)
	for position:Vector3 in [Vector3(10,80,10),Vector3(1990,90,1990),Vector3(10,80,1990)]:
		camera.position=position;ecosystem._step(1.0/60.0)
	check(before==forest.chunks and forest.removals==0 and terrain.pending.is_empty(),"travel retains all accepted identities without resampling or despawning")
	var owner:Vector2i=ecosystem.resident.keys()[0]
	ecosystem._resample[owner]=true;ecosystem._step(0)
	check(not ecosystem.coverage_status().ready,"pending owner replacement cannot report coverage ready")
	for token:int in terrain.pending:
		var points:PackedVector3Array=terrain.pending[token].points
		ecosystem._surface_ready(token,points,points,2,1)
	check(before==forest.chunks and ecosystem._resample.has(owner),"stale epoch keeps previous far representation and retries")
	ecosystem.reset()
	check(forest.chunks.is_empty() and ecosystem.resident.is_empty() and not ecosystem.coverage_status().ready,"reload clears derived forest ownership")
	ecosystem.free();terrain.free();forest.free();camera.free()
	print("FOREST_WORLD_COVERAGE failures=",failures," owners=1024 trees=",identities," frames=",frames)
	quit(1 if failures else 0)
