# SPDX-License-Identifier: 0BSD
extends CanvasLayer
const Trade = preload("res://addons/player_runtime/trader_inventory.gd")
signal closed
signal traded
var trader: RefCounted
var inventory: RefCounted
var permitted: Callable
var panel: PanelContainer
var rows: ItemList
var selling:ItemList
var search:LineEdit
var buy_button:Button
var sell_button:Button
var selection_info:Label
var session_token:=0
var mode_buttons:Dictionary={}
var quantity: SpinBox
var balance: Label
var notice: Label
var player_revision := -1
var stock_revision := -1
var opened := false
var ride: Node
var towns: OptionButton
var reserve: Button
var cancel: Button
var travel_info: Label
var quests:Node
var trade_panel:VBoxContainer
var quest_panel:VBoxContainer
var quest_text:Label
var quest_button:Button
var quest_error:=""
var quest_offers:ItemList
var quest_abandon:Button
var offer_keys:=PackedInt64Array()

func _ready() -> void:
	layer = 30
	panel = PanelContainer.new()
	panel.position = Vector2(370, 90)
	panel.custom_minimum_size = Vector2(1180, 810)
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17252b")
	for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 24)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 15)
	panel.add_child(column)
	var header:=HBoxContainer.new();column.add_child(header)
	var title := Label.new();title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.text = "TRADER / GENERAL SUPPLIES"
	title.add_theme_font_size_override("font_size", 28)
	header.add_child(title)
	var dismiss:=Button.new();dismiss.text="X";dismiss.custom_minimum_size=Vector2(44,44);dismiss.pressed.connect(close);header.add_child(dismiss)
	var modes:=HBoxContainer.new();column.add_child(modes)
	for mode:String in ["Quests","Trade"]:
		var button:=Button.new();button.text=mode;button.toggle_mode=true;mode_buttons[mode]=button;button.custom_minimum_size=Vector2(200,44);modes.add_child(button)
		button.pressed.connect(func():select_mode(mode))
	quest_panel=VBoxContainer.new();column.add_child(quest_panel)
	quest_text=Label.new();quest_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;quest_text.custom_minimum_size=Vector2(1120,220);quest_panel.add_child(quest_text)
	quest_offers=ItemList.new();quest_offers.custom_minimum_size=Vector2(1120,200);quest_offers.add_theme_font_size_override("font_size",21);quest_panel.add_child(quest_offers)
	quest_button=Button.new();quest_button.custom_minimum_size.y=48;quest_button.pressed.connect(quest_action);quest_panel.add_child(quest_button)
	quest_abandon=Button.new();quest_abandon.text="Abandon quest · keep current world changes";quest_abandon.custom_minimum_size.y=44;quest_abandon.pressed.connect(abandon_quest);quest_panel.add_child(quest_abandon)
	trade_panel=VBoxContainer.new();column.add_child(trade_panel);column=trade_panel
	balance = Label.new(); column.add_child(balance)
	var welcome := Label.new()
	welcome.text = "Drag an item across to buy or sell. Quantity applies to each trade. Prices are per item; coins and stock are finite."
	column.add_child(welcome)
	search=LineEdit.new();search.placeholder_text="Search supplies, food, salvage…";search.text_changed.connect(func(_value:String):refresh());column.add_child(search)
	var listings:=HBoxContainer.new();listings.add_theme_constant_override("separation",20);column.add_child(listings)
	for side:String in ["merchant","player"]:
		var section:=VBoxContainer.new();section.size_flags_horizontal=Control.SIZE_EXPAND_FILL;listings.add_child(section)
		var heading:=Label.new();heading.text="TRADER STOCK · drag here to sell" if side=="merchant" else "YOUR ITEMS · drag here to buy";heading.add_theme_color_override("font_color",Color("9cffe0"));section.add_child(heading)
		var listing:=preload("res://addons/player_runtime/trade_list.gd").new();listing.trade=self;listing.side=side
		listing.custom_minimum_size=Vector2(550,290);listing.add_theme_font_size_override("font_size",18);listing.fixed_icon_size=Vector2i(42,42);listing.item_selected.connect(func(_index:int):_selection_changed());section.add_child(listing)
		if side=="merchant":rows=listing
		else:selling=listing
	selection_info=Label.new();selection_info.text="Select a listing to see the total.";column.add_child(selection_info)
	var buttons := HBoxContainer.new();buttons.add_theme_constant_override("separation",12);column.add_child(buttons)
	var amount_label:=Label.new();amount_label.text="Quantity";buttons.add_child(amount_label)
	quantity = SpinBox.new(); quantity.min_value = 1; quantity.max_value = 999; quantity.value = 1;quantity.custom_minimum_size.x=110
	quantity.value_changed.connect(func(_value:float):_selection_changed());buttons.add_child(quantity)
	buy_button=Button.new();buy_button.text="Buy selected";buy_button.custom_minimum_size.x=240;buy_button.pressed.connect(_trade_selected.bind(true));buttons.add_child(buy_button)
	sell_button=Button.new();sell_button.text="Sell selected";sell_button.custom_minimum_size.x=240;sell_button.pressed.connect(_trade_selected.bind(false));buttons.add_child(sell_button)
	var close_button := Button.new(); close_button.text = "Close / Esc"
	close_button.pressed.connect(close); buttons.add_child(close_button)
	var travel := HBoxContainer.new(); column.add_child(travel)
	towns = OptionButton.new(); towns.custom_minimum_size.x = 500; travel.add_child(towns)
	towns.item_selected.connect(func(_index: int): _travel_quote())
	reserve = Button.new(); reserve.text = "Reserve ride"; reserve.pressed.connect(_reserve); travel.add_child(reserve)
	cancel = Button.new(); cancel.text = "Cancel reservation"; cancel.pressed.connect(_cancel); travel.add_child(cancel)
	travel_info = Label.new(); travel_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(travel_info)
	notice = Label.new(); notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(notice)
	panel.hide()

