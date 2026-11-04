# SPDX-License-Identifier: 0BSD
extends CanvasLayer
const Trade = preload("res://addons/player_runtime/trader_inventory.gd")
const TextInputFocus = preload("res://addons/player_runtime/text_input_focus.gd")
const Icons = preload("res://addons/player_runtime/item_icons.gd")
const WindowNav = preload("res://addons/player_runtime/window_navigation.gd")
signal closed
signal traded
const INK:=Color("#e9f3ec")
const MUTED:=Color("#91b8ac")
const FAINT:=Color("#5d8a7e")
const GOLD:=Color("#e3bd73")
const GOLD_SOFT:=Color("#b69254")
const MINT:=Color("#7be0bd")
const PANEL:=Color("#0d2524")
const PANEL_DEEP:=Color("#071a19")
const CARD:=Color("#0a2221")
const LINE:=Color("#285149")
var trader: RefCounted
var inventory: RefCounted
var permitted: Callable
var panel: PanelContainer
var backdrop: ColorRect
var brand_root: Control
var rows
var selling
var search:LineEdit
var buy_button:Button
var sell_button:Button
var selection_info:Label
var session_token:=0
var mode_buttons:Dictionary={}
var modes:HBoxContainer
var choice_panel:VBoxContainer
var choice_quest:Button
var choice_trade:Button
var hud:Node
var quantity: SpinBox
var balance: Label
var trader_purse: Label
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
	backdrop=ColorRect.new();backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color=Color(0.005,0.02,0.02,0.72);backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(backdrop);backdrop.hide()
	panel = PanelContainer.new()
	panel.position = Vector2(210, 110)
	panel.custom_minimum_size = Vector2(1500, 860)
	add_child(panel)
	var shell:=_style(PANEL_DEEP,Color("#3a6a5e"),22,1,30);_pad(shell,3)
	panel.add_theme_stylebox_override("panel",shell)
	var inner:=PanelContainer.new()
	var inner_style:=_style(PANEL,Color("#1e403b"),18,1);_pad(inner_style,24)
	inner.add_theme_stylebox_override("panel",inner_style)
	panel.add_child(inner)
	brand_root=Control.new();brand_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	brand_root.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(brand_root);brand_root.hide()
	var outer_brand:=VBoxContainer.new();outer_brand.position=Vector2(188,24);outer_brand.add_theme_constant_override("separation",2)
	outer_brand.mouse_filter=Control.MOUSE_FILTER_IGNORE;brand_root.add_child(outer_brand)
	outer_brand.add_child(_label("TERRAFOREST",16,GOLD))
	outer_brand.add_child(_label("TRADING COUNTER · CIVIC DISTRICT",10,MUTED))
	var live:=Label.new();live.position=Vector2(1370,26);live.size=Vector2(320,28);live.text="TRADING COUNTER / LIVE"
	live.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;live.add_theme_font_size_override("font_size",10)
	live.add_theme_color_override("font_color",FAINT);live.mouse_filter=Control.MOUSE_FILTER_IGNORE;brand_root.add_child(live)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	inner.add_child(column)
	var header:=HBoxContainer.new();header.custom_minimum_size.y=78;column.add_child(header)
	var brand:=VBoxContainer.new();brand.size_flags_horizontal=Control.SIZE_EXPAND_FILL;brand.add_theme_constant_override("separation",0);header.add_child(brand)
	brand.add_child(_label("CIVIC DISTRICT · GENERAL SUPPLIES",11,GOLD))
	brand.add_child(_label("THE TRADING POST",34,INK))
	brand.add_child(_label("A fair counter for supplies, salvage and the road ahead.",12,MUTED))
	var right:=HBoxContainer.new();right.add_theme_constant_override("separation",10);header.add_child(right)
	right.add_child(_purse("YOUR PURSE",true))
	right.add_child(_purse("TRADER'S PURSE",false))
	var dismiss:=_button("X",Color("#0c2421"),Color("#3b6b5e"),MUTED)
	dismiss.custom_minimum_size=Vector2(42,42);dismiss.pressed.connect(close);right.add_child(dismiss)
	column.add_child(_line(GOLD_SOFT,1))
	choice_panel=VBoxContainer.new();choice_panel.add_theme_constant_override("separation",16);column.add_child(choice_panel)
	choice_panel.add_child(_label("WHAT WOULD YOU LIKE TO DO?",11,GOLD))
	var choice_row:=HBoxContainer.new();choice_row.add_theme_constant_override("separation",18);choice_panel.add_child(choice_row)
	choice_quest=_button("QUESTS\nJobs and expeditions",Color("#173f37"),MINT,MINT)
	choice_quest.custom_minimum_size=Vector2(330,120);choice_quest.pressed.connect(func():select_mode("Quests"));choice_row.add_child(choice_quest)
	choice_trade=_button("TRADING\nBuy, sell and move supplies",Color("#3b3320"),GOLD,GOLD)
	choice_trade.custom_minimum_size=Vector2(330,120);choice_trade.pressed.connect(func():select_mode("Trade"));choice_row.add_child(choice_trade)
	choice_panel.add_child(_label("Choose a counter. E, Esc or Tab closes.",11,MUTED))
	modes=HBoxContainer.new();column.add_child(modes)
	for mode:String in ["Quests","Trade"]:
		var button:=_button(mode.to_upper(),Color("#102d2b"),Color("#315d53"),MUTED)
		button.toggle_mode=true;mode_buttons[mode]=button;button.custom_minimum_size=Vector2(180,38);modes.add_child(button)
		button.pressed.connect(func():select_mode(mode))
	quest_panel=VBoxContainer.new();column.add_child(quest_panel)
	quest_panel.add_child(_label("QUESTS",11,GOLD))
	quest_text=_label("",14,INK);quest_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;quest_text.custom_minimum_size=Vector2(1120,220);quest_panel.add_child(quest_text)
	quest_offers=ItemList.new();quest_offers.custom_minimum_size=Vector2(1120,200);_style_list(quest_offers);quest_panel.add_child(quest_offers)
	quest_button=_button("Accept selected quest",Color("#173f37"),MINT,MINT);quest_button.custom_minimum_size.y=48;quest_button.pressed.connect(quest_action);quest_panel.add_child(quest_button)
	quest_abandon=_button("Abandon quest · keep current world changes",Color("#2a1c1c"),Color("#704b48"),Color("#d9aaa0"));quest_abandon.custom_minimum_size.y=44;quest_abandon.pressed.connect(abandon_quest);quest_panel.add_child(quest_abandon)
	trade_panel=VBoxContainer.new();column.add_child(trade_panel);column=trade_panel
	column.add_theme_constant_override("separation",8)
	var welcome:=_label("Drag across to buy or sell. Quantity applies to each trade; stock and coin are finite.",12,MUTED);welcome.visible=false;column.add_child(welcome)
	search=LineEdit.new();TextInputFocus.configure(search);search.placeholder_text="Search supplies, food, salvage…";search.text_changed.connect(func(_value:String):refresh())
	_style_line_edit(search);search.visible=false;column.add_child(search)
	var listings:=HBoxContainer.new();listings.add_theme_constant_override("separation",20);column.add_child(listings)
	for side:String in ["merchant","player"]:
		var card:=PanelContainer.new();card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var card_style:=_style(CARD,LINE,12,1);_pad(card_style,12);card.add_theme_stylebox_override("panel",card_style);listings.add_child(card)
		var section:=VBoxContainer.new();section.add_theme_constant_override("separation",8);card.add_child(section)
		var card_head:=HBoxContainer.new();section.add_child(card_head)
		var card_title:=VBoxContainer.new();card_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;card_title.add_theme_constant_override("separation",0);card_head.add_child(card_title)
		card_title.add_child(_label("TRADER STOCK" if side=="merchant" else "YOUR PACK",11,MINT if side=="merchant" else GOLD))
		card_title.add_child(_label("Finite goods from the counter" if side=="merchant" else "Goods and gear you carry",16,INK))
		card_head.add_child(_badge("BUY" if side=="merchant" else "SELL",MINT if side=="merchant" else GOLD))
		section.add_child(_line(Color(0.18,0.36,0.32,0.65),1))
		var listing:=preload("res://addons/player_runtime/trade_list.gd").new();listing.trade=self;listing.side=side
		listing.custom_minimum_size=Vector2(560,470);listing.focus_mode=Control.FOCUS_ALL;listing.item_selected.connect(func(_index:int):_selection_changed());section.add_child(listing)
		if side=="merchant":rows=listing
		else:selling=listing
		if side=="merchant":listings.add_child(_trade_rail())
	var footer:=PanelContainer.new();var footer_style:=_style(Color("#091d1c"),Color("#2b5148"),12,1,8);_pad(footer_style,10);footer.add_theme_stylebox_override("panel",footer_style);column.add_child(footer)
	var footer_column:=VBoxContainer.new();footer_column.add_theme_constant_override("separation",4);footer.add_child(footer_column)
	selection_info=_label("Select a listing to see the total.",11,MUTED);footer_column.add_child(selection_info)
	var buttons := HBoxContainer.new();buttons.add_theme_constant_override("separation",12);footer_column.add_child(buttons)
	buttons.add_child(_label("QUANTITY",10,FAINT))
	quantity = SpinBox.new(); quantity.min_value = 1; quantity.max_value = 999; quantity.value = 1;quantity.custom_minimum_size.x=110
	quantity.value_changed.connect(func(_value:float):_selection_changed());_style_spin(quantity);buttons.add_child(quantity)
	buy_button=_button("Buy selected",Color("#1d5144"),MINT,MINT);buy_button.custom_minimum_size.x=230;buy_button.pressed.connect(_trade_selected.bind(true));buttons.add_child(buy_button)
	sell_button=_button("Sell selected",Color("#3b3320"),GOLD,GOLD);sell_button.custom_minimum_size.x=230;sell_button.pressed.connect(_trade_selected.bind(false));buttons.add_child(sell_button)
	var travel := HBoxContainer.new(); column.add_child(travel)
	travel.visible=false
	towns = OptionButton.new(); towns.custom_minimum_size.x = 500; _style_option(towns);travel.add_child(towns)
	towns.item_selected.connect(func(_index: int): _travel_quote())
	reserve = _button("Reserve ride",Color("#102d2b"),Color("#315d53"),MUTED); reserve.pressed.connect(_reserve); travel.add_child(reserve)
	cancel = _button("Cancel reservation",Color("#2a1c1c"),Color("#704b48"),Color("#d9aaa0")); cancel.pressed.connect(_cancel); travel.add_child(cancel)
	travel_info=_label("",11,MUTED);travel_info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;travel_info.visible=false;column.add_child(travel_info)
	notice=_label("",11,MINT);notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.visible=false;column.add_child(notice)
	panel.hide()

