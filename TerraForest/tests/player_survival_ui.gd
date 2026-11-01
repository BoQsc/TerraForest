# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true);run.call_deferred()
func run()->void:
	var hud=preload("res://addons/player_runtime/player_hud.gd").new();root.add_child(hud)
	var changed:=[0];hud.survival_changed.connect(func():changed[0]+=1)
	hud.inventory.grant_items(PackedInt64Array([214,2,215,1,216,1,217,1,218,1,219,1]),hud.inventory.snapshot().revision);hud.refresh();hud.set_open(true)
	var slots:Dictionary={}
	for index in 32:
		var row:Dictionary=hud.inventory.snapshot().slots[index]
		if row.item>=214 and row.item<=219:slots[row.item]=index
	var double:=InputEventMouseButton.new();double.button_index=MOUSE_BUTTON_LEFT;double.pressed=true;double.double_click=true
	check(hud.item_input(slots[214],double) and hud.progression.snapshot().xp==25 and hud.survival.snapshot().readings[214]==1,"double-click uses one carried book through native transaction")
	var right:=InputEventMouseButton.new();right.button_index=MOUSE_BUTTON_RIGHT;right.pressed=true
	check(hud.item_input(slots[215],right) and hud.item_context.visible,"right click exposes Use only for a usable carried item")
	hud.item_context.id_pressed.emit(0);hud.item_context.hide()
	check(hud.progression.snapshot().xp==35 and hud.survival.snapshot().readings[215]==1,"context Use consumes letter and grants its mild experience")
	hud.item_input(slots[214],right);var old:PackedByteArray=hud.survival.capture_storage_snapshot()
	hud.inventory.transfer(slots[214],31,1,hud.inventory.snapshot().revision);hud.item_context.id_pressed.emit(0);hud.item_context.hide()
	check(hud.survival.capture_storage_snapshot()==old and hud.progression.snapshot().xp==35,"stale context action cannot consume a replacement stack")
	hud.refresh();hud.equip_inventory(slots[216]);var active:int=hud.active_slot
	check(hud.use_item(active,hud.inventory.snapshot().revision) and hud.survival.snapshot().effects.has(2) and hud.progression.snapshot().xp==50,"held-slot use shares the same native reading/effect transaction")
	hud.show_side("Journal")
	check(hud.journal_panel.visible and hud.journal_panel.choices.item_count==3 and "Survey" in hud.journal_panel.choices.get_item_text(2),"read entries appear in persistent Journal UI")
	hud.survival.advance(720000)
	check(hud.use_item(slots[217],hud.inventory.snapshot().revision) and hud.survival.snapshot().food_ms==3600000 and hud.skill_damage(1,100)==105,"actual food use restores food and applies native damage buff")
	var before:PackedByteArray=hud.inventory.capture_storage_snapshot()
	check(not hud.use_item(slots[218],hud.inventory.snapshot().revision) and hud.inventory.capture_storage_snapshot()==before,"full-food refusal leaves the ration intact")
	hud.survival_active=func()->bool:return false
	var saved:PackedByteArray=hud.survival.capture_storage_snapshot();hud.tick_survival()
	check(hud.survival.capture_storage_snapshot()==saved,"inactive/paused player time does not drain food or buffs")
	hud.survival_active=func()->bool:return true
	hud.set_open(false);hud.tick_survival()
	check(hud.survival.snapshot().food_ms==3599000 and hud.survival_status.visible and "Well fed" in hud.survival_status.text,"one-second active tick updates bounded condition UI")
	check(changed[0]>=5,"use and active-time changes mark compound state dirty")
	var icons=preload("res://addons/player_runtime/item_icons.gd")
	for identity in range(214,220):
		check(icons.texture(identity)!=null and load("res://addons/player_runtime/art/drops/%d.res"%identity) is ArrayMesh,"item %d has a baked 3D icon and world drop"%identity)
	check(hud.slots.size()==22 and hud.belt.size()==10,"backpack still excludes belt slots")
	var merchant=preload("res://addons/player_runtime/trader_inventory.gd").new()
	var trade=preload("res://addons/player_runtime/trader_panel.gd").new();root.add_child(trade)
	hud.inventory.grant(601,10,hud.inventory.snapshot().revision)
	check(trade.open_for(merchant,hud.inventory,func()->bool:return true),"food trader UI opens against actual native stock")
	trade.rows.select(trade.rows.item_count-1);trade.exchange(true)
	await process_frame;await process_frame
	check(trade.notice.text=="Bought 1 item(s)." and trade.rows.get_v_scroll_bar().value>0,"buying lower-list food keeps the selected offer visible after refresh")
	trade.free()
	hud.free();print("PLAYER_SURVIVAL_UI ",JSON.stringify({"checks":checks,"failures":failures}));quit(1 if failures else 0)
