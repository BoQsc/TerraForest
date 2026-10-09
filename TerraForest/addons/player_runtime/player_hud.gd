# SPDX-License-Identifier: 0BSD
# Presentation only. Stack rules and mutations live in NativePlayerInventory.
extends CanvasLayer
signal tool_requested(item: int)
signal menu_changed(open: bool)
signal inventory_changed
signal drop_requested(slot: int, revision: int)
const CATALOG: Dictionary={1:"Sculpt sphere",2:"Sculpt cube",3:"Build blocks",4:"Place objects"}
const MATERIALS: Dictionary={101:"Brick",102:"Wood",103:"Concrete",104:"Metal"}
const RESOURCES: Dictionary={201:"Stone",202:"Iron ore",203:"Copper ore",204:"Plant",205:"Grass clump"}
const STARTER_MATERIAL_COUNT:=64
var inventory: RefCounted
var reward_inbox: RefCounted
var inventory_open:=false
var selected_slot: int=-1
var previous_mouse: int=Input.MOUSE_MODE_CAPTURED
var slots: Array[Button]=[]
var belt: Array[Button]=[]
var modal: Control
var message: Label
var pending_choice: OptionButton
var pending_amount: SpinBox
var claim_button: Button
var recipe_choice: OptionButton
var craft_amount: SpinBox
var craft_button: Button
var drop_button: Button
const Crafting=preload("res://addons/player_runtime/crafting.gd")
var state: Dictionary={}
var enabled:=true
var default_loadout:=PackedByteArray()
var temporary_world:=true
var active_item:=0
var gameplay_construction:=false

func show_active_tool(item: int) -> void:
	active_item=item
	if not slots.is_empty(): refresh()

func prepare() -> bool:
	if inventory!=null: return true
	if not ClassDB.class_exists("NativePlayerInventory"):
		GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	if not ClassDB.class_exists("NativePlayerInventory"):
		push_error("Player inventory extension unavailable");enabled=false;return false
	inventory=ClassDB.instantiate("NativePlayerInventory")
	reward_inbox=ClassDB.instantiate("NativeRewardInbox")
	for id: int in CATALOG: inventory.register_item(id,1)
	for id: int in MATERIALS: inventory.register_item(id,999)
	for id: int in RESOURCES: inventory.register_item(id,999)
	for id: int in CATALOG: inventory.grant(id,1,inventory.snapshot().revision)
	# Only the default for a missing loadout section. Restoration replaces all
	# slots, including an explicitly empty saved inventory; never top up on load.
	if gameplay_construction:
		var supplies:=PackedInt64Array()
		for id: int in MATERIALS: supplies.append_array(PackedInt64Array([id,STARTER_MATERIAL_COUNT]))
		if not inventory.grant_items(supplies,inventory.snapshot().revision).ok:
			inventory=null
			return false
	default_loadout=inventory.capture_storage_snapshot()
	return true

func capture_snapshot() -> PackedByteArray:
	return inventory.capture_storage_snapshot()

func restore_snapshot(data: PackedByteArray) -> bool:
	if not inventory.restore_storage_snapshot(data): return false
	selected_slot=-1
	if not slots.is_empty(): refresh()
	return true

