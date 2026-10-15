# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func settle() -> void:
	for i in 12:await physics_frame;await process_frame
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,45),"gameplay world loads"):await finish();return
	game.set_physics_process(false);game._clear_motion()
	if not check(game.ground_enabled and game.construction_inventory.gameplay,"paid gameplay and ground gathering enabled"):await finish();return
	var hud=game.player_hud
	var fixture: RefCounted=ClassDB.instantiate("NativePlayerInventory")
	fixture.register_item(1,1);fixture.register_durable(1,200);fixture.grant(1,1,0);fixture.wear_tool(0,199,1)
	check(hud.restore_snapshot(fixture.capture_storage_snapshot()),"only starting supply is a nearly broken pickaxe")
	hud.equip(0)
	var cell:=Vector3i(game.player.position.floor())+Vector3i(0,8,-3)
	check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,33])),"wooden impact target prepared")
	game.structures.blocks.set_focus(Vector3(cell));aim(Vector3(cell)+Vector3(0.5,-1.12,2),Vector3(cell)+Vector3.ONE*0.5)
	await settle()
	game.world_attack.next_attack=0
	check(game.world_attack.attack() and hud.inventory.snapshot().slots[0].item==0,"normal attack consumes last durability and breaks tool")
	check(game.equipped_tool==0 and hud.active_item==0 and game._lake_notice.contains("Pickaxe broke") and game._lake_notice.contains("Crafting"),"break switches to empty hands and explains replacement")
	var target: Dictionary=game.world_attack.target()
	game.world_attack.next_attack=0
	check(target.get("kind")=="block" and game.world_attack.attack(),"empty hands can continue the same attack path")
	hud.set_open(true);hud.craft_recipe(7)
	check(amount(1)==0 and hud.crafting_message.text.contains("Gather"),"missing ingredients rejects replacement with current guidance")
	hud.set_open(false)
	if not check(await wait_for(func():return game.ground_cover.resident.size()>=49,15),"natural ground cover ready"):await finish();return
	# Gather real generated stones and dry twigs. No material grants are used.
	for species in [0,7]:
		var needed: int=3 if species==0 else 2
		var collected:=0
		var candidates: Array=[]
		for rows: Array in game.ground_cover.resident.values():
			var row: Dictionary=rows[species]
			for i in row.ids.size():
				var t: PackedFloat32Array=row.transforms
				candidates.append({"id":row.ids[i],"point":Vector3(t[i*12+3],t[i*12+7],t[i*12+11])})
		for candidate: Dictionary in candidates:
			if collected>=needed:break
			aim(candidate.point+Vector3(0.6,0,0.8),candidate.point+Vector3(0,0.15,0))
			var probe: Dictionary=game.ground_interaction.collection_probe(game.camera.global_position,game.camera.global_position-game.camera.global_basis.z*2.5)
			if not probe.ok or probe.hit.id!=candidate.id:continue
			var item: int=201 if species==0 else 102;var before:=amount(item)
			use()
			if amount(item)==before+1:collected+=1
		if not check(collected==needed,"gathered %d actual %s"%[needed,"stones" if species==0 else "dry twigs"]):await finish();return
	check(amount(201)==3 and amount(102)==2,"all replacement costs earned through E gathering")
	hud.set_open(true);hud.craft_recipe(7)
	check(amount(1)==1 and amount(201)==0 and amount(102)==0,"crafting UI consumes exact earned resources for replacement")
	var slot:=slot_of(1)
	if not check(slot>=0,"replacement exists"):await finish();return
	check(hud.inventory.snapshot().slots[slot].wear==0 and hud.inventory.snapshot().slots[slot].durability==200,"replacement begins with full durability")
	if slot!=0:check(hud.inventory.transfer(slot,0,1,hud.inventory.snapshot().revision).ok,"replacement moves from backpack to empty toolbelt")
	hud.refresh();hud.set_open(false);hud.equip(0)
	check(game.equipped_tool==1 and hud.active_item==1,"replacement equips through gameplay toolbelt")
	aim(Vector3(cell)+Vector3(0.5,-1.12,2),Vector3(cell)+Vector3.ONE*0.5)
	game.world_attack.next_attack=0
	check(game.world_attack.attack() and hud.inventory.snapshot().slots[0].wear==1,"crafted replacement attacks and wears normally")
	var saved: PackedByteArray=hud.capture_snapshot()
	hud.inventory.wear_tool(0,1,hud.inventory.snapshot().revision)
	check(hud.restore_snapshot(saved) and hud.capture_snapshot()==saved,"replacement inventory snapshot restores exactly")
	await finish()
