# SPDX-License-Identifier: 0BSD
extends SceneTree
class Fixture extends Node3D:
	var camera:Camera3D
	var player:CharacterBody3D
var stage:Fixture
var checks:=0
var failures:=0
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
	return ok
func block(size:Vector3,center:Vector3)->StaticBody3D:
	var body:=StaticBody3D.new();body.position=center
	var shape:=BoxShape3D.new();shape.size=size
	var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider);stage.add_child(body)
	return body
func frames()->void:
	for frame in 3:await physics_frame
func _initialize()->void:run.call_deferred()
func run()->void:
	stage=Fixture.new();root.add_child(stage)
	stage.camera=Camera3D.new();stage.add_child(stage.camera);stage.camera.position=Vector3(0,1.6,8)
	stage.player=CharacterBody3D.new();stage.add_child(stage.player);stage.player.position=Vector3(0,0,8)
	var population=preload("res://addons/characters/runtime/zombie_population.gd").new();population.game=stage
	var host=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(host);host.readiness=func(_bounds:AABB):return true
	var floor_body:=block(Vector3(20,1,20),Vector3(0,-.5,0))
	await frames()
	check(not population._occluded(Vector3.ZERO),"visible room cannot reveal a new resident")
	var wall:=block(Vector3(8,4,.2),Vector3(0,2,4))
	await frames()
	check(population._occluded(Vector3.ZERO),"solid room wall permits hidden resident admission")
	wall.queue_free();await frames()
	check(not population._occluded(Vector3.ZERO),"removed wall immediately prevents hidden admission")
	var low:=block(Vector3(8,.6,.2),Vector3(0,.3,4))
	var high:=block(Vector3(8,2,.2),Vector3(0,2.4,4))
	await frames()
	check(not population._occluded(Vector3.ZERO),"window opening is not treated as an opaque wall")
	low.queue_free();high.queue_free()
	var roof:=block(Vector3(6,.2,6),Vector3(0,2.5,0));await frames()
	var point:=Vector3(0,.002,0)
	check(host.supported_resident_point(point,true)==point,"saved standing resident selects its floor rather than the roof")
	check(host.supported_resident_point(point,false)==point,"sleeping resident retains its authored floor")
	roof.position.y=1.2;await frames()
	check(not host.supported_resident_point(point,true).is_finite() and host.supported_resident_point(point,false).is_finite(),"low ceiling requires the saved compact posture")
	floor_body.queue_free();await frames()
	check(not host.supported_resident_point(point,false).is_finite(),"removed floor cannot admit a floating sleeper")
	stage.free();await process_frame
	await house_clearance()
	print("HOUSE_SLEEPER_VISIBILITY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func house_clearance()->void:
	var homes=preload("res://addons/characters/runtime/house_sleepers.gd")
	for house:String in homes.HOMES:
		for turn in 4:
			stage=Fixture.new();root.add_child(stage)
			var structures=preload("res://addons/structures/structures_world.gd").new();stage.add_child(structures)
			if not check(structures.prepare(),"house collision fixture prepares"):stage.free();continue
			for catalog:String in ["furniture","ladder","storage","window","door","guardrail","fence"]:
				load("res://addons/structures/"+catalog+"_catalog.gd").register(structures)
			var origin:=Vector3i(100,20,100)
			var asset:Resource=homes.Catalog.asset(house)
			var anchor:Dictionary=homes.plan([{"asset":asset,"origin":origin,"rotation":turn}],1703).anchors[0]
			var placement=ClassDB.instantiate("NativePrefabPlacement")
			if not check(placement.place(structures.blocks,asset,origin,turn,structures.model_collections(),[]).get("ok",false),"approved furnished "+house+" places at rotation "+str(turn)):stage.free();continue
			structures.blocks.set_focus(anchor.position);structures.blocks.set_collision_radius(48);structures.blocks.flush_bakes()
			structures.set_model_focus(anchor.position)
			var deadline:=Time.get_ticks_msec()+10000
			var bounds:=AABB(anchor.position-Vector3(2.5,.5,2.5),Vector3(5,5,5))
			while not structures.is_collision_region_ready(bounds) and Time.get_ticks_msec()<deadline:await process_frame
			check(structures.is_collision_region_ready(bounds),"actual house collision covers complete wake envelope")
			var host=preload("res://addons/characters/runtime/zombie_world.gd").new();host.population_enabled=false;host.enabled=true
			host.target=Node3D.new();stage.add_child(host.target);host.target.position=anchor.position+Vector3(0,0,30)
			host.readiness=structures.is_collision_region_ready;stage.add_child(host)
			await frames()
			for pose in [1,2]:
				var actor:CharacterBody3D=host.spawn_at(anchor.position,true,true)
				if not check(actor!=null,"house floor admits pose %d"%pose):continue
				actor.rotation.y=anchor.yaw;actor.set_physics_process(false)
				if check(host.put_to_sleep(actor,pose),"authored posture fits unchanged furnished house"):
					actor.sleeper.wake()
					for step in 120:actor.sleeper.advance_wake(.05)
					check(actor.sleeper.phase=="ready" and not actor.sleeper.blocked,"entire wake path clears "+house+" rotation %d pose %d"%[turn,pose])
				host.clear();await frames()
			stage.free();await frames()