func _ready() -> void:
	layer=20
	if not prepare(): return
	modal=Control.new()
	message=Label.new()
	var bar:=HBoxContainer.new()
	bar.position=Vector2(620,900)
	bar.add_theme_constant_override("separation",8)
	add_child(bar)
	for i in range(6):
		var button:=Button.new()
		button.custom_minimum_size=Vector2(106,64)
		button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(func(): equip(i))
		bar.add_child(button);belt.append(button)
	var hint:=Label.new();hint.text="Alt + 1–6 equip    ·    Tab inventory"
	hint.text += "    ·    " + ("Gameplay construction" if gameplay_construction else "Free editor")
	hint.position=Vector2(620,970);add_child(hint)
	add_child(modal);modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade:=ColorRect.new();shade.color=Color(0.025,0.04,0.06,0.9)
	modal.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel:=PanelContainer.new();panel.position=Vector2(460,235);panel.size=Vector2(1000,570)
	modal.add_child(panel)
	var margin:=MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	panel.add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",16);margin.add_child(column)
	var title:=Label.new();title.text="INVENTORY";title.add_theme_font_size_override("font_size",28);column.add_child(title)
	var detail:=Label.new();detail.text="Tools and materials · first six slots form the toolbelt"
	if gameplay_construction: detail.text="Construction costs one material per block; removal gives no refund."
	column.add_child(detail)
	var grid:=GridContainer.new();grid.columns=8;grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);column.add_child(grid)
	for i in range(32):
		var button:=Button.new();button.custom_minimum_size=Vector2(110,75);button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(func(): select_slot(i))
		grid.add_child(button);slots.append(button)
	var rewards:=HBoxContainer.new();rewards.add_theme_constant_override("separation",12)
	column.add_child(rewards)
	var reward_label:=Label.new();reward_label.text="Pending materials";rewards.add_child(reward_label)
	pending_choice=OptionButton.new();pending_choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	rewards.add_child(pending_choice);pending_choice.item_selected.connect(func(_index: int): _select_pending())
	pending_amount=SpinBox.new();pending_amount.min_value=1;pending_amount.max_value=32000000;pending_amount.value=1
	pending_amount.custom_minimum_size.x=130;rewards.add_child(pending_amount)
	claim_button=Button.new();claim_button.text="Claim";claim_button.pressed.connect(claim_pending);rewards.add_child(claim_button)
	var crafting:=HBoxContainer.new();crafting.add_theme_constant_override("separation",12);column.add_child(crafting)
	var craft_label:=Label.new();craft_label.text="Craft supplies";crafting.add_child(craft_label)
	recipe_choice=OptionButton.new();recipe_choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;crafting.add_child(recipe_choice)
	for recipe in Crafting.RECIPES: recipe_choice.add_item(recipe.title)
	craft_amount=SpinBox.new();craft_amount.min_value=1;craft_amount.max_value=1000;craft_amount.value=1;craft_amount.custom_minimum_size.x=130;crafting.add_child(craft_amount)
	craft_button=Button.new();craft_button.text="Craft";craft_button.pressed.connect(craft_selected);crafting.add_child(craft_button)
	drop_button=Button.new();drop_button.text="Drop one selected supply";drop_button.pressed.connect(drop_selected);column.add_child(drop_button)
	message.text="Click a filled slot, then a destination to move or swap. Tab / Esc closes."
	column.add_child(message)
	modal.hide();refresh()

func refresh() -> void:
	state=inventory.snapshot()
	for i in range(32):
		var row: Dictionary=state.slots[i]
		var title: String=CATALOG.get(row.item,MATERIALS.get(row.item,RESOURCES.get(row.item,"Empty")))
		if row.item in MATERIALS or row.item in RESOURCES: title += " ×%d" % row.count
		slots[i].text="%02d%s\n%s"%[i+1," •" if i==selected_slot else "",title]
		if i<6:
			belt[i].text="%d%s\n%s"%[i+1," •" if row.item!=0 and row.item==active_item else "",title]
			belt[i].disabled=row.item not in CATALOG
	_refresh_pending()
	drop_button.disabled=selected_slot<0 or not _droppable(state.slots[selected_slot].item)

func _droppable(item: int) -> bool:
	return item in MATERIALS or item in RESOURCES

func drop_selected() -> void:
	if not enabled or not inventory_open or selected_slot<0 or not _droppable(state.slots[selected_slot].item): return
	drop_requested.emit(selected_slot,state.revision)

