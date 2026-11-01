# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
const Clothing=preload("res://addons/characters/wearables/clothing.gd")

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	super._initialize()

func minimal(clothes:Node)->bool:
	if clothes==null or clothes.worn!=PackedInt32Array([0,0,0]):return false
	for original:Dictionary in clothes.covered:
		if original.item!=301 and original.node.visible:return false
	return true

func run()->void:
	var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("world.json")))
	if not check(str(receipt.slot).begins_with("ClothingLoot_"),"only an owned copied world can be opened"):await finish();return
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed;await wait_for(browser_catalog_ready)
	if not check(await open_world(receipt.slot,false,1,1703,true),"ordinary saved world opens"):await finish();return
	var game:=current_scene;game.background_fps=30;game.app_focused=true;game.set_physics_process(false);game._clear_motion()
	# The shared browser fixture passes --no-zombies. Enable one controlled
	# resident through the production spawn path, keeping ambient spawns off.
	game.zombies.enabled=true;game.zombies.population_enabled=false
	game.player.collision_mask|=game.zombies.CHARACTER_LAYER
	var hud:Node=game.player_hud;var store:RefCounted=game.corpse_loot.store
	var record:Dictionary={}
	if "--restore" in OS.get_cmdline_user_args():
		record=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("loot.json")))
		check(store.snapshot(int(record.corpse)).slots[int(record.slot)].count==0,"fresh process keeps the looted corpse slot empty")
		check(hud.equipment.snapshot(1).slots[Clothing.SLOTS[int(record.item)]].item==int(record.item),"fresh process restores the looted item in equipment")
		var total:=0
		for row:Dictionary in hud.inventory.snapshot().slots:
			if row.item==int(record.item):total+=row.count
		check(total==0,"looted clothing is not duplicated in the backpack on reload")
	else:
		hud.set_open(true);hud.show_side("Character");await process_frame
		check(minimal(hud.character_panel.clothing) and minimal(game.tool_view.human.clothing),"empty equipment shows the minimal starter in portrait and world")
		await photograph("starter-character");hud.set_open(false)
		# Select a fixture seed through the real allocator so one actual death
		# exercises a clothing drop, without spawning a crowd or mirroring its RNG.
		var before:PackedByteArray=store.capture_corpse_snapshot();var chosen_seed:=-1
		for seed in 64:
			var probe:RefCounted=ClassDB.instantiate("NativeCorpseStore");probe.configure(hud.inventory,4096,8);probe.restore_corpse_snapshot(before)
			var candidate:int=probe.create_corpse(game.player.global_position,0,seed)
			for row:Dictionary in probe.snapshot(candidate).slots:
				if row.item in [304,305,306]:chosen_seed=seed;break
			if chosen_seed>=0:break
		if not check(chosen_seed>=0,"bounded fixture search finds a native clothing drop"):await finish();return
		var zombie:Node3D
		# The copied player can be on a constructed floor. Query that surface,
		# then use ordinary authored-resident support/clearance admission.
		for distance in [2.0,4.0,6.0]:
			for offset in [Vector3(0,0,1),Vector3(1,0,0),Vector3(-1,0,0),Vector3(0,0,-1)]:
				var around:Vector3=game.player.global_position+offset*distance
				var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(around+Vector3.UP*4,around-Vector3.UP*8,1|2|4))
				if hit.is_empty():continue
				zombie=game.zombies.spawn_at(hit.position+Vector3.UP*.06,false,true)
				if zombie!=null:break
			if zombie!=null:break
		if zombie==null:print("LOOT_ADMISSION enabled=",game.zombies.enabled," residents=",game.zombies.residents.size()," player=",game.player.global_position)
		if not check(zombie!=null,"actual zombie admits on resident world collision"):await finish();return
		zombie.set_behavior(false);zombie.set_physics_process(false)
		var world_seed:int=game.ecosystem.seed;game.ecosystem.seed=chosen_seed
		zombie.die();game.ecosystem.seed=world_seed
		var id:int=zombie.get_meta("corpse_identity",0)
		if not check(id>0 and not zombie.alive and game.corpse_loot.active.get(id)==zombie,"actual death signal retains a native lootable corpse"):await finish();return
		var slot:=-1;var item:=0
		for i in store.snapshot(id).slots.size():
			var row:Dictionary=store.snapshot(id).slots[i]
			if row.item in [304,305,306]:slot=i;item=row.item;break
		if not check(slot>=0,"new corpse contains one trail garment"):await finish();return
		for frame in 120:await physics_frame
		var aimed:=false
		for offset in [Vector3(0,1.4,1.2),Vector3(1.2,1.4,0),Vector3(0,1.4,-1.2),Vector3(-1.2,1.4,0)]:
			var point:Vector3=zombie.physical_bones.Hips.global_position
			game.camera.global_position=point+offset;game.camera.look_at(point)
			for frame in 3:await physics_frame
			game.app_focused=true
			if game.corpse_loot.aimed_id()==id:aimed=true;break
		if not check(aimed and game.corpse_loot.ui.try_open(),"real corpse ray opens the ordinary loot UI"):await finish();return
		var ui:Node=game.corpse_loot.ui
		await photograph("corpse-clothing")
		var destination:=-1
		for i in range(10,32):
			if hud.inventory.snapshot().slots[i].count==0:destination=i;break
		if not check(destination>=0,"owned backpack has space for the garment"):await finish();return
		ui.drop_stack("player",destination,ui.drag_data("chest",slot))
		if not check(hud.inventory.snapshot().slots[destination].item==item and store.snapshot(id).slots[slot].count==0,"ordinary corpse drag transfers exactly one garment into the backpack"):await finish();return
		ui.close();hud.set_open(true);hud.show_side("Character")
		hud.character_panel.drop_stack("equipment",Clothing.SLOTS[item],hud.drag_data("player",destination))
		check(hud.equipment.snapshot(1).slots[Clothing.SLOTS[item]].item==item,"looted garment equips through its ordinary matching slot")
		record={"corpse":id,"slot":slot,"item":item}
		FileAccess.open(folder.path_join("loot.json"),FileAccess.WRITE).store_string(JSON.stringify(record))
	hud.set_open(true);hud.show_side("Character");await process_frame
	check(game.tool_view.human.clothing.worn[Clothing.SLOTS[int(record.item)]]==int(record.item) and hud.character_panel.clothing.worn==game.tool_view.human.clothing.worn,"looted clothing agrees in portrait and production player view")
	await photograph("looted-character");hud.set_open(false)
	check(await leave(),"normal save and return persists corpse loot and equipment")
	await finish()

func finish()->void:
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"review never captures the pointer")
	if game_ready():current_scene.shutdown_requested=true;await current_scene.terrain.shutdown_after_edits()
	if is_instance_valid(current_scene):current_scene.free()
	print("CLOTHING_LOOT_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
