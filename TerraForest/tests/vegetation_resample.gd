# SPDX-License-Identifier: 0BSD
extends SceneTree
class TerrainStub extends Node3D:
	var epoch:=1
	var published_revision:=1
	var pending_edit:=false
	var world_ready:=true
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
	terrain.published_revision=1
	ecosystem._resample[Vector2i.ZERO]=true
	ecosystem._requests[6]={"key":Vector2i.ZERO,"ids":PackedInt64Array([1,2]),"rotations":PackedFloat32Array([0,0]),"scales":PackedFloat32Array([1,NAN])}
	ecosystem._pending_cells[Vector2i.ZERO]=6
	ecosystem._surface_ready(6,PackedVector3Array([Vector3(10,20,10),Vector3(30,20,10)]),PackedVector3Array([Vector3.UP,Vector3.UP]),1,1)
	check(ecosystem.rejected_batches==1 and ecosystem._resample.has(Vector2i.ZERO),"native rejection keeps owner scheduled for resampling")
	check(not ecosystem._pending_cells.has(Vector2i.ZERO) and not ecosystem._requests.has(6),"rejected completion releases request admission for retry")
	check(is_equal_approx(vegetation.renderer.roots[1].t.origin.y,1) and is_equal_approx(vegetation.trunk_collision.get_instance(1)[7],1) and vegetation.renderer.roots[2].time==123.0,"malformed batch preserves both live roots and collision support")
	sample(ecosystem,7,2)
	check(not ecosystem._resample.has(Vector2i.ZERO) and is_equal_approx(vegetation.renderer.roots[1].t.origin.y,2),"valid retry replaces retained support and clears resampling")
	ecosystem._resample[Vector2i.ZERO]=true
	ecosystem._requests[8]={"key":Vector2i.ZERO,"ids":PackedInt64Array([1,2]),"rotations":PackedFloat32Array([0,0]),"scales":PackedFloat32Array([1,1])}
	ecosystem._pending_cells[Vector2i.ZERO]=8
	ecosystem._surface_ready(999,PackedVector3Array(),PackedVector3Array(),1,1)
	check(ecosystem._pending_cells[Vector2i.ZERO]==8 and ecosystem._requests.has(8),"unknown completion cannot release a live owner's request")
	terrain.pending_edit=true
	ecosystem._surface_ready(8,PackedVector3Array([Vector3(10,90,10),Vector3(30,90,10)]),PackedVector3Array([Vector3.UP,Vector3.UP]),1,1)
	check(ecosystem._resample.has(Vector2i.ZERO) and is_equal_approx(vegetation.renderer.roots[1].t.origin.y,2),"completion during terrain edit retains old support and retry intent")
	terrain.pending_edit=false
	sample(ecosystem,9,3)
	check(not ecosystem._resample.has(Vector2i.ZERO) and is_equal_approx(vegetation.renderer.roots[1].t.origin.y,3),"post-edit retry publishes updated support")
	var camera:=Camera3D.new();root.add_child(camera);ecosystem.camera=camera
	ecosystem.density=0;ecosystem._last_cell=Vector2i.ZERO;ecosystem._scan_timer=1
	ecosystem._resample[Vector2i.ZERO]=true;ecosystem._step(0)
	check(vegetation.renderer.roots.is_empty() and vegetation.trunk_collision.get_ids().is_empty(),"zero-candidate resample retires existing renderer and trunk records")
	check(ecosystem._samples[Vector2i.ZERO].ids.is_empty() and not ecosystem._resample.has(Vector2i.ZERO),"empty owner replaces stale sample cache and completes resampling")
	ecosystem._publish_samples(Vector2i.ZERO)
	check(vegetation.renderer.roots.is_empty(),"later exclusion reconciliation cannot resurrect retired candidates")
	ecosystem._reconcile.clear()
	ecosystem._structures_changed();ecosystem._structure_region_changed(AABB(Vector3.ZERO,Vector3(64,32,64)));ecosystem._water_changed(AABB(Vector3.ZERO,Vector3(64,32,64)))
	check(ecosystem._reconcile.is_empty(),"empty candidate caches do not schedule pointless structure or water reconciliation")
	ecosystem.free();camera.free();terrain.free();vegetation.free()
	print("VEGETATION_RESAMPLE failures=",failures);quit(1 if failures else 0)