func open_for(merchant: RefCounted, player_inventory: RefCounted, reach_check: Callable) -> bool:
	if not reach_check.is_valid() or not reach_check.call(): return false
	trader = merchant; inventory = player_inventory; permitted = reach_check
	quest_error=""
	offer_keys=PackedInt64Array();quest_offers.clear()
	session_token+=1;search.text="";opened = true
	if is_instance_valid(hud) and hud.has_method("set_above_ui"):hud.set_above_ui(true)
	backdrop.show();brand_root.show();panel.show(); refresh(); show_choices(); return true

func show_choices()->void:
	choice_panel.show();modes.hide();quest_panel.hide();trade_panel.hide()
	if is_instance_valid(quests):refresh_quests()
	choice_quest.grab_focus()

func select_mode(mode:String)->void:
	if mode not in ["Quests","Trade"]:return
	choice_panel.hide();modes.hide()
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

func refresh(preserve_scroll:=false) -> void:
	var selected:PackedInt32Array=rows.get_selected_items()
	var selected_id:int=rows.get_item_metadata(selected[0]) if not selected.is_empty() else 0
	var player_selected:PackedInt32Array=selling.get_selected_items()
	var player_id:int=selling.get_item_metadata(player_selected[0]) if not player_selected.is_empty() else 0
	var row_scroll:float=rows.get_v_scroll_bar().value
	var sell_scroll:float=selling.get_v_scroll_bar().value
	var player_state:Dictionary=inventory.snapshot()
	var stock_state:Dictionary=trader.stock.snapshot()
	var owned_counts:Dictionary={}
	for row:Dictionary in player_state.slots:
		if int(row.count)>0:owned_counts[int(row.item)]=int(owned_counts.get(int(row.item),0))+int(row.count)
	rows.clear();selling.clear()
	player_revision = player_state.revision; stock_revision = stock_state.revision
	balance.text = "%s coins" % _coin_text(Trade.count(inventory, Trade.CURRENCY))
	trader_purse.text = "%s coins" % _coin_text(Trade.count(trader.stock, Trade.CURRENCY))
	var filter:=search.text.strip_edges().to_lower()
	for id: int in Trade.GOODS:
		var offer: Array = Trade.GOODS[id]
		if not filter.is_empty() and not str(offer[0]).to_lower().contains(filter):continue
		var available:int=Trade.count(trader.stock,id);var owned:int=int(owned_counts.get(id,0))
		var icon:Texture2D=preload("res://addons/player_runtime/item_icons.gd").texture(id)
		rows.add_item(str(offer[0]),icon,_item_detail(id),"%d coins"%offer[1],"STOCK %d"%available)
		var index:int=rows.item_count-1;rows.set_item_metadata(index,id)
		rows.set_item_tooltip(index,"Buy %s · %d coins each · stock %d\nDrag trader stock to YOUR ITEMS to buy."%[offer[0],offer[1],available])
		rows.set_item_custom_fg_color(index,Color("e0ebe8") if available>0 else Color("7b8d92"))
		if id==selected_id:rows.select(index)
		if owned>0:
			selling.add_item(str(offer[0]),icon,_item_detail(id),"%d coins"%offer[2],"YOU HAVE %d"%owned)
			var sell_index:int=selling.item_count-1;selling.set_item_metadata(sell_index,id)
			selling.set_item_tooltip(sell_index,"Sell %s · %d coins each\nDrag to TRADER STOCK to sell, or drag a toolbelt item here to move it to your backpack."%[offer[0],offer[2]])
			if id==player_id:selling.select(sell_index)
	if not preserve_scroll:
		if rows.item_count>0 and rows.get_selected_items().is_empty():rows.select(0)
		if selling.item_count>0 and selling.get_selected_items().is_empty():selling.select(0)
		rows.ensure_current_is_visible();selling.ensure_current_is_visible()
		rows.call_deferred("ensure_current_is_visible");selling.call_deferred("ensure_current_is_visible")
	else:
		_restore_scroll.call_deferred(row_scroll,sell_scroll)
	notice.text = "Drag trader stock to Your items to buy; drag your items to Trader stock to sell. Toolbelt items can be dragged to either side."
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
	var buy:PackedInt32Array=rows.get_selected_items();var sell:PackedInt32Array=selling.get_selected_items()
	var selected_item:=0
	if not buy.is_empty():selected_item=int(rows.get_item_metadata(buy[0]))
	elif not sell.is_empty():selected_item=int(selling.get_item_metadata(sell[0]))
	if Trade.metadata_item(selected_item):
		if int(quantity.max_value)!=1:quantity.max_value=1
		if int(quantity.value)!=1:quantity.set_value_no_signal(1)
	elif int(quantity.max_value)!=999:quantity.max_value=999
	var amount:=int(quantity.value)
	buy_button.disabled=buy.is_empty();sell_button.disabled=sell.is_empty()
	var summaries:=PackedStringArray()
	if not buy.is_empty():
		var id:int=rows.get_item_metadata(buy[0]);var price:int=Trade.price(id,true)*amount
		buy_button.text="BUY %d · %d COINS"%[amount,price]
		buy_button.disabled=Trade.count(trader.stock,id)<amount or Trade.count(inventory,Trade.CURRENCY)<price
		summaries.append("Buy %d × %s · %d coins"%[amount,Trade.name_of(id),price])
	if not sell.is_empty():
		var id:int=selling.get_item_metadata(sell[0]);var price:int=Trade.price(id,false)*amount
		sell_button.text="SELL %d · %d COINS"%[amount,price]
		sell_button.disabled=Trade.count(inventory,id)<amount or Trade.count(trader.stock,Trade.CURRENCY)<price
		summaries.append("Sell %d × %s · %d coins"%[amount,Trade.name_of(id),price])
	if not buy.is_empty():
		var id:int=rows.get_item_metadata(buy[0]);var amount_now:=int(quantity.value)
		selection_info.text="%d × %s\n%d coins total · stock after trade: %d"%[amount_now,Trade.name_of(id),Trade.price(id,true)*amount_now,maxi(0,Trade.count(trader.stock,id)-amount_now)]
	elif not sell.is_empty():
		var id:int=selling.get_item_metadata(sell[0]);var amount_now:=int(quantity.value)
		selection_info.text="%d × %s\n%d coins total · you keep %d"%[amount_now,Trade.name_of(id),Trade.price(id,false)*amount_now,maxi(0,Trade.count(inventory,id)-amount_now)]
	else:
		selection_info.text="Select a listing to see the total."

