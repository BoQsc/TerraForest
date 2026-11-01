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
	var restore:bool="--restore-locks" in OS.get_cmdline_user_args()
	expected=FileAccess.open(folder.path_join("expected.bin"),FileAccess.READ).get_var() if restore else JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("world.json")))
	if not check(str(expected.slot).begins_with("Exploration_"),"only owned generated exploration fixture is modified"):await finish();return
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed;await wait_for(browser_catalog_ready)
	var browser=current_scene;var selected:=-1
	for index in browser.worlds.item_count:
		if browser.worlds.get_item_metadata(index)==expected.slot:selected=index;break
	if not check(selected>=0,"ordinary browser lists this generated world"):await finish();return
	browser.worlds.select(selected);browser.launch_selected(false)
	if not check(await wait_for(game_ready,100),"normal saved-world loading reaches gameplay"):await finish();return
	game=current_scene;game.background_fps=60;game.app_focused=true;game.set_physics_process(false);game._clear_motion();game.zombies.update(0,game.player.global_position,false)
	if not check(preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"load preserves offscreen no-capture mode"):await finish();return
	var store:RefCounted=game.storage.store
	if restore:
		check(store.capture_storage_snapshot()==expected.storage,"fresh process restores exact remaining locks, damage and contents")
		check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"fresh process restores lockpicks and worn hatchet without duplication")
		for identity in expected.opened:check(not store.is_locked(identity) and store.has_contents(identity),"opened stocked chest stays open on reload: "+str(identity))
		if expected.partial>0:check(store.lock_state(expected.partial).remaining==150,"partially broken generated lock retains health on reload")
		await finish();return
	var locked:=PackedInt64Array()
	for identity in store.get_ids():
		if store.is_locked(identity):locked.append(identity)
	print("GENERATED_LOCK_IDENTITIES ",locked)
	if not check(locked.size()>=2,"ordinary generation published multiple rare stocked locks"):await finish();return
	var candidates:Dictionary={}
	var places:Array=game.generated_region.store.get_plan().places
	for place:Dictionary in places:
		game.teleport(place.position+Vector3.UP*.05)
		if not check(await wait_for(game_ready,90),"ordinary streaming admits generated place for lock inspection"):await finish();return
		game.set_physics_process(false);game.zombies.update(0,game.player.global_position,false)
		for identity in locked:
			var transform:PackedFloat32Array=game.storage.collection.get_instance(identity)
			if not transform.is_empty():candidates[identity]=transform
		if candidates.size()>=mini(3,locked.size()):break
	if not check(candidates.size()>=2,"streamed actual generated chest transforms located without inserting test objects"):await finish();return
	expected.opened=PackedInt64Array();expected.partial=0
	var index:=0
	for identity:int in candidates:
		if index>=3:break
		var row:PackedFloat32Array=candidates[identity];var point:=Vector3(row[3],row[7],row[11])
		game.teleport(point+Vector3.UP*.05)
		if not check(await wait_for(game_ready,90),"normal loading reaches actual locked chest location"):await finish();return
		game.set_physics_process(false);game.zombies.update(0,game.player.global_position,false)
		var aimed:=false
		for offset in [Vector3(0,.05,1.5),Vector3(0,.05,-1.5),Vector3(1.5,.05,0),Vector3(-1.5,.05,0)]:
			game.player.global_position=point+offset;game.camera.position=Vector3(0,1.65,0);game.camera.look_at(point+Vector3.UP*.4)
			for frame in 4:await physics_frame
			game.app_focused=true
			if game.storage.aimed_id()==identity:aimed=true;break
		if not check(aimed,"native live ray reaches generated chest without intervening obstruction"):await finish();return
		check(store.lock_state(identity).maximum==180 and store.has_contents(identity),"generated lock has supplies and doubled chest health")
		if index==1:
			game.player_hud.set_open(true);game.player_hud.craft_recipe(2);game.player_hud.craft_recipe(game.player_hud.Crafting.RECIPES.size()-1);game.player_hud.set_open(false)
			if not check(game.player_hud.inventory.can_afford(PackedInt64Array([213,3]),game.player_hud.inventory.snapshot().revision).ok,"normal inventory crafting provides three lockpicks"):await finish();return
			for attempt in 3:
				game.storage.try_open()
				if game.storage.opened:break
			check(game.storage.opened and not store.is_locked(identity),"E uses carried lockpick and opens generated chest")
			if game.storage.opened:await photograph("generated-lock-picked");game.storage.close()
			expected.opened.append(identity)
		else:
			game.player_hud.equip_item(2)
			for strike in (1 if index==2 else 6):
				var target:Dictionary=game.world_attack.target()
				if not check(target.get("kind")=="model" and target.get("id")==identity and game.world_attack.apply_target(target),"live hatchet contact adapter damages generated chest lock"):await finish();return
				if strike==0:await photograph("generated-lock-damaged-"+str(identity))
			if index==2:expected.partial=identity
			else:
				check(not store.is_locked(identity) and store.has_contents(identity) and game.storage.collection.is_removal_protected(identity),"six hatchet hits open lock without destroying stored supplies")
				check(game.storage.try_open() and game.storage.opened,"E opens forced chest through live picking")
				if game.storage.opened:
					await photograph("generated-lock-forced")
					game.storage.storage_list.select(1);game.storage.quantity.get_line_edit().text="2"
					check(game.storage.move_selected(false) and game.player_hud.inventory.can_afford(PackedInt64Array([202,2]),game.player_hud.inventory.snapshot().revision).ok,"normal chest UI collects two generated iron ore for crafting")
					game.storage.close()
				expected.opened.append(identity)
		index+=1
	expected.storage=store.capture_storage_snapshot();expected.inventory=game.player_hud.inventory.capture_storage_snapshot()
	FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE).store_var(expected)
	await finish()
func finish()->void:
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"test never captures the desktop pointer")
	if game_ready():
		current_scene.shutdown_requested=true;check(await current_scene.terrain.shutdown_after_edits(),"owned test world saves durably")
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame
	print("CONTAINER_LOCK_WORLD checks=",checks," failures=",failures)
	quit(1 if failures else 0)
