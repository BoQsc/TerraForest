extends "res://tests/window_session_flow.gd"

const Trade=preload("res://addons/player_runtime/trader_inventory.gd")
var game:Node
var expected:Dictionary={}

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	super._initialize()

func item_slot(identity:int)->int:
	var state:Dictionary=game.player_hud.inventory.snapshot()
	for index in state.slots.size():
		if state.slots[index].item==identity and state.slots[index].count>0:return index
	return -1

func stream_to(point:Vector3)->bool:
	game.teleport(point)
	if not check(await wait_for(game_ready,100),"normal streaming reaches generated supply location"):return false
	game.set_physics_process(false);game.app_focused=true;game._clear_motion();game.fly=false
	game.zombies.update(0,game.player.global_position,false)
	return true

func collect_chest(identity:int,point:Vector3)->bool:
	if not await stream_to(point+Vector3.UP*.05):return false
	var aimed:=false
	for offset in [Vector3(0,.05,1.5),Vector3(0,.05,-1.5),Vector3(1.5,.05,0),Vector3(-1.5,.05,0)]:
		game.player.global_position=point+offset;game.camera.position=Vector3(0,1.65,0);game.camera.look_at(point+Vector3.UP*.4)
		for frame in 4:await physics_frame
		game.app_focused=true
		if game.storage.aimed_id()==identity:aimed=true;break
	if not check(aimed,"live native scene ray reaches actual generated supply chest"):return false
	if game.storage.store.is_locked(identity):
		game.player_hud.equip_item(2)
		for strike in 7:
			if not game.storage.store.is_locked(identity):break
			var target:Dictionary=game.world_attack.target()
			if not check(target.get("id")==identity and game.world_attack.apply_target(target),"actual hatchet contact opens generated lock"):return false
	if not check(game.storage.try_open() and game.storage.opened,"ordinary E adapter opens chest"):return false
	await photograph("supply-"+str(identity))
	for index in game.storage.box_state.slots.size():
		var row:Dictionary=game.storage.box_state.slots[index]
		if row.item in [102,214,215,216,217,218,219] and row.count>0:
			game.storage.storage_list.select(index);game.storage.quantity.get_line_edit().text=str(row.count)
			if not check(game.storage.move_selected(false),"actual chest UI withdraws generated item %d"%row.item):return false
	game.storage.close();return true