func drag_offer(side:String,index:int)->Dictionary:
	if not opened or side not in ["merchant","player"]:return {}
	var listing=rows if side=="merchant" else selling
	if index<0 or index>=listing.item_count:return {}
	quantity.apply()
	var id:int=listing.get_item_metadata(index)
	var amount:=1 if Trade.metadata_item(id) else int(quantity.value)
	return {"owner":get_instance_id(),"session":session_token,"side":side,"item":id,"quantity":amount,"player_revision":player_revision,"stock_revision":stock_revision}

func drag_caption(data:Dictionary)->String:
	var buying:bool=data.side=="merchant"
	return "%s %d × %s · %d coins"%["Buy" if buying else "Sell",data.quantity,Trade.name_of(data.item),Trade.price(data.item,buying)*data.quantity]

func accepts_offer(side:String,data:Variant)->bool:
	return opened and side in ["merchant","player"] and data is Dictionary and data.get("owner",0)==get_instance_id() and data.get("session",-1)==session_token and data.get("side","") in ["merchant","player"] and data.side!=side and Trade.GOODS.has(data.get("item",0)) and data.get("quantity",0) is int and data.quantity>0 and data.quantity<=999 and (not Trade.metadata_item(int(data.get("item",0))) or int(data.get("quantity",0))==1) and data.get("player_revision") is int and data.get("stock_revision") is int

