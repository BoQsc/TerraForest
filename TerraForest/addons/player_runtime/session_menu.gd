# SPDX-License-Identifier: 0BSD
extends CanvasLayer
var game: Node
var opened:=false
var developer:=false
var tilde_down:=-1
var panel: PanelContainer
var dev_box: VBoxContainer
var mode_label: Label
var fly_button: Button
var inventory_button: Button
var mode_button: Button
var instructions: Label
var objects: OptionButton
var shapes: OptionButton
var vegetation: OptionButton
var materials: OptionButton
var message: Label
var confirmation: ConfirmationDialog
var pending_action: Callable
func button(parent: Node,text: String,action: Callable) -> Button:
	var out:=Button.new();out.text=text;out.custom_minimum_size.y=42;out.pressed.connect(action);parent.add_child(out);return out
func _ready() -> void:
	layer=40;developer=not game.construction_inventory.gameplay;game.help.hide()
	panel=PanelContainer.new();panel.position=Vector2(580,110);panel.size=Vector2(760,830);add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.045,0.05,0.98)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(edge,24)
	panel.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);panel.add_child(column)
	var title:=Label.new();title.text="TERRAFOREST";title.add_theme_font_size_override("font_size",28);column.add_child(title)
	mode_label=Label.new();column.add_child(mode_label)
	var row:=HBoxContainer.new();column.add_child(row)
	button(row,"Resume",func():set_open(false));inventory_button=button(row,"Inventory",func():set_open(false);game.player_hud.set_open(true))
	button(row,"Save world",save_world);button(row,"Load saved world",func():confirm("Discard unsaved changes and reload?",reload_world))
	var label:=Label.new();label.text="BUILD & PLACE";column.add_child(label)
	objects=OptionButton.new();for entry in game.model_tool.catalog:objects.add_item(entry.title)
	column.add_child(objects);button(column,"Place selected object",func():set_open(false);game._set_player_tool_mode(true,true,game.tool);game.model_tool.select(objects.selected))
	row=HBoxContainer.new();column.add_child(row)
	shapes=OptionButton.new();for name in ["Cube","Slab","Stairs","Slope","Post","Sphere"]:shapes.add_item(name)
	materials=OptionButton.new();for name in ["Brick","Wood","Concrete","Metal"]:materials.add_item(name)
	row.add_child(shapes);row.add_child(materials)
	button(row,"Build selected shape",func():set_open(false);game._set_player_tool_mode(true,false,game.tool);game.structure_shape=shapes.selected+1;game.structure_material=materials.selected;game.structure_prefab_index=-1;game._sync_construction_palette())
	row=HBoxContainer.new();column.add_child(row)
	button(row,"Mine terrain",func():set_open(false);game._set_player_tool_mode(false,false,1))
	vegetation=OptionButton.new()
	for name in game.player_hud.GroundCatalog.NAMES:vegetation.add_item(name)
	row.add_child(vegetation)
	button(row,"Gather / place",func():set_open(false);game._activate_ground_tool(vegetation.selected))
	button(row,"Headlamp",func():game.headlamp.toggle())
	instructions=Label.new();instructions.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(instructions)
	dev_box=VBoxContainer.new();column.add_child(dev_box)
	label=Label.new();label.text="DEVELOPMENT TOOLS";dev_box.add_child(label)
	row=HBoxContainer.new();dev_box.add_child(row)
	fly_button=button(row,"Flight",toggle_flight)
	button(row,"Diagnostics",func():set_open(false);dispatch(KEY_F3))
	button(row,"Road editor",func():set_open(false);game._set_player_tool_mode(false,false,game.tool);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE)
	button(row,"Place vehicle",func():set_open(false);dispatch(KEY_V))
	button(dev_box,"Building / settlement editor",func():set_open(false);game._set_player_tool_mode(true,false,game.tool);Input.mouse_mode=Input.MOUSE_MODE_VISIBLE)
	mode_button=button(column,"Development mode (~)",toggle_developer)
	mode_button.tooltip_text="Tap the ` / ~ key to switch modes. Hold for 0.45 seconds and release to toggle development flight."
	message=Label.new();message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(message)
	button(column,"Save and quit",func():confirm("Save this world and quit?",func():game._notification(NOTIFICATION_WM_CLOSE_REQUEST)))
	game.terrain.save_completed.connect(func(ok: bool):message.text="World saved" if ok else "Save failed; check world status")
	confirmation=ConfirmationDialog.new();confirmation.confirmed.connect(func():pending_action.call());add_child(confirmation)
	panel.hide();refresh()