func _refresh_pending() -> void:
	var selected: int=int(pending_choice.get_item_metadata(pending_choice.selected)) if not pending_choice.disabled and pending_choice.selected>=0 else 0
	pending_choice.clear()
	var pending: PackedInt64Array=reward_inbox.get_pending()
	for i in range(0,pending.size(),2):
		var item: int=pending[i]
		pending_choice.add_item("%s ×%d"%[MATERIALS.get(item,RESOURCES.get(item,CATALOG.get(item,"Item %d"%item))),pending[i+1]])
		pending_choice.set_item_metadata(i/2,item)
		if item==selected: pending_choice.select(i/2)
	pending_choice.disabled=pending.is_empty()
	if pending.is_empty(): pending_choice.add_item("No pending materials")
	_select_pending()

func _select_pending() -> void:
	claim_button.disabled=pending_choice.disabled
	pending_amount.editable=not pending_choice.disabled
	if pending_choice.disabled: return
	var item: int=pending_choice.get_item_metadata(pending_choice.selected)
	var pending: PackedInt64Array=reward_inbox.get_pending()
	for i in range(0,pending.size(),2):
		if pending[i]==item: pending_amount.max_value=mini(pending[i+1],32000000);return

func claim_pending() -> void:
	if not enabled or not inventory_open or pending_choice.disabled: return
	var item: int=pending_choice.get_item_metadata(pending_choice.selected)
	var amount:=int(pending_amount.value)
	var result: Dictionary=reward_inbox.claim(inventory,PackedInt64Array([item,amount]),state.revision)
	if result.ok:
		message.text="Claimed %d · %s"%[amount,"temporary world; not saved" if temporary_world else "F5 saves world"]
		inventory_changed.emit()
	elif result.reason=="full": message.text="Not enough inventory space. Claim fewer or free a slot; pending materials are retained."
	else: message.text="Claim rejected (%s). Inventory refreshed; try again."%result.reason
	refresh()

func equip(slot: int) -> void:
	if not enabled or inventory==null or slot<0 or slot>=6: return
	state=inventory.snapshot()
	var item: int=state.slots[slot].item
	if item in CATALOG: tool_requested.emit(item)

func craft_selected() -> void:
	if not enabled or not inventory_open: return
	var result: Dictionary=Crafting.craft(inventory,recipe_choice.selected,int(craft_amount.value),state.revision)
	if result.ok:
		message.text="Crafted supplies · "+("temporary world; not saved" if temporary_world else "F5 saves world")
		inventory_changed.emit()
	elif result.reason=="full": message.text="Not enough output space. Free a slot or craft fewer; inputs are retained."
	elif result.reason=="insufficient_items": message.text="Not enough raw resources. Claim mined resources before crafting."
	else: message.text="Craft rejected (%s). Inventory refreshed; try again."%result.reason
	refresh()

func select_slot(slot: int) -> void:
	if selected_slot<0:
		if state.slots[slot].item!=0: selected_slot=slot
	elif selected_slot==slot:
		selected_slot=-1
	else:
		var result: Dictionary=inventory.transfer(selected_slot,slot,state.slots[selected_slot].count,state.revision)
		message.text=("Loadout updated · temporary world; changes are not saved." if temporary_world else "Loadout updated · close inventory and press F5 to save world.") if result.ok else "Move rejected: "+str(result.reason)
		if result.ok: inventory_changed.emit()
		selected_slot=-1
	refresh()

func set_open(value: bool) -> void:
	if not enabled or inventory==null or inventory_open==value: return
	inventory_open=value
	if value:
		previous_mouse=Input.mouse_mode
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		refresh()
	else:
		Input.mouse_mode=previous_mouse
		selected_slot=-1
	modal.visible=value
	menu_changed.emit(value)

func _input(event: InputEvent) -> void:
	if not enabled: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_TAB or (inventory_open and event.physical_keycode==KEY_ESCAPE):
			set_open(not inventory_open);get_viewport().set_input_as_handled();return
		if event.alt_pressed and event.physical_keycode>=KEY_1 and event.physical_keycode<=KEY_6:
			equip(event.physical_keycode-KEY_1);get_viewport().set_input_as_handled();return

func _unhandled_key_input(_event: InputEvent) -> void:
	# Let quantity entry and dropdown navigation receive GUI keyboard events.
	if inventory_open: get_viewport().set_input_as_handled()