func drop_offer(side:String,data:Variant)->void:
	if not accepts_offer(side,data):return
	_commit(data.item,data.quantity,data.side=="merchant",data.player_revision,data.stock_revision)

func accepts_belt_drop(side:String,data:Variant)->bool:
	if not opened or side not in ["merchant","player"] or not is_instance_valid(hud):return false
	if not data is Dictionary or data.get("owner",0)!=hud.get_instance_id() or data.get("side","")!="player":return false
	if not hud.inventory_open:return false
	for field in ["slot","count","revision"]:
		if not data.has(field) or typeof(data[field])!=TYPE_INT:return false
	var slot:int=data.slot
	if slot<0 or slot>=10 or int(data.count)<1 or int(data.revision)<0:return false
	var state:Dictionary=hud.inventory.snapshot()
	return int(data.revision)==state.revision and int(state.slots[slot].count)>=int(data.count) and int(state.slots[slot].item)>0

func accepts_drop(side:String,data:Variant)->bool:
	return accepts_offer(side,data) or accepts_belt_drop(side,data)

func drop_data(side:String,data:Variant)->void:
	if accepts_belt_drop(side,data):drop_belt(side,data)
	else:drop_offer(side,data)

func drop_belt(side:String,data:Variant)->void:
	if not accepts_belt_drop(side,data) or not is_instance_valid(hud):return
	var slot:int=data.slot;var amount:int=data.count
	if side=="player":
		var moved_name:=Trade.name_of(int(hud.inventory.snapshot().slots[slot].item))
		var moved:Dictionary=hud.move_belt_to_backpack(slot,amount,int(data.revision))
		notice.text="Moved %d × %s to your backpack."%[amount,moved_name] if moved.get("ok",false) else "Backpack has no room for that item."
		refresh(true)
		return
	var state:Dictionary=hud.inventory.snapshot()
	if int(data.revision)!=state.revision:
		refresh(true);notice.text="Inventory changed. Review the refreshed offer.";return
	var item:int=state.slots[slot].item
	var response:Dictionary=trader.exchange(inventory,item,amount,false,state.revision,trader.stock.snapshot().revision,slot)
	refresh(true)
	if response.ok:
		notice.text="Sold %d × %s · %d coins"%[amount,Trade.name_of(item),Trade.price(item,false)*amount]
		traded.emit()
	else:
		notice.text=_failure_text(response.reason)

