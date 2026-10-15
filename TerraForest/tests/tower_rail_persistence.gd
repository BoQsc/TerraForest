# SPDX-License-Identifier: 0BSD
extends "res://tests/world_browser_route.gd"
const Rails=preload("res://addons/structures/guardrail_catalog.gd")
func inspect_world(reopen: bool)->void:
	var rails: Node3D=game.structures.model(Rails.STAIR_KEY)
	if not check(rails!=null,"main world registers stair rail persistence identity"):return
	var path:=report.path_join("tower.bin")
	var expected: Dictionary
	if not reopen:
		var asset: Resource=preload("res://addons/structures/furniture_catalog.gd").furnished_tower(3)
		var origin:=Vector3i(game.player.position.floor())+Vector3i(30,40,0)
		# An elevated fixture isolates structure collision from terrain grading;
		# use the real prefab transaction and ordinary compound world save.
		var construction=preload("res://addons/player_runtime/construction_inventory.gd").new()
		if not check(construction.place_prefab(game.structures.blocks,game.player_hud.inventory,asset,origin,1,game.structures.model_collections(),preload("res://addons/structures/construction_catalog.gd").recipes(),[]),"quarter-turned tower places through normal transaction"):
			print(construction.reason);return
		check(rails.get_ids().size()==4,"tower owns four sloping rails")
		expected={"rails":rails.capture_snapshot(),"origin":Vector3(origin),"blocks":game.structures.blocks.capture_snapshot()}
		var file:=FileAccess.open(path,FileAccess.WRITE);file.store_var(expected);file.close()
	else:
		expected=FileAccess.open(path,FileAccess.READ).get_var()
		check(rails.capture_snapshot()==expected.rails,"fresh process restores exact rotated rail identities and transforms")
		check(game.structures.blocks.capture_snapshot()==expected.blocks,"fresh process restores exact tower blocks")
	game.set_process(false)
	game.structures.set_model_focus(expected.origin);game.structures.blocks.set_focus(expected.origin)
	check(await wait_until(func():return game.structures.is_collision_region_ready(AABB(expected.origin+Vector3(-10,-1,-10),Vector3(22,16,22))),15),"rotated tower collision becomes resident")
	var ids: PackedInt64Array=rails.get_ids()
	for id in ids:
		var p: PackedFloat32Array=rails.get_instance(id)
		var frame:=Transform3D(Basis(Vector3(p[0],p[4],p[8]),Vector3(p[1],p[5],p[9]),Vector3(p[2],p[6],p[10])),Vector3(p[3],p[7],p[11]))
		var hit: Dictionary=game.structures.blocks.raycast_scene(frame*Vector3(-0.3,1.05,0.5),frame*Vector3(0.3,1.05,0.5),2,[])
		check(not hit.is_empty() and hit.get("collider")==rails,"restored/placed sloping top rail has matching physics")
