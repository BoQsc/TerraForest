# SPDX-License-Identifier: 0BSD
# Presentation only. Stack rules and mutations live in NativePlayerInventory.
extends CanvasLayer
signal tool_requested(item: int)
signal actions_requested
signal menu_changed(open: bool)
signal inventory_changed
signal drop_requested(slot: int, revision: int)
const CATALOG: Dictionary={1:"Pickaxe",2:"Hatchet",3:"Building hammer",4:"Assembly tool"}
const MATERIALS: Dictionary={101:"Brick",102:"Wood",103:"Concrete",104:"Metal"}
# UI metadata is local so this addon remains independently loadable.
# woodland_accents checks it against the ecosystem catalog.
class GroundCatalog:
	const COUNT:=8
	const ITEMS: Array[int]=[201,204,205,206,207,208,209,210]
	const COSTS: Array[int]=[201,204,205,206,207,208,209,102]
	const NAMES: Array[String]=["Stone","Fern","Grass clump","White wildflower","Golden wildflower","Violet wildflower","Low bush","Dry twigs"]
const RESOURCES: Dictionary={201:"Stone",202:"Iron ore",203:"Copper ore",204:"Plant",205:"Grass clump",206:"White wildflower",207:"Golden wildflower",208:"Violet wildflower",209:"Low bush",210:"Dry twigs"}
const GROUND_ITEMS: Dictionary={201:0,204:1,205:2,206:3,207:4,208:5,209:6,210:7}
var ground_tools_enabled:=false
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
var recipe_buttons: Array[Button]=[]
var crafting_panel: PanelContainer
var crafting_message: Label
var drop_button: Button
const Crafting=preload("res://addons/player_runtime/crafting.gd")
var state: Dictionary={}
var enabled:=true
var default_loadout:=PackedByteArray()
var temporary_world:=true
var active_item:=0
var active_slot: int=-1
var ground_species: int=-1
var ground_hint: Label
var mode_hint: Label
var action_hint: Label
var editor_hint: String=""
var ground_feedback: String=""
var gameplay_construction:=false

func show_active_tool(item: int) -> void:
	active_item=item
	if not slots.is_empty(): refresh()

func show_ground_feedback(text: String) -> void:
	if text==ground_feedback: return
	ground_feedback=text
	_refresh_ground_hint()

func show_ground_tool(species: int) -> void:
	ground_feedback=""
	ground_species=species
	if not slots.is_empty(): refresh()

func _refresh_ground_hint() -> void:
	if ground_hint==null: return
	ground_hint.visible=ground_species>=0 and not inventory_open
	if ground_species<0: return
	var names: Array[String]=GroundCatalog.NAMES
	var items: Array[int]=GroundCatalog.COSTS
	var choices: Array[String]=[]
	var available:=0
	for i in range(GroundCatalog.COUNT):
		choices.append("%d %s%s"%[i+1,names[i]," [selected]" if i==ground_species else ""])
	for row: Dictionary in state.slots:
		if row.item==items[ground_species]: available+=int(row.count)
	var cost: String=("Place: 1 %s · have %d"%[MATERIALS.get(items[ground_species],names[ground_species]),available]) if gameplay_construction else "Free placement · editor"
	ground_hint.text=names[ground_species]+" · "+cost+"\nLMB / E "+("collect" if gameplay_construction else "remove")+" · RMB place · Esc to choose another plant"
	if not ground_feedback.is_empty(): ground_hint.text+="\n"+ground_feedback

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
	active_slot=-1;active_item=0
	if not slots.is_empty(): refresh()
	return true

