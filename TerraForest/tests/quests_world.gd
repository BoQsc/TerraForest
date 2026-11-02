# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
var game:Node
var expected:Dictionary={}

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	super._initialize()

func run()->void:
	var restoring:bool="--restore-quests" in OS.get_cmdline_user_args()
	var exercising:bool="--exercise-quests" in OS.get_cmdline_user_args()
	var baselines_only:bool="--baseline-check" in OS.get_cmdline_user_args()
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed;await wait_for(browser_catalog_ready)
	var browser:=current_scene
	if restoring or exercising or baselines_only:
		expected=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("created_slot.json"))) if baselines_only else FileAccess.open(folder.path_join("expected.bin"),FileAccess.READ).get_var()
		if not check(str(expected.slot).begins_with("Quests_"),"reopen only an owned quest fixture"):await finish();return
		var selected:=-1
		for index in browser.worlds.item_count:
			if browser.worlds.get_item_metadata(index)==expected.slot:selected=index;break
		if not check(selected>=0,"normal selector lists the generated fixture"):await finish();return
		browser.worlds.select(selected);browser.launch_selected(false)
	else:
		expected.slot="Quests_1703_"+Crypto.new().generate_random_bytes(4).hex_encode()
		FileAccess.open(folder.path_join("created_slot.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":expected.slot}))
		browser.name_field.text=expected.slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
		check(browser.selected_options()==preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS,"ordinary default generation has no special quest fixture recipe")
		browser.generate_button.pressed.emit()
	if not check(await wait_for(game_ready,520),"ordinary generation or loading reaches gameplay"):await finish();return
	game=current_scene;game.background_fps=60;game.app_focused=true;game.set_physics_process(false);game._clear_motion();game.zombies.update(0,game.player.global_position,false)
	var store:RefCounted=game.quests.store;var locations:Array=store.get_locations()
	check(game.persistence._providers.has("player_quests") and store.snapshot().seed==1703,"native quest component participates in the actual compound world save")
	if baselines_only:
		await verify_baseline_roundtrip();await finish();return
	if not restoring and not exercising:
		check(game.persistence.location_baselines.capture_storage_snapshot().size()==80,"ordinary generation publishes its world identity without placeholder owner patches")
		if not check(not locations.is_empty() and store.accept(locations[0].key,store.snapshot().revision).ok,"newly generated world accepts its first real location"):await finish();return
		remember(store)
		game.terrain.changed_since_save=true
		if not check(await leave(),"immediate post-generation save returns normally without waiting for a tour"):await finish();return
		browser=current_scene
		var selected:=-1
		for index in browser.worlds.item_count:
			if browser.worlds.get_item_metadata(index)==expected.slot:selected=index;break
		if not check(selected>=0,"first save remains in the ordinary selector"):await finish();return
		browser.worlds.select(selected);browser.launch_selected(false)
		if not check(await wait_for(game_ready,120),"first post-generation save reopens normally"):await finish();return
		game=current_scene;game.background_fps=60;game.app_focused=true;game.set_physics_process(false);game._clear_motion();game.zombies.update(0,game.player.global_position,false)
		store=game.quests.store;locations=store.get_locations()
		check(store.capture_storage_snapshot()==expected.quests,"first post-generation reservation restores exactly")
		check(game.persistence.location_baselines.capture_storage_snapshot()==expected.baselines,"published generation identity survives first normal save and reopen")
		if not check(store.abandon(store.snapshot().revision).ok,"owned first-save fixture clears its test reservation"):await finish();return
	if restoring:
		if expected.has("baselines"):check(game.persistence.location_baselines.capture_storage_snapshot()==expected.baselines,"fresh process preserves generation baseline identity")
		check(store.capture_storage_snapshot()==expected.quests,"fresh process restores exact generated ownership and accepted contract")
		check(store.snapshot().phase==1 and store.snapshot().key==expected.key,"travel reservation persists without inventing reset or kill progress")
		check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory and game.player_hud.progression.capture_storage_snapshot()==expected.progression,"metadata and reservation add no items or XP")
		check(game.storage.store.capture_storage_snapshot()==expected.storage,"quest metadata does not refill existing containers")
	else:
		if exercising and store.snapshot().phase!=0:
			if not check(store.abandon(store.snapshot().revision).ok,"owned fixture abandons only its previous reservation"):await finish();return
		var types:Array=[];var owned_residents:Dictionary={};var owned_chests:Dictionary={}
		for entry:Dictionary in locations:
			types.append(entry.layout)
			for key in entry.residents:owned_residents[key]=entry.key
			for identity in entry.containers:owned_chests[identity]=entry.key
		check(types.count("survey_mine")==1 and types.count("split_rock_cave")==1 and types.count("coal_mine")==1 and types.count("watchtower_w1")==2,"all underground layouts and both generated watchtowers publish location identities")
		var population:RefCounted=game.zombies.population.store;var found:=0
		for identity in range(1,population.statistics().slots+1):
			var resident:Dictionary=population.resident(identity)
			if owned_residents.has(resident.anchor):found+=1
		check(found==owned_residents.size() and found==20,"ownership refers to all twenty actual generated sleepers, not synthetic copies")
		var original_position:Vector3=game.player.global_position
		for entry:Dictionary in locations:
			if not await stream_to(entry.marker+Vector3.UP*2):await finish();return
			var chests_ready:bool=await wait_for(func():
				for identity in entry.containers:
					if game.storage.collection.get_instance(identity).size()!=12:return false
				return true,30)
			for identity in entry.containers:
				chests_ready=chests_ready and game.storage.store.has_contents(identity)
			check(chests_ready,"resident location owns actual stocked chest placements: "+entry.layout)
		if not await stream_to(original_position):await finish();return
		check(owned_chests.size()==12,"all twelve owned chests were checked through normal region streaming")
		var registry:PackedByteArray=store.capture_storage_snapshot()
		check(registry.size()<4096 and store.validate_snapshot(registry),"generated ownership stays compact without serializing the whole world")
		check(not locations.is_empty() and store.accept(locations[0].key,store.snapshot().revision).ok,"native travel reservation uses a real generated location")
		remember(store)
		print("QUEST_WORLD_OWNERSHIP bytes=",registry.size()," sites=",locations.size()," residents=",owned_residents.size()," chests=",owned_chests.size())
	game.terrain.changed_since_save=true
	check(await leave(),"normal save and return publishes quest state with the world")
	await finish()

