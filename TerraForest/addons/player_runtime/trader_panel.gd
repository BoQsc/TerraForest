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

func _ready() -> void:
	layer = 30
	panel = PanelContainer.new()
	panel.position = Vector2(460, 190)
	panel.custom_minimum_size = Vector2(1000, 650)
	add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17252b")
	for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 24)
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 15)
	panel.add_child(column)
	var title := Label.new()
	title.text = "TRADER / GENERAL SUPPLIES"
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	balance = Label.new(); column.add_child(balance)
	var welcome := Label.new()
	welcome.text = "Welcome. I buy gathered resources and sell building supplies.\nStock and coins are finite. Prices below are per item."
	column.add_child(welcome)
	rows = ItemList.new(); rows.custom_minimum_size = Vector2(940, 320)
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
	notice = Label.new(); notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(notice)
	panel.hide()

func open_for(merchant: RefCounted, player_inventory: RefCounted, reach_check: Callable) -> bool:
	if not reach_check.is_valid() or not reach_check.call(): return false
	trader = merchant; inventory = player_inventory; permitted = reach_check
	opened = true; panel.show(); refresh(); rows.grab_focus(); return true

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
	notice.text = "Choose an item and quantity. Buying and selling complete together."

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
