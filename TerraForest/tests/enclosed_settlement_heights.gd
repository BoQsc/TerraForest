# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"saved world ready"):await finish();return
	game.set_physics_process(false);game._clear_motion()
	print("HEIGHT_PROFILE generator=",game.terrain.backend.world_generator," seed=",game.terrain.backend.world_seed," transform=",game.terrain.global_transform)
	var probes: Array=[]
	for id in game.doors.collection.get_ids():
		var p: PackedFloat32Array=game.doors.collection.get_instance(id)
		probes.append({"name":"door %d"%id,"point":Vector3(p[3],p[7],p[11])})
	for road: Dictionary in game.road_palette.prepared_streets:
		probes.append({"name":"road midpoint","point":(road.ends[0]+road.ends[1])*0.5})
	for probe: Dictionary in probes:
		var point: Vector3=probe.point
		var from: Vector3=point+Vector3.UP*15
		var to: Vector3=point-Vector3.UP*70
		var ready: bool=await wait_for(func():return not game._terrain_pick(from,to).is_empty(),8)
		var hit: Dictionary=game._terrain_pick(from,to)
		print("HEIGHT_PROBE ",probe.name," authored=",point," terrain=",hit)
		check(ready and absf(hit.get("position",Vector3.INF).y-point.y)<3,"terrain supports "+probe.name+" within foundation depth")
	await finish()
