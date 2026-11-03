# SPDX-License-Identifier: 0BSD
extends SceneTree
const Trade=preload("res://addons/player_runtime/trader_inventory.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	run.call_deferred()
func row_for(list,item:int)->int:
	for row in list.item_count:
		if int(list.get_item_metadata(row))==item:return row
	return -1
func run()->void:
	var hud=preload("res://addons/player_runtime/player_hud.gd").new()
	root.add_child(hud)
	hud.inventory_open=true;hud.enabled=false
	var player:RefCounted=hud.inventory
	var trader=Trade.new()
	var ui=preload("res://addons/player_runtime/trader_panel.gd").new()
	root.add_child(ui);ui.hud=hud
	ui.closed.connect(func():hud.inventory_open=false;hud.enabled=true;hud.refresh())
	check(ui.open_for(trader,player,func():return true),"two-list shop opens")
	check(ui.choice_panel.visible and ui.choice_quest.visible and ui.choice_trade.visible and not ui.trade_panel.visible and not ui.quest_panel.visible,"E opens the Quests/Trading choice first")
	ui.select_mode("Trade")
	check(ui.trade_panel.visible and not ui.choice_panel.visible,"Trading opens from the choice screen")
	check(ui.backdrop.mouse_filter==Control.MOUSE_FILTER_IGNORE,"trade backdrop leaves toolbar input reachable")
	hud.equip_inventory(1)
	check(hud.active_slot==1,"toolbar selection remains functional while trading")
	check(hud.layer==hud.DRAG_LAYER and hud.layer>ui.layer,"toolbar HUD is above the trader UI while trading")
	hud.raise_drag_layer()
	check(hud.layer==hud.DRAG_LAYER and hud.layer>ui.layer,"toolbelt drag preview is raised above the trader UI")
	hud.restore_drag_layer()
	check(hud.layer==hud.DRAG_LAYER,"toolbar remains above the trader UI after drag")
	check(ui.rows.item_count==Trade.GOODS.size(),"every market item type is listed even with no stock")
	check(int(ui.rows.get_item_metadata(0))==101,"existing listing order remains stable")
	var ranger:=row_for(ui.rows,8)
	check(ranger>=0 and ui.rows.get_item_text(ranger)=="Ranger assault rifle","zero-stock weapon remains visible")
	var shown:=true
	for id:int in Trade.GOODS:shown=shown and (Trade.price(id,true)>0 and Trade.price(id,false)>0 and Trade.name_of(id)!="Item %d"%id)
	check(shown,"every item type has a name and both prices")
	var player_rows:=0
	for id:int in [1,2,3,4,401]:player_rows+=int(row_for(ui.selling,id)>=0)
	check(player_rows==5,"all owned toolbelt and bucket types appear in Your items")
	check(ui.rows.get_item_metadata(ui.rows.item_count-1)==501,"newly appended item types are not hidden")
	await process_frame
	await process_frame
	ui.rows.get_v_scroll_bar().value=120
	var stock_scroll:float=ui.rows.get_v_scroll_bar().value
	var coins:=Trade.count(player,Trade.CURRENCY)
	var stock_tool:=Trade.count(trader.stock,1)
	var sale:Dictionary=hud.drag_data("player",0)
	check(not sale.is_empty() and ui.accepts_belt_drop("merchant",sale),"toolbelt tool is accepted by Trader stock")
	check(hud.accepts_drag("player",1,sale),"toolbar remains a drop target while trading")
	ui.drop_belt("merchant",sale)
	await process_frame
	await process_frame
	check(absf(ui.rows.get_v_scroll_bar().value-stock_scroll)<1.0,"sale preserves trader stock scroll")
	check(Trade.count(player,1)==0 and Trade.count(trader.stock,1)==stock_tool+1 and Trade.count(player,Trade.CURRENCY)==coins+Trade.price(1,false),"toolbelt tool sells with its quote and reaches finite stock")
	var move:Dictionary=hud.drag_data("player",1)
	check(not move.is_empty() and ui.accepts_belt_drop("player",move),"toolbelt item is accepted by Your items")
	ui.drop_belt("player",move)
	var in_backpack:=false
	for index in range(10,32):
		if int(player.snapshot().slots[index].item)==2:in_backpack=true
	check(in_backpack and int(player.snapshot().slots[1].count)==0 and Trade.count(player,2)==1,"toolbelt drag moves the stack into the backpack")
	player.grant(Trade.CURRENCY,100,player.snapshot().revision)
	ui.refresh()
	var buy_row:=row_for(ui.rows,1)
	ui.rows.select(buy_row)
	var before_buy:=Trade.count(player,Trade.CURRENCY)
	ui.exchange(true)
	check(Trade.count(player,1)==1 and Trade.count(trader.stock,1)==stock_tool and Trade.count(player,Trade.CURRENCY)==before_buy-Trade.price(1,true),"tool can be bought back from finite stock")
	var tab_event:=InputEventKey.new();tab_event.physical_keycode=KEY_TAB;tab_event.pressed=true
	ui._input(tab_event)
	check(not ui.opened and not hud.inventory_open and not hud.modal.visible,"Tab closes trader without opening backpack")
	check(hud.layer==hud.UI_LAYER,"toolbar returns below the trader UI after close")
	ui.free();hud.free();await process_frame
	print("TRADE_ALL_ITEMS checks=",checks," failures=",failures);quit(1 if failures else 0)