func _trade_selected(buying:bool)->void:
	var listing=rows if buying else selling
	var selected:PackedInt32Array=listing.get_selected_items()
	if selected.is_empty():return
	quantity.apply()
	var item:int=listing.get_item_metadata(selected[0])
	_commit(item,1 if Trade.metadata_item(item) else int(quantity.value),buying,player_revision,stock_revision)

func exchange(buying: bool) -> void:
	# Existing callers can still transact the selected merchant listing.
	var selected:PackedInt32Array=rows.get_selected_items()
	if selected.is_empty():return
	quantity.apply()
	var item:int=rows.get_item_metadata(selected[0])
	_commit(item,1 if Trade.metadata_item(item) else int(quantity.value),buying,player_revision,stock_revision)

func _commit(item:int,amount:int,buying:bool,expected_player:int,expected_stock:int)->void:
	if not opened:return
	if not permitted.is_valid() or not permitted.call():close();return
	var response:Dictionary=trader.exchange(inventory,item,amount,buying,expected_player,expected_stock)
	refresh()
	if response.ok:
		notice.text="%s %d × %s · %d coins"%["Bought" if buying else "Sold",amount,Trade.name_of(item),Trade.price(item,buying)*amount]
		traded.emit()
	else:
		notice.text=_failure_text(response.reason)

