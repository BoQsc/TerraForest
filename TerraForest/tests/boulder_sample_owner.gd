# SPDX-License-Identifier: 0BSD
extends SceneTree
class Cover extends Node3D:
	var seed:=1703
	var seed_source:Callable
	var camera:Camera3D
class Terrain extends Node3D:
	var epoch:=1
	var published_revision:=1
	var pending_edit:=false
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var cover:=Cover.new();root.add_child(cover)
	cover.camera=Camera3D.new();cover.add_child(cover.camera)
	cover.seed_source=func()->int:return 42
	var terrain:=Terrain.new()
	var coordinator=load("res://addons/world_ecosystem/boulder_horizon.gd").new()
	coordinator.cover=cover;coordinator.terrain=terrain
	coordinator.native=ClassDB.instantiate("NativeGroundCover")
	var owner:=Vector2i(15,15)
	var request:Dictionary=coordinator.candidates_for_page(owner)
	check(request.seed==42 and cover.seed==42 and request.points==coordinator.native.boulder_candidates(owner,42).points,"companion request reads restored seed before local grass processes")
	var points:PackedVector3Array=request.points
	var normals:=PackedVector3Array();normals.resize(points.size());normals.fill(Vector3.UP)
	coordinator.accept_surface_page(request,points,normals,1,1)
	check(coordinator._samples.has(owner) and coordinator._reconcile.has(owner),"matching seed epoch and revision admit samples")
	cover.seed_source=func()->int:return 73
	var current:Dictionary=coordinator.candidates_for_page(owner)
	check(current.seed==73 and coordinator._samples.is_empty(),"seed change clears previous derived ownership")
	coordinator.accept_surface_page(request,points,normals,1,1)
	check(coordinator._samples.is_empty() and coordinator._resample.has(owner),"old-seed completion cannot publish into new world")
	coordinator.free();terrain.free();cover.free()
	print("BOULDER_SAMPLE_OWNER failures=",failures)
	quit(1 if failures else 0)