func open_for(merchant: RefCounted, player_inventory: RefCounted, reach_check: Callable) -> bool:
	if not reach_check.is_valid() or not reach_check.call(): return false
	trader = merchant; inventory = player_inventory; permitted = reach_check
	quest_error=""
	offer_keys=PackedInt64Array();quest_offers.clear()
	session_token+=1;search.text="";opened = true; panel.show(); refresh(); select_mode("Quests" if is_instance_valid(quests) and quests.store.snapshot().introduction>0 else "Trade"); return true

func select_mode(mode:String)->void:
	trade_panel.visible=mode=="Trade";quest_panel.visible=mode=="Quests"
	for key in mode_buttons:mode_buttons[key].set_pressed_no_signal(key==mode)
	refresh_quests()
	if trade_panel.visible:rows.grab_focus();rows.call_deferred("ensure_current_is_visible")
	else:quest_button.grab_focus()

func refresh_quests()->void:
	if not is_instance_valid(quests):return
	var state:Dictionary=quests.store.snapshot()
	quest_text.text=quests.description()+("\n\n"+quest_error if not quest_error.is_empty() else "")
	var repeatable:bool=state.phase==0 and state.introduction not in [1,2,3]
	quest_offers.visible=repeatable
	quest_abandon.visible=state.phase in [1,3] and state.introduction!=3
	quest_button.visible=state.phase==4 or state.introduction in [2,3] or repeatable
	var needs_car:bool=state.phase!=4 and state.introduction in [2,3]
	var loading_car:bool=needs_car and is_instance_valid(ride) and not ride.game.world_vehicle.scene_ready()
	quest_button.disabled=loading_car or (needs_car and is_instance_valid(ride) and ride.active())
	quest_button.text="Collect reward" if state.phase==4 else "Accept expedition · supplies & free ride" if state.introduction==2 else "Return to the coal mine · free ride" if state.introduction==3 else "Accept selected quest"
	if loading_car:quest_button.text="Preparing the trader's car…"
	if repeatable:
		var offers:Array=quests.offers()
		var keys:=PackedInt64Array()
		for offer:Dictionary in offers:keys.append(offer.key)
		if keys!=offer_keys:
			var selected:=quest_offers.get_selected_items()
			var selected_key:int=quest_offers.get_item_metadata(selected[0]) if not selected.is_empty() else 0
			offer_keys=keys;quest_offers.clear()
			for offer:Dictionary in offers:
				var offset:Vector3=offer.marker-quests.game.player.global_position
				var distance:=Vector2(offset.x,offset.z).length()
				var bearing:String=["N","NE","E","SE","S","SW","W","NW"][posmod(roundi(atan2(offset.x,-offset.z)/(PI/4)),8)]
				var range_text:="%.1f km"%(distance/1000) if distance>=1000 else "%.0f m"%distance
				quest_offers.add_item("%s · %s %s · %d coins · %d XP"%[offer.title,range_text,bearing,offer.coins,offer.xp])
				quest_offers.set_item_tooltip(quest_offers.item_count-1,"%s\nMap coordinates: %.0f, %.0f"%[offer.title,offer.marker.x,offer.marker.z])
				quest_offers.set_item_metadata(quest_offers.item_count-1,offer.key)
				if offer.key==selected_key:quest_offers.select(quest_offers.item_count-1)
			if quest_offers.item_count>0 and quest_offers.get_selected_items().is_empty():quest_offers.select(0)
		quest_button.disabled=quest_offers.item_count==0
		quest_text.text+="\n\nAccept here, then start at the question mark outside the location. Starting replaces changes inside that location; it does not reset the world." if not offers.is_empty() else "\n\nNo repeatable locations with preserved generation originals are available in this world."