func run()->void:
	var restore:bool="--restore-survival" in OS.get_cmdline_user_args()
	var exercise:bool="--exercise-survival" in OS.get_cmdline_user_args()
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed;await wait_for(browser_catalog_ready)
	var browser=current_scene
	if restore or exercise:
		expected=FileAccess.open(folder.path_join("expected.bin"),FileAccess.READ).get_var() if restore else JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("created_slot.json")))
		if not check(str(expected.slot).begins_with("Survival_"),"only owned survival fixture may be reopened"):await finish();return
		var selected:=-1
		for index in browser.worlds.item_count:
			if browser.worlds.get_item_metadata(index)==expected.slot:selected=index;break
		if not check(selected>=0,"normal selector lists generated world"):await finish();return
		browser.worlds.select(selected);browser.launch_selected(false)
	else:
		expected.slot="Survival_1703_"+Crypto.new().generate_random_bytes(4).hex_encode()
		FileAccess.open(folder.path_join("created_slot.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":expected.slot}))
		browser.name_field.text=expected.slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
		check(browser.selected_options()==preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS,"ordinary default recipe without review/developer switches")
		browser.generate_button.pressed.emit()
	if not check(await wait_for(game_ready,520),"ordinary generation or loading reaches gameplay"):await finish();return
	game=current_scene;game.background_fps=60;game.app_focused=true;game.set_physics_process(false);game._clear_motion()
	game.zombies.update(0,game.player.global_position,false)
	var hud:Node=game.player_hud
	hud.set_open(true)
	if restore:
		check(hud.survival.capture_storage_snapshot()==expected.survival,"fresh process restores exact food, timed buffs and reading history")
		check(hud.inventory.capture_storage_snapshot()==expected.inventory,"fresh process restores consumed foods and books without duplication")
		check(hud.progression.capture_storage_snapshot()==expected.progression,"fresh process restores mild earned reading experience")
		check(game.storage.store.capture_storage_snapshot()==expected.storage,"depleted generated supplies do not refill")
		check(game.trader.trader.stock.capture_storage_snapshot()==expected.trade,"finite food purchase and sold stock restore")
		check(hud.skill_damage(1,100)==expected.damage,"saved native buff still affects actual gameplay damage adapter")
		hud.show_side("Journal");await create_timer(.5).timeout;await photograph("journal-restored")
		check(hud.journal_panel.choices.item_count>=1,"read narrative remains available after item consumption and reopening")
		hud.set_open(false)
		if check(game.trader.try_open({"collider":game.trader.actor}),"restored merchant remains reachable through ordinary interaction"):
			game.trader.ui.select_mode("Trade")
			game.trader.ui.rows.select(game.trader.ui.rows.item_count-1);game.trader.ui.refresh()
			for frame in 2:await process_frame
			await process_frame;await process_frame
			check(game.trader.ui.rows.get_v_scroll_bar().value>0,"last food offer remains visible after UI refresh")
			await photograph("food-trade-restored")
		await finish();return
	check(game.persistence._providers.has("player_survival") and game.persistence._providers.size()<127,"survival fits bounded compound save registry")
	var candidates:Dictionary={}
	var places:Array=game.generated_region.store.get_plan().places
	hud.set_open(false)
	for place:Dictionary in places:
		if not place.title in ["Abandoned survey mine","Split-rock cave"]:continue
		if not await stream_to(place.position):await finish();return
		for identity in game.storage.store.get_ids():
			var contents:Dictionary=game.storage.store.snapshot(identity)
			if not contents.slots.any(func(row:Dictionary):return row.item in [214,215,216] and row.count>0):continue
			if not contents.slots.any(func(row:Dictionary):return row.item==217 and row.count>0) or not contents.slots.any(func(row:Dictionary):return row.item==218 and row.count>0):continue
			var transform:PackedFloat32Array=game.storage.collection.get_instance(identity)
			if not transform.is_empty():candidates[identity]=Vector3(transform[3],transform[7],transform[11])
	if not check(candidates.size()>=2,"ordinary generated sites contain new food and readable stock"):await finish();return
	var collected:=0
	var readables:Dictionary={}
	for identity:int in candidates:
		var reading:int=0
		for row:Dictionary in game.storage.store.snapshot(identity).slots:
			if row.item in [214,215,216] and row.count>0:reading=row.item;break
		if readables.has(reading):continue
		if not await collect_chest(identity,candidates[identity]):await finish();return
		readables[reading]=true
		collected+=1
		if collected>=2:break
	check(readables.size()==2,"two different authored locations supply different readable items")
	if not check(item_slot(217)>=0 and item_slot(218)>=0 and (item_slot(214)>=0 or item_slot(215)>=0 or item_slot(216)>=0),"ordinary loot supplies usable food and reading without grants"):await finish();return
	var merchant:=Vector3.INF
	for place:Dictionary in places:
		if place.id==game.trader.PLACE:merchant=place.position;break
	if not check(merchant.is_finite(),"ordinary generated trader is published"):await finish();return
	if not await stream_to(merchant):await finish();return
	if not check(await wait_for(func():return is_instance_valid(game.trader.actor),20),"native resident collision admits merchant"):await finish();return
	var reachable:=false
	for offset in [Vector3(0,0,1.5),Vector3(0,0,-1.5),Vector3(1.5,0,0),Vector3(-1.5,0,0)]:
		game.player.global_position=merchant+offset;game.camera.position=Vector3(0,1.65,0);game.camera.look_at(merchant+Vector3.UP*1.45)
		for frame in 4:await physics_frame
		game.app_focused=true
		if game.trader.reachable():reachable=true;break
	if not check(reachable and game.trader.try_open({"collider":game.trader.actor}),"real reachable trader opens through normal adapter"):await finish();return
	var trade:Node=game.trader.ui
	trade.select_mode("Trade")
	for index in trade.rows.item_count:
		if trade.rows.get_item_metadata(index)==102:trade.rows.select(index)
	trade.quantity.get_line_edit().text="3";trade.exchange(false)
	check(Trade.count(hud.inventory,601)>=6,"generated timber sold through actual trading UI earns food money")
	for index in trade.rows.item_count:
		if trade.rows.get_item_metadata(index)==219:trade.rows.select(index)
	trade.quantity.get_line_edit().text="1";trade.exchange(true)
	check(item_slot(219)>=0 and Trade.count(game.trader.trader.stock,219)==23,"actual buy action exchanges finite food stock and coins")
	await photograph("food-trade");trade.close()
	var bread:=item_slot(218);var before_count:int=Trade.count(hud.inventory,218)
	var drop_point:Vector3=game.camera.global_position-game.camera.global_basis.z
	check(game.pickups.drop_one(hud.inventory,bread,hud.inventory.snapshot().revision,drop_point).ok,"generated food can be dropped through native item transaction")
	check(game.pickups.collect_aimed(game.camera.global_position,drop_point+game.camera.global_basis.z*-.4,hud.inventory,func(_point:Vector3)->bool:return true).ok and Trade.count(hud.inventory,218)==before_count,"native aimed pickup preserves dropped food quantity")
	hud.refresh();hud.set_open(true)
	var initial_xp:int=hud.progression.snapshot().xp
	var double:=InputEventMouseButton.new();double.pressed=true;double.button_index=MOUSE_BUTTON_LEFT;double.double_click=true
	var readable:=214 if item_slot(214)>=0 else 215 if item_slot(215)>=0 else 216
	check(hud.item_input(item_slot(readable),double) and hud.progression.snapshot().xp>initial_xp,"inventory double click reads actual looted book and earns mild XP")
	hud.survival.advance(720000);hud.survival_changed.emit()
	var right:=InputEventMouseButton.new();right.pressed=true;right.button_index=MOUSE_BUTTON_RIGHT
	check(hud.item_input(item_slot(217),right) and hud.item_context.visible,"looted food exposes actual Use context menu")
	hud.item_context.id_pressed.emit(0);hud.item_context.hide()
	check(hud.survival.snapshot().food_ms==3600000 and hud.skill_damage(1,100)==105,"eating restores food and applies native Well fed modifier")
	var condition:PackedByteArray=hud.survival.capture_storage_snapshot()
	await create_timer(1.1).timeout
	check(hud.survival.capture_storage_snapshot()==condition,"ordinary inventory pauses food and timed buffs")
	hud.set_open(false);await create_timer(1.1).timeout;hud.set_open(true)
	check(hud.survival.snapshot().food_ms<3600000,"real one-second gameplay timer drains only active time")
	hud.show_side("Journal");await photograph("journal-earned")
	expected.survival=hud.survival.capture_storage_snapshot();expected.inventory=hud.inventory.capture_storage_snapshot();expected.progression=hud.progression.capture_storage_snapshot()
	expected.storage=game.storage.store.capture_storage_snapshot();expected.trade=game.trader.trader.stock.capture_storage_snapshot();expected.damage=hud.skill_damage(1,100)
	FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE).store_var(expected)
	await finish()

func finish()->void:
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"test never captures or recenters desktop pointer")
	if game_ready():
		current_scene.shutdown_requested=true;check(await current_scene.terrain.shutdown_after_edits(),"owned world saves durably")
	if is_instance_valid(current_scene):current_scene.free()
	print("PLAYER_SURVIVAL_WORLD checks=",checks," failures=",failures)
	quit(1 if failures else 0)