func confirm(text: String,action: Callable) -> void:
	pending_action=action;confirmation.dialog_text=text;confirmation.popup_centered(Vector2i(450,160))
func refresh() -> void:
	inventory_button.disabled=game.world_vehicle.driving
	mode_label.text="DEVELOPMENT · free editing" if developer else "GAMEPLAY · resource costs enabled"
	mode_button.text="Return to gameplay (~)" if developer else "Enter development mode (~)"
	instructions.text="Drag inventory stacks to arrange the ten-slot belt. Shift-drag splits a stack.\nE interacts · "+("Alt + 1–9 / 0" if developer else "1–9 / 0")+" equip · Tab inventory · Esc menu"
	dev_box.visible=developer;fly_button.text="Flight: "+("on" if game.fly else "off")
func set_open(value: bool) -> void:
	if opened==value:return
	if value:
		game.storage.close();game.player_hud.set_open(false)
	opened=value;panel.visible=value
	game.player_hud.inventory_open=value;game.player_hud.enabled=not value
	game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	refresh()
func toggle_developer() -> void:
	if game.loading_active or game.shutdown_requested or game.site_preparation.status=="running" or game.site_survey.busy or not game._foundation_placement.is_empty() or not game.road_palette.pending.is_empty() or game.terrain.pending_edit or game.construction_inventory.busy or not game.construction_inventory.pending_prefab.is_empty():
		message.text="Wait for the current world edit to finish.";return
	developer=not developer
	game.construction_inventory.gameplay=not developer;game.model_tool.gameplay=not developer;game.player_hud.gameplay_construction=not developer
	game.mining_rewards.enabled=not developer
	if not developer:game.fly=false;game._clear_motion()
	game.player_hud.refresh();refresh()
func toggle_flight() -> void:
	if not developer or game.world_vehicle.driving:return
	game.fly=not game.fly;game._clear_motion();refresh()
func save_world() -> void:
	if game.world_vehicle.driving and not game.world_vehicle.safe_exit_position(game).is_finite():message.text="Park beside clear ground before saving.";return
	game.terrain.save_world();message.text="Saving…"
func reload_world() -> void:
	set_open(false);game.terrain.reload_world(false)
func dispatch(key: int) -> void:
	var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=key;game._unhandled_input(event)
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or event.echo:return
	if event.physical_keycode==KEY_QUOTELEFT:
		if event.pressed:tilde_down=Time.get_ticks_msec()
		elif tilde_down>=0:
			if Time.get_ticks_msec()-tilde_down>=450:
				if not developer:toggle_developer()
				toggle_flight()
			else:toggle_developer()
			tilde_down=-1
		get_viewport().set_input_as_handled();return
	if event.pressed and event.physical_keycode==KEY_ESCAPE:
		if confirmation.visible:confirmation.hide()
		elif game.storage.opened:game.storage.close()
		elif game.player_hud.inventory_open and not opened:game.player_hud.set_open(false)
		else:set_open(not opened)
		get_viewport().set_input_as_handled();return
	if opened:return
	if not developer and event.pressed and not game.player_hud.inventory_open:
		if event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8,KEY_9,KEY_0]:
			game.player_hud.equip(9 if event.physical_keycode==KEY_0 else event.physical_keycode-KEY_1);get_viewport().set_input_as_handled()
		elif event.physical_keycode in [KEY_G,KEY_F2,KEY_F3,KEY_F4,KEY_F6,KEY_F7,KEY_F8,KEY_F10,KEY_J,KEY_K,KEY_V,KEY_L] or (event.ctrl_pressed and event.physical_keycode==KEY_R):
			get_viewport().set_input_as_handled()