func quest_action()->void:
	if not opened or not is_instance_valid(quests):return
	if not permitted.is_valid() or not permitted.call():close();return
	quest_error=""
	var state:Dictionary=quests.store.snapshot()
	var result:Dictionary
	if state.phase==4:result=quests.claim()
	elif state.introduction in [2,3]:result=quests.start_expedition()
	else:
		var selected:=quest_offers.get_selected_items()
		if selected.is_empty():return
		result=quests.accept(quest_offers.get_item_metadata(selected[0]))
	if not result.ok:quest_error=str(result.reason)
	refresh_quests()

func abandon_quest()->void:
	if not opened or not is_instance_valid(quests):return
	if not permitted.is_valid() or not permitted.call():close();return
	var result:Dictionary=quests.abandon()
	quest_error="" if result.ok else str(result.reason)
	refresh_quests()

func refresh() -> void:
	var selected := rows.get_selected_items()
	var selected_id:int=rows.get_item_metadata(selected[0]) if not selected.is_empty() else 0
	var player_selected:=selling.get_selected_items()
	var player_id:int=selling.get_item_metadata(player_selected[0]) if not player_selected.is_empty() else 0
	rows.clear();selling.clear()
	player_revision = inventory.snapshot().revision; stock_revision = trader.stock.snapshot().revision
	balance.text = "YOUR PURSE  %d coins                                      TRADER'S PURSE  %d coins" % [Trade.count(inventory, Trade.CURRENCY), Trade.count(trader.stock, Trade.CURRENCY)]
	for id: int in Trade.GOODS:
		var offer: Array = Trade.GOODS[id]
		if not search.text.strip_edges().is_empty() and not str(offer[0]).to_lower().contains(search.text.strip_edges().to_lower()):continue
		var available:int=Trade.count(trader.stock,id);var owned:int=Trade.count(inventory,id)
		var icon:Texture2D=preload("res://addons/player_runtime/item_icons.gd").texture(id)
		rows.add_item("%s    ·    %d coins    ·    Stock %d"%[offer[0],offer[1],available],icon)
		var index:=rows.item_count-1;rows.set_item_metadata(index,id)
		rows.set_item_tooltip(index,"Buy %s · %d coins each · stock %d"%[offer[0],offer[1],available])
		if available==0:rows.set_item_custom_fg_color(index,Color("7b8d92"))
		if id==selected_id:rows.select(index)
		if owned>0:
			selling.add_item("%s    ·    %d coins    ·    You have %d"%[offer[0],offer[2],owned],icon)
			selling.set_item_metadata(selling.item_count-1,id)
			if id==player_id:selling.select(selling.item_count-1)
	if rows.item_count>0 and rows.get_selected_items().is_empty():rows.select(0)
	if selling.item_count>0 and selling.get_selected_items().is_empty():selling.select(0)
	rows.ensure_current_is_visible();selling.ensure_current_is_visible()
	rows.call_deferred("ensure_current_is_visible");selling.call_deferred("ensure_current_is_visible")
	notice.text = "Drag trader stock to Your items to buy; drag your items to Trader stock to sell."
	_selection_changed()
	_refresh_travel()

func _refresh_travel() -> void:
	towns.clear()
	if is_instance_valid(ride):
		for offer: Dictionary in ride.destinations():
			towns.add_item("%s · %d coins" % [offer.title, offer.fare])
			towns.set_item_metadata(towns.item_count - 1, offer)
	if towns.item_count > 0: towns.select(0)
	reserve.disabled = towns.item_count == 0
	cancel.visible = is_instance_valid(ride) and ride.state.phase == ride.BOARDING
	_travel_quote()

func _travel_quote() -> void:
	if towns.item_count == 0:
		travel_info.text = "The trader is already attending a ride." if is_instance_valid(ride) and ride.active() else "No connected town road and return route are available here."
		return
	var offer: Dictionary = towns.get_item_metadata(towns.selected)
	travel_info.text = "Road ride: %.1f km · %d coins, charged when you board.\nFollow the trader to the car. At your destination, get out and the trader drives home." % [offer.distance_m / 1000.0, offer.fare]

func _reserve() -> void:
	if not opened or not is_instance_valid(ride) or towns.selected < 0: return
	var offer: Dictionary = towns.get_item_metadata(towns.selected)
	var result: Dictionary = ride.book(offer.id, offer.revision)
	if not result.ok: _refresh_travel(); notice.text = result.reason

func _cancel() -> void:
	if not opened or not is_instance_valid(ride): return
	var message: String = ride.cancel_reservation()
	_refresh_travel(); notice.text = message

