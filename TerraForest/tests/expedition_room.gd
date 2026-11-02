# SPDX-License-Identifier: 0BSD
extends "res://tests/house_sleeper_visibility.gd"
const Spawn=preload("res://addons/world_runtime/introduction_spawn.gd")
const Homes=preload("res://addons/characters/runtime/house_sleepers.gd")

func run()->void:
	var planned:Dictionary=preload("res://addons/world_runtime/world_generation_plan.gd").build(1703,29,true,true,"user://generation_plans",preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS)
	var room:Dictionary=Spawn.select(planned.get("sites",[]))
	check(planned.get("ok",false) and room.ok,"default expedition has an approved upstairs house near the trader")
	if room.ok:print("INTRODUCTION_ROOM ",room.position," trader_distance=",room.distance," origin=",room.lot.origin," rotation=",room.lot.rotation)
	for building:String in ["house_c1","church_c1"]:
		for turn in 4:
			stage=Fixture.new();root.add_child(stage)
			stage.player=CharacterBody3D.new();stage.add_child(stage.player)
			var structures=preload("res://addons/structures/structures_world.gd").new();stage.add_child(structures)
			if not check(structures.prepare(),"collision fixture prepares"):stage.free();continue
			for catalog:String in ["furniture","ladder","storage","window","door","guardrail","fence"]:load("res://addons/structures/"+catalog+"_catalog.gd").register(structures)
			var lot:Dictionary={"asset":Homes.Catalog.asset(building),"origin":Vector3i(100,20,100),"rotation":turn}
			var placement=ClassDB.instantiate("NativePrefabPlacement")
			if not check(placement.place(structures.blocks,lot.asset,lot.origin,turn,structures.model_collections(),[]).get("ok",false),"exact approved "+building+" places at rotation "+str(turn)):stage.free();continue
			var focus:=Spawn.point(lot,Vector3(6.5,5,18) if building=="church_c1" else Spawn.LOCAL)
			structures.blocks.set_focus(focus);structures.blocks.set_collision_radius(64);structures.blocks.flush_bakes();structures.set_model_focus(focus)
			var bounds:=AABB(focus-Vector3(25,10,25),Vector3(50,35,50))
			var deadline:=Time.get_ticks_msec()+15000
			while not structures.is_collision_region_ready(bounds) and Time.get_ticks_msec()<deadline:await process_frame
			await frames()
			if building=="house_c1":
				check(Spawn.clear(stage,Spawn.point(lot,Spawn.LOCAL)),"second-floor spawn is supported with standing capsule clearance at rotation "+str(turn))
				await exit_house(lot,structures)
			else:
				var anchors:Array=Homes.plan([lot],1703).anchors
				check(anchors.size()==10,"church keeps all ten authored sleepers")
				var host=preload("res://addons/characters/runtime/zombie_world.gd").new();host.population_enabled=false;host.enabled=true
				host.target=Node3D.new();stage.add_child(host.target);host.target.position=focus+Vector3(0,0,80);host.readiness=structures.is_collision_region_ready;stage.add_child(host)
				for anchor:Dictionary in anchors:
					var actor:CharacterBody3D=host.spawn_at(anchor.position,true,true)
					if not check(actor!=null,"church floor admits sleeper "+str(anchor.position)):continue
					actor.rotation.y=anchor.yaw;actor.set_physics_process(false)
					if check(host.put_to_sleep(actor,anchor.pose),"church sleep pose clears unchanged structures"):
						actor.sleeper.wake()
						for step in 120:actor.sleeper.advance_wake(.05)
						check(actor.sleeper.phase=="ready" and not actor.sleeper.blocked,"church complete wake envelope clears at "+str(anchor.position))
					host.clear();await frames()
			stage.free();await frames()
	print("EXPEDITION_ROOM checks=",checks," failures=",failures);quit(1 if failures else 0)

func exit_house(lot:Dictionary,structures:Node)->void:
	var hinges:RefCounted=ClassDB.instantiate("NativeHingedDoors")
	var doors:Node3D=structures.model("architecture/wooden_door/v1")
	for identity in doors.get_ids():hinges.toggle(doors,identity,AABB())
	var player:=stage.player;player.collision_layer=8;player.collision_mask=7;player.floor_snap_length=.35;player.floor_max_angle=deg_to_rad(48);player.floor_constant_speed=true;player.safe_margin=.004
	var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8
	var shape:=CollisionShape3D.new();shape.shape=capsule;shape.position.y=.9;player.add_child(shape)
	player.position=Spawn.point(lot,Spawn.LOCAL)
	var motor:RefCounted=ClassDB.instantiate("NativePlayerMovement")
	for local:Vector3 in Spawn.EXIT.slice(1):
		var target:=Spawn.point(lot,local)
		for tick in 360:
			await physics_frame
			var offset:=target-player.position;offset.y=0
			if offset.length()<.16:break
			player.velocity=motor.walking_velocity(offset.normalized(),player.velocity,1.0/60,false,player.is_on_floor(),false)
			motor.move_grounded(player,1.0/60)
		if not check(Vector2(player.position.x,player.position.z).distance_to(Vector2(target.x,target.z))<.2 and absf(player.position.y-target.y)<.18,"physical upstairs-to-door route "+str(local)+" rotation "+str(lot.rotation)+" end "+str(player.position)):break