func _failure_text(reason:String)->String:
	var messages:={"stale_revision":"Stock or inventory changed. Review the refreshed offer.","insufficient_items":"You do not have enough coins or goods.","full":"Your backpack is full.","peer_rejected":"The trader lacks stock, coins, or storage space.","invalid_offer":"Choose an available item and quantity from 1 to 999."}
	return messages.get(reason,"The exchange could not be completed. No items or coins changed.")

func close() -> void:
	if not opened: return
	opened = false; panel.hide(); backdrop.hide();brand_root.hide()
	if is_instance_valid(hud) and hud.has_method("set_above_ui"):hud.set_above_ui(false)
	closed.emit()

func _input(event: InputEvent) -> void:
	if opened and event is InputEventKey and event.pressed and get_viewport().gui_get_focus_owner() is LineEdit and event.physical_keycode not in [KEY_ESCAPE,KEY_TAB]:return
	if not opened or not event is InputEventKey or not event.pressed or event.echo:return
	if event.physical_keycode==KEY_E:
		close();get_viewport().set_input_as_handled();return
	WindowNav.close_window(self,event,close)

func _style(bg:Color,border:Color,radius:int,border_width:int=1,shadow:int=0)->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=bg;style.border_color=border
	style.set_border_width_all(border_width);style.set_corner_radius_all(radius);style.anti_aliasing=true
	if shadow>0:
		style.shadow_size=shadow;style.shadow_color=Color(0,0,0,0.55);style.shadow_offset=Vector2(0,12)
	return style

func _pad(style:StyleBoxFlat,value:int)->void:
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(edge,value)

func _label(text:String,size:int,color:Color,align:=HORIZONTAL_ALIGNMENT_LEFT)->Label:
	var label:=Label.new();label.text=text;label.horizontal_alignment=align;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",color)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return label

func _line(color:Color,height:int)->ColorRect:
	var line:=ColorRect.new();line.color=color;line.custom_minimum_size.y=height;line.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return line

func _button(text:String,fill:Color,border:Color,text_color:Color)->Button:
	var button:=Button.new();button.text=text;button.focus_mode=Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size",12);button.add_theme_color_override("font_color",text_color)
	button.add_theme_color_override("font_disabled_color",FAINT)
	for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		var color:=fill
		if state in ["hover","hover_pressed"]:color=fill.lightened(0.08)
		elif state=="pressed":color=fill.darkened(0.06)
		elif state=="disabled":color=Color("#0b1c1b")
		var style:=_style(color,border if state!="disabled" else Color("#243f3a"),9,1);_pad(style,7)
		style.set_border_width(SIDE_BOTTOM,2)
		button.add_theme_stylebox_override(state,style)
	return button

func _style_list(list:ItemList)->void:
	list.add_theme_font_size_override("font_size",16)
	list.add_theme_color_override("font_color",INK)
	list.add_theme_color_override("font_selected_color",Color("#f5d795"))
	list.add_theme_stylebox_override("panel",_style(Color("#081c1b"),Color("#2b554c"),9,1))
	list.add_theme_stylebox_override("selected",_style(Color("#1a4a40"),GOLD,8,1))
	list.add_theme_stylebox_override("selected_focus",_style(Color("#1a4a40"),GOLD,8,1))
	list.add_theme_stylebox_override("focus",_style(Color(0,0,0,0),GOLD,8,1))
	list.add_theme_stylebox_override("hovered",_style(Color("#102d2b"),Color("#4b8171"),8,1))
	list.add_theme_constant_override("v_separation",6)
	list.fixed_icon_size=Vector2i(42,42)

func _style_line_edit(edit:LineEdit)->void:
	edit.add_theme_font_size_override("font_size",14)
	edit.add_theme_color_override("font_color",INK);edit.add_theme_color_override("font_placeholder_color",FAINT)
	edit.add_theme_stylebox_override("normal",_style(Color("#081c1b"),Color("#315d53"),8,1))
	edit.add_theme_stylebox_override("focus",_style(Color("#0c2825"),GOLD,8,1))