func _selection_changed()->void:
	if quantity==null:return
	var amount:=int(quantity.value)
	var buy:=rows.get_selected_items();var sell:=selling.get_selected_items()
	buy_button.disabled=buy.is_empty();sell_button.disabled=sell.is_empty()
	var summaries:=PackedStringArray()
	if not buy.is_empty():
		var id:int=rows.get_item_metadata(buy[0]);var price:int=Trade.GOODS[id][1]*amount
		buy_button.text="Buy %d · %d coins"%[amount,price]
		buy_button.disabled=Trade.count(trader.stock,id)<amount or Trade.count(inventory,Trade.CURRENCY)<price
		summaries.append("Buy: %s"%Trade.GOODS[id][0])
	if not sell.is_empty():
		var id:int=selling.get_item_metadata(sell[0]);var price:int=Trade.GOODS[id][2]*amount
		sell_button.text="Sell %d · %d coins"%[amount,price]
		sell_button.disabled=Trade.count(inventory,id)<amount or Trade.count(trader.stock,Trade.CURRENCY)<price
		summaries.append("Sell: %s"%Trade.GOODS[id][0])
	selection_info.text="    /    ".join(summaries) if not summaries.is_empty() else "No matching listings."

func drag_offer(side:String,index:int)->Dictionary:
	if not opened or side not in ["merchant","player"]:return {}
	var listing:ItemList=rows if side=="merchant" else selling
	if index<0 or index>=listing.item_count:return {}
	quantity.apply()
	var id:int=listing.get_item_metadata(index)
	return {"owner":get_instance_id(),"session":session_token,"side":side,"item":id,"quantity":int(quantity.value),"player_revision":player_revision,"stock_revision":stock_revision}

func drag_caption(data:Dictionary)->String:
	var buying:bool=data.side=="merchant"
	return "%s %d × %s · %d coins"%["Buy" if buying else "Sell",data.quantity,Trade.GOODS[data.item][0],Trade.GOODS[data.item][1 if buying else 2]*data.quantity]

func accepts_offer(side:String,data:Variant)->bool:
	return opened and side in ["merchant","player"] and data is Dictionary and data.get("owner",0)==get_instance_id() and data.get("session",-1)==session_token and data.get("side","") in ["merchant","player"] and data.side!=side and Trade.GOODS.has(data.get("item",0)) and data.get("quantity",0) is int and data.quantity>0 and data.quantity<=999 and data.get("player_revision") is int and data.get("stock_revision") is int

func drop_offer(side:String,data:Variant)->void:
	if not accepts_offer(side,data):return
	_commit(data.item,data.quantity,data.side=="merchant",data.player_revision,data.stock_revision)

func _trade_selected(buying:bool)->void:
	var listing:ItemList=rows if buying else selling
	var selected:=listing.get_selected_items()
	if selected.is_empty():return
	quantity.apply()
	_commit(listing.get_item_metadata(selected[0]),int(quantity.value),buying,player_revision,stock_revision)

func exchange(buying: bool) -> void:
	# Existing callers can still transact the selected merchant listing.
	var selected:=rows.get_selected_items()
	if selected.is_empty():return
	quantity.apply()
	_commit(rows.get_item_metadata(selected[0]),int(quantity.value),buying,player_revision,stock_revision)

func _commit(item:int,amount:int,buying:bool,expected_player:int,expected_stock:int)->void:
	if not opened:return
	if not permitted.is_valid() or not permitted.call():close();return
	var response:Dictionary=trader.exchange(inventory,item,amount,buying,expected_player,expected_stock)
	refresh()
	if response.ok:
		notice.text="%s %d × %s · %d coins"%["Bought" if buying else "Sold",amount,Trade.GOODS[item][0],Trade.GOODS[item][1 if buying else 2]*amount]
		traded.emit()
	else:
		var messages:={"stale_revision":"Stock or inventory changed. Review the refreshed offer.","insufficient_items":"You do not have enough coins or goods.","full":"Your backpack is full.","peer_rejected":"The trader lacks stock, coins, or storage space.","invalid_offer":"Choose an available item and quantity from 1 to 999."}
		notice.text=messages.get(response.reason,"The exchange could not be completed. No items or coins changed.")

func close() -> void:
	if not opened: return
	opened = false; panel.hide(); closed.emit()

func _input(event: InputEvent) -> void:
	if opened and event is InputEventKey and event.pressed and get_viewport().gui_get_focus_owner() is LineEdit and event.physical_keycode!=KEY_ESCAPE:return
	if opened and event is InputEventKey and event.pressed and event.physical_keycode in [KEY_ESCAPE, KEY_E, KEY_TAB]:
		close(); get_viewport().set_input_as_handled()