func _ready() -> void:
	layer=20
	if not prepare(): return
	modal=Control.new()
	message=Label.new()
	var bar:=HBoxContainer.new()
	bar.position=Vector2(370,960)
	bar.add_theme_constant_override("separation",8)
	add_child(bar)
	action_hint=Label.new();action_hint.position=Vector2(370,920);add_child(action_hint)
	ground_hint=Label.new();ground_hint.position=Vector2(500,800)
	ground_hint.add_theme_color_override("font_shadow_color",Color.BLACK)
	ground_hint.add_theme_constant_override("shadow_offset_x",2);ground_hint.add_theme_constant_override("shadow_offset_y",2)
	add_child(ground_hint)
	for i in range(10):
		var button=preload("res://addons/player_runtime/inventory_slot.gd").new();button.controller=self;button.slot=i
		button.custom_minimum_size=Vector2(110,64)
		button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(func(): equip(i))
		bar.add_child(button);belt.append(button)
	var hint:=Label.new();mode_hint=hint;hint.text="1–9 / 0 / Wheel equip    ·    Tab inventory    ·    Esc menu"
	hint.text += "    ·    " + ("Gameplay construction" if gameplay_construction else "Free editor")
	hint.position=Vector2(370,1032);add_child(hint)
	add_child(modal);modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade:=ColorRect.new();shade.color=Color(0.025,0.04,0.06,0.9)
	modal.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel:=PanelContainer.new();panel.position=Vector2(660,200);panel.size=Vector2(1040,650)
	modal.add_child(panel)
	var margin:=MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	panel.add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",16);margin.add_child(column)
	var title:=Label.new();title.text="INVENTORY";title.add_theme_font_size_override("font_size",28);var title_row:=HBoxContainer.new();title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title_row.add_child(title)
	var actions_button:=Button.new();actions_button.text="Actions";actions_button.pressed.connect(func():set_open(false);actions_requested.emit());title_row.add_child(actions_button)
	var close_button:=Button.new();close_button.text="Close";close_button.pressed.connect(func():set_open(false));title_row.add_child(close_button);column.add_child(title_row)
	var detail:=Label.new();detail.text="Tools and materials · first ten slots form the toolbelt"
	if gameplay_construction: detail.text="First ten slots are your toolbelt. Drag to move; Shift-drag to split."
	column.add_child(detail)
	var grid:=GridContainer.new();grid.columns=8;grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);column.add_child(grid)
	for i in range(32):
		var button=preload("res://addons/player_runtime/inventory_slot.gd").new();button.controller=self;button.slot=i;button.custom_minimum_size=Vector2(110,75);button.focus_mode=Control.FOCUS_NONE
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
	crafting_panel=PanelContainer.new();crafting_panel.position=Vector2(220,200);crafting_panel.size=Vector2(420,650);modal.add_child(crafting_panel)
	var craft_margin:=MarginContainer.new()
	for side in ["left","right","top","bottom"]:craft_margin.add_theme_constant_override("margin_"+side,20)
	crafting_panel.add_child(craft_margin)
	var recipes:=VBoxContainer.new();recipes.add_theme_constant_override("separation",14);craft_margin.add_child(recipes)
	var craft_label:=Label.new();craft_label.text="CRAFTING";craft_label.add_theme_font_size_override("font_size",26);recipes.add_child(craft_label)
	var craft_help:=Label.new();craft_help.text="Click a recipe to craft one batch.";recipes.add_child(craft_help)
	for i in Crafting.RECIPES.size():
		var button:=Button.new();button.custom_minimum_size=Vector2(370,94);button.alignment=HORIZONTAL_ALIGNMENT_LEFT;button.focus_mode=Control.FOCUS_NONE
		for visual in ["normal","hover","pressed","disabled"]:
			var style:=StyleBoxFlat.new();style.bg_color=Color("203a34") if visual in ["hover","pressed"] else Color("142420")
			style.border_color=Color("608d79") if visual!="disabled" else Color("33413c");style.set_border_width_all(1);style.set_corner_radius_all(6)
			for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(edge,12)
			button.add_theme_stylebox_override(visual,style)
		button.add_theme_color_override("font_disabled_color",Color("879b93"))
		button.pressed.connect(craft_recipe.bind(i));recipes.add_child(button);recipe_buttons.append(button)
	crafting_message=Label.new();crafting_message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;crafting_message.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	crafting_message.text="Recipes use materials in your inventory. Claim pending mined materials first.";recipes.add_child(crafting_message)
	var equip_button:=Button.new();equip_button.text="Equip selected item / empty hands";equip_button.pressed.connect(func():
		if selected_slot>=0:
			var chosen:=selected_slot;set_open(false);equip_inventory(chosen)
	);column.add_child(equip_button)
	drop_button=Button.new();drop_button.text="Drop one selected supply";drop_button.pressed.connect(drop_selected);column.add_child(drop_button)
	message.text="Drag stacks to move, merge or swap. Shift-drag moves half. Tab / Esc closes."
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;message.custom_minimum_size.y=42
	column.add_child(message)
	modal.hide();refresh()

func refresh() -> void:
	if action_hint!=null:
		action_hint.text=editor_hint if not editor_hint.is_empty() else {0:"Empty hands | E interact",1:"Pickaxe | Hold left mouse: mine nearby terrain",2:"Hatchet | Left mouse: chop tree",3:"Building hammer | Right mouse: build | Left mouse: remove | Esc: shape, material, rotation",4:"Assembly tool | Right mouse: place | Left mouse: dismantle | Esc: object and transform settings"}.get(active_item,"Holding "+MATERIALS.get(active_item,RESOURCES.get(active_item,"item"))+" | E interact")
	if mode_hint!=null:mode_hint.text="1–9 / 0"+" / Wheel equip · Tab inventory · Esc menu · "+("Gameplay" if gameplay_construction else "Development")
	var latest: Dictionary=inventory.snapshot()
	var inventory_changed_since_view: bool=latest.revision!=state.get("revision",-1)
	state=latest
	if inventory_changed_since_view and active_slot>=0 and active_item!=int(state.slots[active_slot].item):
		active_item=int(state.slots[active_slot].item);tool_requested.emit(active_item)
	for i in range(32):
		var row: Dictionary=state.slots[i]
		var title: String=CATALOG.get(row.item,MATERIALS.get(row.item,RESOURCES.get(row.item,"Empty")))
		if row.item in MATERIALS or row.item in RESOURCES: title += " ×%d" % row.count
		slots[i].set_appearance(row.count==0,i==active_slot,i==selected_slot)
		slots[i].text="%02d%s\n%s"%[i+1," •" if i==selected_slot else "",title]
		if i<10:
			belt[i].text="%d%s\n%s"%[(i+1)%10," •" if i==active_slot else "",title]
			belt[i].disabled=false
			belt[i].set_appearance(row.count==0,i==active_slot,false)
	_refresh_ground_hint()
	_refresh_pending()
	_refresh_recipes()
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

