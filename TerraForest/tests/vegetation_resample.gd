# SPDX-License-Identifier: 0BSD
extends SceneTree
class TerrainStub extends Node3D:
	var epoch:=1
	var published_revision:=1
	var pending_edit:=false
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func sample(ecosystem: Node,token: int,height: float) -> void:
	ecosystem._requests[token]={"key":Vector2i.ZERO,"ids":PackedInt64Array([1,2]),"rotations":PackedFloat32Array([0,0]),"scales":PackedFloat32Array([1,1])}
	ecosystem._pending_cells[Vector2i.ZERO]=token
	ecosystem._surface_ready(token,PackedVector3Array([Vector3(10,height+0.2,10),Vector3(30,0.2,10)]),PackedVector3Array([Vector3.UP,Vector3.UP]),1,1)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var vegetation=preload("res://addons/vegetation/vegetation_world.gd").new();root.add_child(vegetation)
	check(vegetation.enable_trunk_collision() and vegetation.initialize()==OK,"native rendering and trunk records ready")
	var terrain:=TerrainStub.new()
	var ecosystem=preload("res://addons/world_ecosystem/world_ecosystem.gd").new()
	ecosystem.terrain=terrain;ecosystem.vegetation=vegetation;ecosystem._wanted[Vector2i.ZERO]=true
	sample(ecosystem,1,0)
	check(vegetation.renderer.roots.size()==2,"initial surface publishes two roots")
	vegetation.renderer.roots[2].time=123.0
	sample(ecosystem,2,5)
	check(is_equal_approx(vegetation.renderer.roots[1].t.origin.y,5),"same stable ID follows changed terrain support")
	check(is_equal_approx(vegetation.trunk_collision.get_instance(1)[7],5),"trunk placement follows changed terrain support")
	check(vegetation.renderer.roots[2].time==123.0 and vegetation.renderer.roots[2].t.origin.y==0,"unchanged neighbor retains its transition state and transform")
	vegetation.renderer.membership_changed=false
	sample(ecosystem,3,5)
	check(not vegetation.renderer.membership_changed,"identical resample does not republish owner")
	sample(ecosystem,4,1)
	check(is_equal_approx(vegetation.renderer.roots[1].t.origin.y,1) and is_equal_approx(vegetation.trunk_collision.get_instance(1)[7],1),"lowered support updates both representations too")
	terrain.published_revision=2;sample(ecosystem,5,9)
	check(ecosystem.stale_results==1 and is_equal_approx(vegetation.renderer.roots[1].t.origin.y,1),"stale support cannot replace the accepted transform")
	ecosystem.free();terrain.free();vegetation.free()
	print("VEGETATION_RESAMPLE failures=",failures);quit(1 if failures else 0)