func _style_spin(spin:SpinBox)->void:
	var edit:=spin.get_line_edit();edit.add_theme_font_size_override("font_size",14)
	edit.add_theme_color_override("font_color",INK)
	edit.add_theme_stylebox_override("normal",_style(Color("#081c1b"),Color("#315d53"),7,1))
	edit.add_theme_stylebox_override("focus",_style(Color("#0c2825"),GOLD,7,1))

func _style_option(option:OptionButton)->void:
	option.add_theme_font_size_override("font_size",13)
	option.add_theme_color_override("font_color",INK)
	for state in ["normal","hover","pressed","focus"]:
		option.add_theme_stylebox_override(state,_style(Color("#081c1b"),Color("#315d53"),8,1))

func _trade_rail()->VBoxContainer:
	var rail:=VBoxContainer.new();rail.custom_minimum_size.x=74;rail.alignment=BoxContainer.ALIGNMENT_CENTER
	rail.add_theme_constant_override("separation",4)
	rail.add_child(_label("↔",26,GOLD_SOFT,HORIZONTAL_ALIGNMENT_CENTER))
	rail.add_child(_label("DRAG",9,FAINT,HORIZONTAL_ALIGNMENT_CENTER))
	rail.add_child(_label("across",9,MUTED,HORIZONTAL_ALIGNMENT_CENTER))
	rail.add_child(_line(Color(0.25,0.50,0.43,0.55),1))
	rail.add_child(_label("⇄",18,MINT,HORIZONTAL_ALIGNMENT_CENTER))
	rail.add_child(_label("BUY\nSELL",9,FAINT,HORIZONTAL_ALIGNMENT_CENTER))
	return rail

func _purse(caption:String,player:bool)->PanelContainer:
	var card:=PanelContainer.new();card.custom_minimum_size=Vector2(210,64)
	var style:=_style(Color("#0a211f"),Color("#315d53"),11,1);_pad(style,10)
	card.add_theme_stylebox_override("panel",style)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",9);card.add_child(row)
	var icon:=TextureRect.new();icon.texture=Icons.texture(Trade.CURRENCY);icon.custom_minimum_size=Vector2(32,32)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(icon)
	var text:=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;text.add_theme_constant_override("separation",0);row.add_child(text)
	text.add_child(_label(caption,10,FAINT))
	var value:=_label("0 coins",16,MINT if player else GOLD)
	text.add_child(value)
	if player:balance=value
	else:trader_purse=value
	return card

func _badge(text:String,tint:Color)->PanelContainer:
	var badge:=PanelContainer.new();badge.custom_minimum_size=Vector2(48,24)
	var style:=_style(Color(tint.r,tint.g,tint.b,0.09),Color(tint.r,tint.g,tint.b,0.45),6,1);_pad(style,5)
	badge.add_theme_stylebox_override("panel",style)
	badge.add_child(_label(text,9,tint,HORIZONTAL_ALIGNMENT_CENTER))
	return badge

func _item_detail(item:int)->String:
	if item>=1 and item<=8:return "Tool · gear"
	if item>=301 and item<=306:return "Clothing · wearable"
	if item>=401 and item<=411:return "Container · water"
	if item==501:return "Vehicle · durable"
	if item in [214,215,216]:return "Readable · notes"
	if item in [217,218,219]:return "Food · restores hunger"
	if item in [221,223]:return "Ammunition · stackable"
	if item==222:return "Explosive · placeable"
	if item==220:return "Fuel · stackable"
	if item in [224,225,226,227]:return "Salvage · recyclable"
	return "Commodity · stackable"

func _coin_text(value:int)->String:
	var text:=str(absi(value))
	var grouped:=""
	while text.length()>3:
		grouped=","+text.right(3)+grouped
		text=text.left(text.length()-3)
	return ("-" if value<0 else "")+text+grouped

func _restore_scroll(row_value:float,sell_value:float)->void:
	if is_instance_valid(rows):
		rows.get_v_scroll_bar().value=clampf(row_value,0.0,rows.get_v_scroll_bar().max_value)
	if is_instance_valid(selling):
		selling.get_v_scroll_bar().value=clampf(sell_value,0.0,selling.get_v_scroll_bar().max_value)
