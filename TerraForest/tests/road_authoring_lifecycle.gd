# SPDX-License-Identifier: 0BSD
extends SceneTree
class TerrainStub extends Node:
	var epoch:=1
	var density_revision:=1
	var pending_edit:=false
	var stopping:=false
	var edit_ticket:=0
	var last_edit_outcome: Dictionary={}
	var submissions:=0
	func request_surface_batch(_points: PackedVector3Array,_token: int) -> bool:return true
	func construct_curved_road_bed(_a: Vector3,_b: Vector3,_c: PackedFloat64Array,_i: int,_w: float,_d: float,_h: float) -> bool:
		submissions+=1;edit_ticket+=1;pending_edit=true;return true
class WorldStub extends Node:
	var terrain:=TerrainStub.new()
	var road_palette=preload("res://addons/volumetric_terrain/road_palette.gd").new()
	var road_preview=preload("res://addons/volumetric_terrain/road_preview.gd").new()
	var world_vehicle: Dictionary={"driving":false}
	var loading_active:=false
	var shutdown_requested:=false
	func _road_protection_error(_bounds: AABB) -> String:return ""
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var world:=WorldStub.new();root.add_child(world)
	world.add_child(world.terrain);world.add_child(world.road_palette);world.add_child(world.road_preview)
	var job=preload("res://addons/volumetric_terrain/road_authoring.gd").new();job.world=world;world.add_child(job);job.set_process(false)
	var p=world.road_palette
	p.width.value=4;p.depth.value=4;p.clearance.value=16
	p.mark(true,Vector3(100,50,100));p.mark(false,Vector3(132,50,100))
	job.prepare();job._process(0)
	var old_token: int=job.token
	var samples: PackedVector3Array=job.points.duplicate()
	job.cancel();job.receive(old_token,samples,PackedVector3Array(),1,1)
	check(job.phase.is_empty() and job.worker==null,"late samples after cancellation cannot start fitting")
	job.prepare();job._process(0)
	job.receive(old_token,samples,PackedVector3Array(),1,1)
	check(job.phase=="sampling" and job.worker==null,"previous request token cannot satisfy new request")
	world.terrain.epoch+=1;job.receive(job.token,samples,PackedVector3Array(),1,1)
	check(job.phase.is_empty(),"reload epoch rejects old sampling result")
	job.prepare();job._process(0);job.receive(job.token,job.points.duplicate(),PackedVector3Array(),world.terrain.epoch,1)
	check(job.phase=="fitting" and job.worker!=null,"actual native fit starts in worker")
	job.cancel()
	var deadline:=Time.get_ticks_msec()+5000
	while job.worker!=null and Time.get_ticks_msec()<deadline:
		job._process(0);await process_frame
	check(job.phase.is_empty() and job.worker==null and job.solver==null,"cancelled fit is reaped without publishing or retaining worker")
	job.prepare();job._process(0);job.receive(job.token,job.points.duplicate(),PackedVector3Array(),world.terrain.epoch,1)
	deadline=Time.get_ticks_msec()+5000
	while job.phase=="fitting" and Time.get_ticks_msec()<deadline:job._process(0);await process_frame
	check(job.phase=="ready","new preview succeeds after cancelled fit")
	job.start_build();job._process(0)
	check(world.terrain.submissions==1,"first section submitted once")
	world.terrain.epoch+=1;job._process(0)
	check(job.phase.is_empty(),"reload cancels route while section is pending")
	world.terrain.pending_edit=false
	world.terrain.last_edit_outcome={"ticket":world.terrain.edit_ticket,"epoch":world.terrain.epoch-1,"status":"published"}
	job._process(0)
	check(world.terrain.submissions==1 and p.prepared_street.is_empty(),"late section completion cannot submit next section or register route")
	job.prepare();job._process(0);job.receive(job.token,job.points.duplicate(),PackedVector3Array(),world.terrain.epoch,1)
	world.free()
	check(not is_instance_valid(job),"teardown joins outstanding native fit")
	print("ROAD_AUTHORING_LIFECYCLE failures=",failures);quit(1 if failures else 0)
