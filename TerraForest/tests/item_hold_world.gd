# SPDX-License-Identifier: 0BSD
extends "res://tests/attack_contact_world.gd"
func count_item(item:int)->int:
	var count:=0
	for row:Dictionary in game.player_hud.inventory.snapshot().slots:
		if row.item==item:count+=row.count
	return count
func run()->void:
	folder="res://reports/item_hold/integration";DirAccess.make_dir_recursive_absolute(folder)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	check(await until(func():return not game.loading_active and not game.needs_floor_spawn and not game.player_view.entry.blocks_actions(),65),"temporary world and player entry ready")
	if game.loading_active or game.player_view.entry.blocks_actions():await finish();return
	game.set_physics_process(false);game._clear_motion();game.zombies.clear();game.zombies.population_enabled=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var hud=game.player_hud;var use=game.world_item_use;var view=game.tool_view.human
	hud.survival_active=func()->bool:return false
	check(hud.inventory.grant_items(PackedInt64Array([214,2,218,3]),hud.inventory.snapshot().revision).ok,"real native inventory receives book and food fixture")
	hud.refresh();hud.equip_item(214);await until(func():return view.action_remaining<=0)
	check(view.held_item.visible and view.held_item.mesh==view.HeldItem.MESHES[214],"ordinary belt selection displays the actual book in the hand")
	var xp:int=hud.progression.snapshot().xp;var before:PackedByteArray=hud.inventory.capture_storage_snapshot()
	mouse(true);mouse(false)
	check(not use.pending.is_empty() and view.active_clip=="FP_Item_Use","left mouse starts the held book gesture")
	check(not use.begin() and hud.inventory.capture_storage_snapshot()==before and hud.progression.snapshot().xp==xp,"gesture cannot restart or grant an early read")
	await until(func():return view.animation_player.current_animation_position>.55)
	check(count_item(214)==2 and hud.progression.snapshot().xp==xp,"book stays owned while the visible use is playing")
	await capture("book-use")
	check(await until(func():return use.pending.is_empty()) and count_item(214)==1 and hud.progression.snapshot().xp==xp+25,"one completed gesture performs one existing native reading transaction")
	check(view.held_item.visible and view.current==214,"remaining book stays visibly held after native stack refresh")
	mouse(true);mouse(false)
	check(await until(func():return use.pending.is_empty()) and count_item(214)==0 and hud.progression.snapshot().xp==xp+50,"second click reads exactly the last book")
	check(not view.held_item.visible and game.equipped_tool==0,"consuming the last book restores the empty hand")
	# Fill once through the unchanged native UI API, then test world refusal/use.
	hud.survival.advance(600000);hud.equip_item(218)
	check(hud.use_item(hud.active_slot,hud.inventory.snapshot().revision),"native fixture fills food before full-food refusal")
	await until(func():return view.action_remaining<=0);before=hud.inventory.capture_storage_snapshot()
	mouse(true);mouse(false)
	check(use.pending.is_empty() and before==hud.inventory.capture_storage_snapshot() and view.active_clip!="FP_Item_Use","full-food refusal keeps the ration and skips the gesture")
	hud.survival.advance(720000);var food:int=hud.survival.snapshot().food_ms;var rations:=count_item(218)
	mouse(true);mouse(false)
	check(not use.pending.is_empty() and hud.survival.snapshot().food_ms==food,"food gesture starts without an early native consumption")
	check(await until(func():return use.pending.is_empty()) and count_item(218)==rations-1 and hud.survival.snapshot().food_ms==hud.survival.snapshot().food_max_ms,"one completed food gesture consumes one ration and restores food")
	await capture("food-held")
	hud.survival.advance(360000)
	for reason in ["equipment","inventory","focus","ownership"]:
		hud.equip_item(218);game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		await until(func():return view.action_remaining<=0)
		var saved:PackedByteArray=hud.survival.capture_storage_snapshot();var owned:=count_item(218)
		check(use.begin(),"cancellable native item-use starts: "+reason)
		match reason:
			"equipment":hud.equip_item(1)
			"inventory":hud.set_open(true);hud.set_open(false)
			"focus":game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT);game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
			"ownership":check(hud.inventory.transfer(hud.active_slot,31,1,hud.inventory.snapshot().revision).ok,"native slot ownership changes during use")
		check(await until(func():return use.pending.is_empty()) and saved==hud.survival.capture_storage_snapshot() and owned==count_item(218),"cancelled gesture changes no food/reading state: "+reason)
		if reason=="ownership":hud.inventory.transfer(31,hud.active_slot,1,hud.inventory.snapshot().revision)
	await finish()
func finish()->void:
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"temporary native world shuts down without writing user saves")
	game.free();await process_frame;await process_frame
	FileAccess.open(folder+"/checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Real belt meshes, mouse-triggered baseline gesture, existing native book/food transactions and cancellation; no user saves or revised-animation approval."},"  ")+"\n")
	print("ITEM_HOLD_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
