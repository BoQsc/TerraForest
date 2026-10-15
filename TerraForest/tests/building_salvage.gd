# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"normal world ready"):await finish();return
	game.set_physics_process(false);game._clear_motion()
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.player_hud.equip(1)
	var origin: Vector3=game.player.position+Vector3(0,10,-3)
	var attack=game.world_attack
	for entry in [["architecture/wooden_door/v1",102,3],["architecture/wooden_window/v1",102,2],["architecture/metal_guardrail/v1",104,2],["architecture/wooden_fence/v1",102,2]]:
		var batch: Node3D=game.structures.model(entry[0])
		var id: int=batch.insert_instance(game.model_tool.records(Transform3D(Basis.IDENTITY,origin),batch),AABB())
		if entry[0]=="architecture/wooden_fence/v1":
			batch.remove_instances(PackedInt64Array([id]))
			game.construction_inventory.gameplay=true
			var inventory=game.player_hud.inventory
			inventory.grant(102,4,inventory.snapshot().revision)
			var wood_before:=amount(102)
			id=game._place_inventory_model(game.model_tool.history,batch,game.model_tool.records(Transform3D(Basis.IDENTITY,origin),batch),AABB(),preload("res://addons/structures/fence_catalog.gd").recipe())
			check(id>0 and amount(102)==wood_before-4,"fence gameplay placement debits four fixture wood")
		check(id>0,"building part inserted: "+entry[0])
		var point:=origin+Vector3(0,1,0)
		var feet:=origin+Vector3(0,0,2)
		if batch==game.doors.collection:
			check(game.doors.state.toggle(batch,id,AABB()).ok,"door opens before damage")
			point=origin+Vector3(0,1,-0.5);feet=origin+Vector3(2,0,-0.5)
		aim(feet,point);game.structures.set_model_focus(origin)
		for i in 15:await physics_frame;await process_frame
		var target: Dictionary=attack.target()
		if not check(target.get("kind")=="model" and target.get("id")==id and target.get("collection")==batch,"attack picks exact building part"):continue
		var before:=amount(entry[1])
		var wear: int=game.player_hud.inventory.snapshot().slots[1].wear
		batch.set_removal_protected(id,true)
		var inventory_before: PackedByteArray=game.player_hud.inventory.capture_storage_snapshot()
		attack.next_attack=0
		check(not attack.attack() and game.player_hud.inventory.capture_storage_snapshot()==inventory_before and not batch.get_instance(id).is_empty(),"protected part rejects damage without wear or reward")
		if batch==game.doors.collection:check(game.doors.state.is_open(id),"rejected damage preserves open hinge")
		batch.set_removal_protected(id,false)
		attack.next_attack=0
		check(attack.attack() and not batch.get_instance(id).is_empty(),"first hit damages without removing part")
		for i in 8:
			if batch.get_instance(id).is_empty():break
			attack.next_attack=0;attack.attack()
		check(batch.get_instance(id).is_empty() and amount(entry[1])==before+entry[2],"destruction grants exact partial salvage")
		check(game.player_hud.inventory.snapshot().slots[1].wear>wear,"shared attack wears tool")
		if batch==game.doors.collection:check(not game.doors.state.is_open(id),"destroyed open door leaves no hinge record")
		var after:=amount(entry[1])
		check(not game._remove_inventory_model(game.model_tool.history,batch,id) and amount(entry[1])==after,"removed identity cannot grant salvage twice")
		origin.x+=6
	await finish()
