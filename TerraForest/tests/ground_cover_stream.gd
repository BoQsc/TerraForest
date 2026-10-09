# SPDX-License-Identifier: 0BSD
extends SceneTree
class Terrain extends Node3D:
	signal surface_batch_ready(token,points,normals,epoch,revision)
	signal region_changed(bounds,revision)
	signal reload_started
	var world_ready:=true
	var stopping:=false
	var pending_edit:=false
	var epoch:=1
	var published_revision:=0
	var requests: Array=[]
	func request_surface_batch(points: PackedVector3Array,token: int) -> bool:
		requests.append({"points":points,"token":token});return true
	func reply() -> void:
		var request: Dictionary=requests.pop_front()
		var normals:=PackedVector3Array();normals.resize(request.points.size());normals.fill(Vector3.UP)
		surface_batch_ready.emit(request.token,request.points,normals,epoch,published_revision)
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var terrain:=Terrain.new();root.add_child(terrain)
	var camera:=Camera3D.new();root.add_child(camera);camera.position=Vector3(960,3,960)
	var cover=load("res://addons/world_ecosystem/ground_cover.gd").new()
	cover.terrain=terrain;cover.camera=camera
	var persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	check(cover.prepare(persistence),"removal provider registers with world persistence")
	root.add_child(cover);cover.set_process(false)
	check(cover.batches.size()==3,"three native species render collections initialized")
	for i in range(49):
		cover._process(0.0)
		check(terrain.requests.size()==1,"one outstanding support batch %d"%i)
		terrain.reply()
	check(cover.resident.size()==49 and cover.rejected_batches==0,"49 owners publish without rejection")
	var count:=0
	for batch in cover.batches:
		count+=batch.get_ids().size()
		check(not batch.collision_stats().enabled and batch.collision_stats().resident_bodies==0,"ground cover creates no physics bodies")
	check(count==3136,"bounded 3136 individual candidates resident")
	var key:=Vector2i(30,30)
	var row: Dictionary=cover.resident[key][2]
	var removed_id: int=row.ids[0]
	check(cover.removed.mark(removed_id),"individual removal persists separately from rendering")
	cover._exclusion_changed(AABB(Vector3(961,-1,961),Vector3(1,2,1)))
	check(cover._dirty.size()==1,"small interior disturbance invalidates one owner")
	cover._process(0.0);terrain.reply()
	check(not cover.batches[2].get_ids().has(removed_id) and cover.resident.size()==49,"individual removal preserves neighbour owners")
	camera.position=Vector3(1600,3,1600);cover._process(0.0)
	check(cover.resident.is_empty() and terrain.requests.size()==1,"teleport retires old owners and submits one destination batch")
	camera.position=Vector3(960,3,960);cover._process(0.0)
	check(terrain.requests.size()==1,"teleport does not multiply outstanding jobs")
	terrain.reply()
	check(cover.resident.is_empty(),"obsolete destination reply does not publish")
	cover._process(0.0);terrain.reply()
	check(cover.resident.size()==1 and not cover.batches[2].get_ids().has(removed_id),"return regeneration retains individual removal")
	cover.reset()
	check(cover.resident.is_empty() and cover.batches[0].get_ids().is_empty() and cover.batches[1].get_ids().is_empty() and cover.batches[2].get_ids().is_empty(),"reset releases generated records")
	cover.free();terrain.free();camera.free()
	print("GROUND_COVER_STREAM ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