func verify_baseline_roundtrip()->void:
	var manifest:PackedByteArray=game.persistence.location_baselines.capture_storage_snapshot()
	var quests:PackedByteArray=game.quests.store.capture_storage_snapshot()
	check(manifest.size()==80 and game.persistence.location_baselines.state().locations==0,"ordinary generated world has its own identity, not invented owner originals")
	var expected_path:=folder.path_join("baseline_expected.bin")
	if "--baseline-reopen" in OS.get_cmdline_user_args():
		check(FileAccess.get_file_as_bytes(expected_path)==manifest,"fresh process restores the exact generated world identity")
	else:FileAccess.open(expected_path,FileAccess.WRITE).store_buffer(manifest)
	game.terrain.changed_since_save=true
	if not check(await leave(),"normal save and return publishes baseline reference section"):return
	var browser:=current_scene;var selected:=-1
	for index in browser.worlds.item_count:
		if browser.worlds.get_item_metadata(index)==expected.slot:selected=index;break
	if not check(selected>=0,"generated world remains in ordinary selector"):return
	browser.worlds.select(selected);browser.launch_selected(false)
	if not check(await wait_for(game_ready,120),"normal selector reopens generated world with baseline metadata"):return
	game=current_scene;game.background_fps=60;game.app_focused=true;game.set_physics_process(false);game._clear_motion();game.zombies.update(0,game.player.global_position,false)
	check(game.persistence.location_baselines.capture_storage_snapshot()==manifest,"normal save/reopen keeps exact baseline identity")
	check(game.quests.store.capture_storage_snapshot()==quests,"baseline persistence does not bypass introduction or start a quest")
	check(await leave(),"baseline check closes through normal save path")

func remember(store:RefCounted)->void:
	expected.key=store.snapshot().key
	expected.baselines=game.persistence.location_baselines.capture_storage_snapshot()
	expected.quests=store.capture_storage_snapshot();expected.inventory=game.player_hud.inventory.capture_storage_snapshot();expected.progression=game.player_hud.progression.capture_storage_snapshot();expected.storage=game.storage.store.capture_storage_snapshot()
	FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE).store_var(expected)

func stream_to(point:Vector3)->bool:
	game.teleport(point)
	if not check(await wait_for(game_ready,100),"normal streaming reaches quest location"):return false
	game.set_physics_process(false);game.app_focused=true;game._clear_motion();game.fly=false
	game.zombies.update(0,game.player.global_position,false)
	return true

func save_diagnostic()->void:
	if not is_instance_valid(game):return
	var pager:Node=game.model_paging
	print("QUEST_SAVE_DIAGNOSTIC ",JSON.stringify({"manual":game.terrain._manual_save_requested,"pending_edit":game.terrain.pending_edit,"closing":game.terrain.closing,"stopping":game.terrain.stopping,"world_ready":game.terrain.world_ready,"error":game.terrain.latest_error,"message":game.session_menu.message.text,"leaving":game.session_menu.leaving_world,"shutdown":game.shutdown_requested,"pager_operation":pager.operation,"pager_waiting":pager.waiting_save,"pager":pager.last_state,"queue":game.terrain.backend.diagnostic_queue_snapshot()}))

func leave()->bool:
	var began:=Time.get_ticks_usec()
	save_diagnostic()
	game.terrain.save_completed.connect(func(success:bool):print("QUEST_SAVE_PROFILE ",JSON.stringify({"success":success,"elapsed_us":Time.get_ticks_usec()-began,"profile":game.terrain.backend.save_profile(),"capture":game.persistence.last_capture})),CONNECT_ONE_SHOT)
	current_scene.session_menu.leave_to_browser()
	var deadline:=Time.get_ticks_msec()+40000
	var next_report:=Time.get_ticks_msec()+5000
	while not browser_catalog_ready() and Time.get_ticks_msec()<deadline:
		await process_frame
		if Time.get_ticks_msec()>=next_report:
			save_diagnostic();next_report=Time.get_ticks_msec()+5000
	if not browser_catalog_ready():save_diagnostic()
	return browser_catalog_ready()

func finish()->void:
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"quest checks never capture or reposition the desktop pointer")
	if game_ready():current_scene.shutdown_requested=true;await current_scene.terrain.shutdown_after_edits()
	if is_instance_valid(current_scene):current_scene.free()
	print("QUESTS_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
