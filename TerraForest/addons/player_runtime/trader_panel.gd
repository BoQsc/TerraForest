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
	panel.position = Vector2(460, 145)
	panel.custom_minimum_size = Vector2(1000, 730)
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
		var button:=Button.new();button.text=mode;button.custom_minimum_size=Vector2(200,44);modes.add_child(button)
		button.pressed.connect(func():select_mode(mode))
	quest_panel=VBoxContainer.new();column.add_child(quest_panel)
	quest_text=Label.new();quest_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;quest_text.custom_minimum_size=Vector2(940,220);quest_panel.add_child(quest_text)
	quest_offers=ItemList.new();quest_offers.custom_minimum_size=Vector2(940,200);quest_offers.add_theme_font_size_override("font_size",21);quest_panel.add_child(quest_offers)
	quest_button=Button.new();quest_button.custom_minimum_size.y=48;quest_button.pressed.connect(quest_action);quest_panel.add_child(quest_button)
	quest_abandon=Button.new();quest_abandon.text="Abandon quest · keep current world changes";quest_abandon.custom_minimum_size.y=44;quest_abandon.pressed.connect(abandon_quest);quest_panel.add_child(quest_abandon)
	trade_panel=VBoxContainer.new();column.add_child(trade_panel);column=trade_panel
	balance = Label.new(); column.add_child(balance)
	var welcome := Label.new()
	welcome.text = "Welcome. I buy resources and sell building supplies, food and reading material.\nStock and coins are finite. Prices below are per item."
	column.add_child(welcome)
	rows = ItemList.new(); rows.custom_minimum_size = Vector2(940, 250)
	rows.add_theme_font_size_override("font_size", 21)
	column.add_child(rows)
	var buttons := HBoxContainer.new(); column.add_child(buttons)
	quantity = SpinBox.new(); quantity.min_value = 1; quantity.max_value = 999; quantity.value = 1
	buttons.add_child(quantity)
	for buying in [true, false]:
		var button := Button.new(); button.text = "Buy" if buying else "Sell"
		button.custom_minimum_size.x = 180; button.pressed.connect(exchange.bind(buying)); buttons.add_child(button)
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
	opened = true; panel.show(); refresh(); select_mode("Quests" if is_instance_valid(quests) and quests.store.snapshot().introduction>0 else "Trade"); return true

func select_mode(mode:String)->void:
	trade_panel.visible=mode=="Trade";quest_panel.visible=mode=="Quests"
	refresh_quests()
	if trade_panel.visible:rows.grab_focus()
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
				quest_offers.add_item("%s · %d coins · %d XP"%[offer.title,offer.coins,offer.xp])
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
	rows.clear()
	player_revision = inventory.snapshot().revision; stock_revision = trader.stock.snapshot().revision
	balance.text = "Your coins: %d     Trader coins: %d" % [Trade.count(inventory, Trade.CURRENCY), Trade.count(trader.stock, Trade.CURRENCY)]
	for id: int in Trade.GOODS:
		var offer: Array = Trade.GOODS[id]
		rows.add_item("%-12s   Buy %d / Sell %d     Stock %d     Yours %d" % [offer[0], offer[1], offer[2], Trade.count(trader.stock, id), Trade.count(inventory, id)])
		rows.set_item_metadata(rows.item_count - 1, id)
	rows.select(selected[0] if not selected.is_empty() else 0)
	rows.ensure_current_is_visible()
	notice.text = "Choose an item and quantity, then Buy or Sell."
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

func exchange(buying: bool) -> void:
	if not opened: return
	if not permitted.is_valid() or not permitted.call(): close(); return
	var selected := rows.get_selected_items()
	if selected.is_empty(): return
	quantity.apply()
	var response: Dictionary = trader.exchange(inventory, rows.get_item_metadata(selected[0]), int(quantity.value), buying, player_revision, stock_revision)
	refresh()
	if response.ok:
		notice.text = "Bought %d item(s)." % int(quantity.value) if buying else "Sold %d item(s)." % int(quantity.value)
		traded.emit()
	else:
		var messages := {"stale_revision":"Stock or inventory changed. Review the refreshed offer.", "insufficient_items":"You do not have enough coins or goods.", "full":"Your backpack is full.", "peer_rejected":"The trader lacks stock, coins, or storage space.", "invalid_offer":"Choose an available item and quantity from 1 to 999."}
		notice.text = messages.get(response.reason, "The exchange could not be completed. No items or coins changed.")

func close() -> void:
	if not opened: return
	opened = false; panel.hide(); closed.emit()

func _input(event: InputEvent) -> void:
	if opened and event is InputEventKey and event.pressed and event.physical_keycode in [KEY_ESCAPE, KEY_E, KEY_TAB]:
		close(); get_viewport().set_input_as_handled()
