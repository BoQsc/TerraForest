# SPDX-License-Identifier: 0BSD
extends SceneTree
const Ecosystem=preload("res://addons/world_ecosystem/world_ecosystem.gd")
class CountedEcosystem extends Ecosystem:
	var refreshes:=0
	var publications:=0
	func _refresh(center:Vector2i)->void:
		refreshes+=1
		super._refresh(center)
	func _publish_samples(key:Vector2i)->void:
		publications+=1
		super._publish_samples(key)
class Terrain extends Node3D:
	var backend:={"world_generator":0}
	var world_ready:=true
	var pending_edit:=false
	func request_surface_batch(_points, _token) -> bool: return false
class Forest extends Node3D:
	var ready_to_render:=true
	var removed: Array=[]
	func upsert_chunk(_owner: String,ids: PackedInt64Array,poses: Array[Transform3D]) -> bool:
		return ids.is_empty() and poses.is_empty()
	func remove_chunk(owner: String) -> void: removed.append(owner)
var failures:=0
func check(value: bool,label: String) -> void:
	print(("PASS " if value else "FAIL ")+label)
	if not value: failures+=1
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world=CountedEcosystem.new()
	var terrain=Terrain.new()
	var forest=Forest.new()
	var camera:=Camera3D.new()
	root.add_child(camera)
	world.terrain=terrain;world.vegetation=forest;world.camera=camera
	world.max_resident_cells=169
	for z in range(13):
		for x in range(13):
			var key:=Vector2i(x,z)
			world.resident[key]=true
			world._samples[key]={"published":true}
	world._refresh(Vector2i(25,25))
	check(forest.removed.size()==169 and world.resident.is_empty(),"departed roots do not remain in renderer LOD selection")
	world.resident.clear();world._samples.clear();world._wanted.clear()
	camera.position=Vector3(1600,100,1600)
	world._step(1.0/60)
	check(world.resident.size()==1,"barren arrival generates one empty candidate owner per frame")
	world._step(1.0/60)
	check(world.resident.size()==2,"barren generation makes bounded progress on the next frame")
	world.max_resident_cells=2
	world._step(1.0/60)
	check(world.resident.size()==2,"candidate admission preserves residency cap")
	var refreshes:int=world.refreshes
	for frame in 120:world._step(1.0/60)
	check(world.refreshes==refreshes,"settled forest does not rebuild identical residency every half second")
	var owner:Vector2i=world.resident.keys()[0]
	var publications:int=world.publications
	world._reconcile[owner]=true
	world._step(1.0/60)
	check(world.publications==publications+1 and world._reconcile.is_empty(),"settled fast path still reconciles changed vegetation")
	world._resample[owner]=true
	world._step(1.0/60)
	check(not world._resample.has(owner),"settled fast path still resamples invalidated terrain support")
	world.stream_radius=128
	world._step(1.0/60)
	check(world.refreshes==refreshes+1,"radius changes refresh residency without camera movement")
	world.reset();world._step(1.0/60)
	check(world.refreshes==refreshes+2 and world.resident.size()==1,"reload invalidates settled residency")
	world.resident.clear()
	world.free();terrain.free();forest.free();camera.free()
	print("ECOSYSTEM_STREAM_BUDGET failures=",failures)
	quit(1 if failures else 0)