func _equippable(item: int) -> bool:
	return item in CATALOG or (ground_tools_enabled and item in GROUND_ITEMS)

func equip(slot: int) -> void:
	if slot<0 or slot>=10:return
	equip_inventory(slot)

func equip_inventory(slot: int) -> void:
	if not enabled or inventory==null or slot<0 or slot>=32:return
	state=inventory.snapshot();active_slot=slot;active_item=int(state.slots[slot].item)
	tool_requested.emit(active_item);refresh()

func equip_item(item: int) -> bool:
	state=inventory.snapshot()
	for i in 32:
		if state.slots[i].item==item:equip_inventory(i);return true
	return false

func _refresh_recipes() -> void:
	var counts: Dictionary={}
	for row: Dictionary in state.slots:counts[row.item]=int(counts.get(row.item,0))+int(row.count)
	for i in recipe_buttons.size():
		var recipe: Dictionary=Crafting.RECIPES[i]
		var requirements: PackedStringArray=[]
		var affordable:=true
		for j in range(0,recipe.costs.size(),2):
			var item: int=recipe.costs[j];var cost: int=recipe.costs[j+1];var have: int=counts.get(item,0)
			requirements.append("%s %d / %d"%[RESOURCES.get(item,MATERIALS.get(item,"Item")),have,cost])
			affordable=affordable and have>=cost
		var output: int=recipe.outputs[0]
		recipe_buttons[i].text="%s x%d\n%s\n%s"%[MATERIALS.get(output,RESOURCES.get(output,"Item")),recipe.outputs[1]," | ".join(requirements),"Click to craft" if affordable else "Need more materials"]
		recipe_buttons[i].disabled=not affordable
		recipe_buttons[i].tooltip_text="Owned / required. One click crafts one batch; output space is checked before consuming materials."

func craft_recipe(recipe: int) -> void:
	if not enabled or not inventory_open: return
	var result: Dictionary=Crafting.craft(inventory,recipe,1,state.revision)
	if result.ok:
		message.text="Crafted supplies · "+("temporary world; not saved" if temporary_world else "F5 saves world")
		inventory_changed.emit()
	elif result.reason=="full": message.text="Not enough output space. Free a slot or craft fewer; inputs are retained."
	elif result.reason=="insufficient_items": message.text="Not enough raw resources. Claim mined resources before crafting."
	else: message.text="Craft rejected (%s). Inventory refreshed; try again."%result.reason
	crafting_message.text=message.text
	refresh()

func select_slot(slot: int) -> void:
	# Click selects; dragging moves. Selection must never relocate an item.
	selected_slot=-1 if selected_slot==slot else slot
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
	_refresh_ground_hint()
	modal.visible=value
	menu_changed.emit(value)

func _input(event: InputEvent) -> void:
	if not enabled: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_TAB or (inventory_open and event.physical_keycode==KEY_ESCAPE):
			set_open(not inventory_open);get_viewport().set_input_as_handled();return
		if event.alt_pressed and event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8,KEY_9,KEY_0]:
			equip(9 if event.physical_keycode==KEY_0 else event.physical_keycode-KEY_1);get_viewport().set_input_as_handled();return

func _unhandled_key_input(_event: InputEvent) -> void:
	# Let quantity entry and dropdown navigation receive GUI keyboard events.
	if inventory_open: get_viewport().set_input_as_handled()

func drag_data(_side: String,slot: int) -> Dictionary:
	if not enabled or not inventory_open:return {}
	var row: Dictionary=state.slots[slot]
	if row.count==0:return {}
	selected_slot=-1
	return {"owner":get_instance_id(),"side":"player","slot":slot,"count":maxi(1,int(row.count)/2) if Input.is_key_pressed(KEY_SHIFT) else row.count,"revision":state.revision}
func accepts_drag(_side: String,_slot: int,data: Variant) -> bool:
	return enabled and inventory_open and data is Dictionary and data.get("owner",0)==get_instance_id()
func drop_stack(side: String,slot: int,data: Variant) -> void:
	if not accepts_drag(side,slot,data):return
	var result: Dictionary=inventory.transfer(data.slot,slot,data.count,data.revision)
	if result.ok:inventory_changed.emit()
	message.text="Stack moved" if result.ok else "Cannot move that stack; inventory refreshed"
	selected_slot=-1;refresh()
