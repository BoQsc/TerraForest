# SPDX-License-Identifier: 0BSD
extends CanvasLayer
# One entry point and dock for gameplay equipment and development authoring.
# Optional host-owned destination; standalone addons do not depend on demo scenes.
var world_browser_path: String=""
var game: Node
var opened:=false
var workspace:=false
var developer:=false
var gameplay_slot:=-1
var developer_hud: CanvasLayer
var tilde_down:=-1
var tilde_chord:=false
var panel: PanelContainer
var mode_label: Label
var message: Label
var fly_button: Button
var inventory_button: Button
var mode_button: Button
var dev_box: VBoxContainer
var confirmation: ConfirmationDialog
var pending_action: Callable
var leaving_world:=false
var pages: Dictionary={}
var navigation: Dictionary={}
var belt_choices: Array[Button]=[]
var docked: Dictionary={}
var current_page:="Session"
var scroll: ScrollContainer
var content: VBoxContainer
var ready_to_dock:=false
var brush_radius: SpinBox
const DESCRIPTIONS={1:"Pickaxe: hold left mouse to attack or dig. Most effective on stone.",2:"Hatchet: hold left mouse to attack or dig. Most effective on wood.",3:"Building hammer: left mouse attacks the aimed target; right mouse builds the selected shape.",4:"Assembly tool: left mouse attacks the aimed target; right mouse places the selected object."}
func button(parent: Node,text: String,action: Callable) -> Button:
	var out:=Button.new();out.text=text;out.custom_minimum_size.y=40;out.pressed.connect(action);parent.add_child(out);return out
func label(parent: Node,text: String) -> Label:
	var out:=Label.new();out.text=text;out.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(out);return out
func page(title: String) -> VBoxContainer:
	var out:=VBoxContainer.new();out.add_theme_constant_override("separation",12);content.add_child(out);pages[title]=out;out.hide();return out
func _ready() -> void:
	layer=40;developer=not game.construction_inventory.gameplay;game.help.hide()
	panel=PanelContainer.new();panel.position=Vector2(220,65);panel.size=Vector2(1480,860);add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.045,0.05,0.98)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(edge,24)
	panel.add_theme_stylebox_override("panel",style)
	var root:=VBoxContainer.new();root.add_theme_constant_override("separation",14);panel.add_child(root)
	label(root,"TERRAFOREST / ACTIONS").add_theme_font_size_override("font_size",26)
	mode_label=label(root,"")
	var columns:=HBoxContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;columns.add_theme_constant_override("separation",24);root.add_child(columns)
	var sidebar:=VBoxContainer.new();sidebar.custom_minimum_size.x=240;columns.add_child(sidebar)
	for title in ["Session","Toolbelt","Building","Objects","Vegetation","Development","Roads","Water"]:
		navigation[title]=button(sidebar,title,show_page.bind(title))
	button(sidebar,"Inventory / crafting",open_inventory)
	button(sidebar,"Return to world",func():set_open(false))
	scroll=ScrollContainer.new();scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;columns.add_child(scroll)
	content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(content)
	var session:=page("Session")
	label(session,"Your world").add_theme_font_size_override("font_size",22)
	label(session,"Choose equipment or configure an action here, then return to the world to aim and use it. Building and Objects keep their detailed settings in this same window.")
	button(session,"Save world",save_world)
	button(session,"Load saved world",func():confirm("Discard unsaved changes and reload?",reload_world))
	inventory_button=button(session,"Inventory / crafting",open_inventory)
	button(session,"Headlamp on / off",func():game.headlamp.toggle();refresh())
	mode_button=button(session,"Development mode",toggle_developer)
	button(session,"Save and quit",func():confirm("Save this world and quit?",func():game._notification(NOTIFICATION_WM_CLOSE_REQUEST)))
	if not world_browser_path.is_empty():button(session,"World browser",func():confirm("Leave this temporary world and discard its changes?" if game.temporary_world else "Save this world and return to the world browser?",leave_to_browser))
	var equipment:=page("Toolbelt")
	label(equipment,"Quick-use tools and items").add_theme_font_size_override("font_size",22)
	label(equipment,"Every belt slot is selectable. Empty slots put your tools away. Materials can be held without activating an editor. Use Inventory to drag items into the ten belt slots.")
	var grid:=GridContainer.new();grid.columns=2;equipment.add_child(grid)
	for i in 10:
		var choice:=button(grid,"",choose_slot.bind(i));choice.custom_minimum_size.x=460;belt_choices.append(choice)
	for id in DESCRIPTIONS:label(equipment,DESCRIPTIONS[id])
	label(equipment,"E always interacts with the aimed chest, vehicle or collectible. Tool actions use the mouse; menus configure them.")
	var nature:=page("Vegetation")
	label(nature,"Plants and stones").add_theme_font_size_override("font_size",22)
	label(nature,"E gathers reachable ground cover with empty hands or any tool. Select an owned stack below to place it; right mouse plants/places one. Development permits free placement.")
	for i in game.player_hud.GroundCatalog.COUNT:button(nature,game.player_hud.GroundCatalog.NAMES[i],choose_plant.bind(i))
	var water_editor=preload("res://addons/volumetric_water/lake_editor.gd").new();water_editor.game=game;page("Water").add_child(water_editor)
	dev_box=page("Development")
	label(dev_box,"Editor controls - separate from inventory").add_theme_font_size_override("font_size",22)
	label(dev_box,"Choose a terrain brush here. Building and Objects open the full editor palettes; Roads retains grading and street controls. None of these controls occupies an inventory slot.")
	var row:=HBoxContainer.new();dev_box.add_child(row)
	button(row,"Sculpt sphere",editor_tool.bind(3));button(row,"Sculpt box",editor_tool.bind(4));button(row,"Voxel cube",editor_tool.bind(1));button(row,"Grid box",editor_tool.bind(2))
	button(row,"Blocks / shapes",show_page.bind("Building"));button(row,"Objects / transforms",show_page.bind("Objects"))
	var radius:=SpinBox.new();brush_radius=radius;radius.min_value=0.25;radius.max_value=64;radius.step=0.25;radius.value=game.radius;radius.prefix="Brush radius (m) ";dev_box.add_child(radius)
	radius.value_changed.connect(func(value: float):game.radius=value)
	var material:=OptionButton.new();for title in ["Stone","Wood","Metal"]:material.add_item(title)
	dev_box.add_child(material);material.item_selected.connect(func(index: int):game.material_id=index+1)
	row=HBoxContainer.new();dev_box.add_child(row)
	fly_button=button(row,"Flight",toggle_flight)
	button(row,"Diagnostics",func():run_command(KEY_F3))
	button(row,"Place vehicle",func():run_command(KEY_V))
	button(row,"Carve lake at aim",func():run_command(KEY_L))
	row=HBoxContainer.new();dev_box.add_child(row)
	button(row,"Place actor",func():run_command(KEY_J));button(row,"Select / send actor",func():run_command(KEY_K))
	button(row,"Remove actor",func():run_command(KEY_J,true));button(row,"Stop actor",func():run_command(KEY_K,true))
	var options:=GridContainer.new();options.columns=3;dev_box.add_child(options)
	for entry in [["Next test site",KEY_F2],["Next biome",KEY_F4],["LOD colours",KEY_F6],["Grass texture",KEY_F7],["Debug light",KEY_F8],["Terrain visualization",KEY_F10]]:
		button(options,entry[0],run_command.bind(entry[1]))
	button(dev_box,"Reset world...",func():confirm("Erase this world state and generate it again?",func():set_open(false);game.terrain.reload_world(true)))
	button(dev_box,"Return to gameplay",toggle_developer)
	message=label(root,"")
	confirmation=ConfirmationDialog.new();confirmation.confirmed.connect(func():pending_action.call());add_child(confirmation)
	game.terrain.save_completed.connect(func(ok: bool):message.text="World saved" if ok else "Temporary world; changes are not saved" if game.temporary_world else "Save failed; check world status")
	game.player_hud.actions_requested.connect(func():set_open(true))
	game.player_hud.developer_tool_requested.connect(activate_developer_slot)
	game.player_hud.developer_belt=developer;game.player_hud.refresh()
	developer_hud=preload("res://addons/player_runtime/developer_hud.gd").new();developer_hud.game=game;add_child(developer_hud)
	panel.hide();refresh();dock_palettes.call_deferred()
func dock_palettes() -> void:
	for pair in [["Building",game.construction_palette.panel],["Objects",game.model_tool.panel],["Roads",game.road_palette.panel]]:
		var host:=page(pair[0]);label(host,"Configure here, then Return to world to aim and use the mouse.")
		var source: Control=pair[1];source.reparent(host);source.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		source.position=Vector2.ZERO;source.size=Vector2.ZERO;source.custom_minimum_size=Vector2.ZERO;source.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		docked[pair[0]]=source
	ready_to_dock=true;sync_panels()
	developer_hud.displayed_slot=-1;developer_hud.refresh()
func visible_ui() -> bool:return opened or workspace
func set_open(value: bool) -> void:
	var changing_focus: bool=value or visible_ui() or game.storage.opened or game.player_hud.inventory_open
	game.storage.close();game.player_hud.set_open(false)
	workspace=false;opened=value;panel.visible=value
	game.player_hud.inventory_open=value;game.player_hud.enabled=not value
	if changing_focus:game._clear_motion()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	if value:current_page="Session"
	refresh();sync_panels()
func show_page(title: String) -> void:
	if title in ["Development","Roads","Water"] and not developer:return
	if title in ["Building","Objects","Roads"]:
		if not ready_to_dock:return
		if game.world_vehicle.driving:message.text="Exit the vehicle before choosing building tools.";return
		set_open(false)
		if developer:
			game.player_hud.developer_slot={"Building":3,"Objects":4,"Roads":6}[title];game.player_hud.active_slot=-1;game.player_hud.active_item=0;game.editor_tool_active=true;game.equipped_tool=0;game.tool_view.equip(0)
			if game.structure_mode!=(title!="Roads") or game.model_tool.active!=(title=="Objects"):
				game._set_player_tool_mode(title!="Roads",title=="Objects",game.tool)
		elif game.equipped_tool!=(3 if title=="Building" else 4) and not game.player_hud.equip_item(3 if title=="Building" else 4):
			set_open(true);message.text="You need a "+game.player_hud.CATALOG[3 if title=="Building" else 4]+" in your inventory.";return
		workspace=true;opened=false;panel.show();game.player_hud.enabled=false;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;game._clear_motion()
	else:
		if not opened:set_open(true)
	current_page=title;refresh();sync_panels()
func sync_panels() -> void:
	if not ready_to_dock:return
	for title in pages:pages[title].visible=visible_ui() and title==current_page
	for title in docked:docked[title].visible=workspace and title==current_page
	for control in game.construction_palette.editor_controls:control.visible=developer
func refresh() -> void:
	if developer_hud!=null:developer_hud.refresh()
	mode_label.text=("DEVELOPMENT / free authoring" if developer else "GAMEPLAY / items and material costs")+"    |    Headlamp: "+("on" if game.headlamp.visible else "off")
	mode_button.text="Return to gameplay" if developer else "Enter development (~)"
	fly_button.text="Flight: "+("on" if game.fly else "off")
	for title in ["Development","Roads","Water"]:navigation[title].visible=developer
	for title in navigation:navigation[title].modulate=Color(0.65,1,0.8) if title==current_page else Color.WHITE
	inventory_button.disabled=game.world_vehicle.driving
	var state: Dictionary=game.player_hud.inventory.snapshot()
	for i in belt_choices.size():
		var item: int=state.slots[i].item
		belt_choices[i].text="%d  %s"%[(i+1)%10,game.player_hud.CATALOG.get(item,game.player_hud.MATERIALS.get(item,game.player_hud.RESOURCES.get(item,"Empty hands")))]
		if developer:belt_choices[i].text="%d  %s"%[(i+1)%10,game.player_hud.DEV_TOOLS[i]]
		belt_choices[i].disabled=game.world_vehicle.driving
func choose_slot(slot: int) -> void:
	set_open(false);game.player_hud.equip(slot)
func choose_plant(species: int) -> void:
	if not game.ground_enabled:message.text="Ground cover is disabled in this launch.";return
	set_open(false)
	if developer:
		game.player_hud.active_slot=-1;game.player_hud.active_item=0;game.equipped_tool=0;game.tool_view.equip(0)
		game.player_hud.developer_slot=5;game.editor_tool_active=true;game._activate_ground_tool(species)
	elif not game.player_hud.equip_item(game.player_hud.GroundCatalog.ITEMS[species]):
		set_open(true);message.text="Gather this plant or stone first; its stack must be in your inventory."
func editor_tool(tool: int) -> void:
	if not developer:return
	set_open(false);game.player_hud.active_slot=-1;game.player_hud.active_item=0;game.editor_tool_active=true;game.equipped_tool=0;game.tool_view.equip(0)
	game.player_hud.developer_slot={3:0,2:1,1:2}.get(tool,0);game.radius=brush_radius.value;game._set_player_tool_mode(false,false,tool)
func open_inventory() -> void:
	if game.world_vehicle.driving:message.text="Exit the vehicle before opening inventory.";return
	set_open(false);game.player_hud.set_open(true)
func toggle_developer() -> void:
	if game.loading_active or game.shutdown_requested or game.site_preparation.status=="running" or game.site_survey.busy or not game._foundation_placement.is_empty() or not game.road_palette.pending.is_empty() or not game.road_authoring.phase.is_empty() or game.terrain.pending_edit or game.construction_inventory.busy or not game.construction_inventory.pending_prefab.is_empty():
		message.text="Wait for the current world edit to finish.";return
	if not developer:gameplay_slot=game.player_hud.active_slot
	developer=not developer
	game.construction_inventory.gameplay=not developer;game.model_tool.gameplay=not developer;game.player_hud.gameplay_construction=not developer;game.mining_rewards.enabled=not developer
	if not developer:game.fly=false
	var had_ui:=visible_ui();set_open(false)
	game.player_hud.developer_belt=developer;game.player_hud.active_slot=-1;game.player_hud.active_item=0;game._equip_player_tool(0)
	if developer:activate_developer_slot(game.player_hud.developer_slot)
	elif gameplay_slot>=0:game.player_hud.equip(gameplay_slot)
	game.player_hud.refresh()
	if had_ui:set_open(true)
	refresh()
func activate_developer_slot(slot: int) -> void:
	if not developer or game.world_vehicle.driving:return
	game.player_hud.developer_slot=slot
	match slot:
		0:editor_tool(3)
		1:editor_tool(2)
		2:editor_tool(1)
		3,4:
			set_open(false);game.editor_tool_active=true;game.equipped_tool=0;game.tool_view.equip(0)
			game._set_player_tool_mode(true,slot==4,game.tool)
		5:choose_plant(maxi(0,game.player_hud.ground_species))
		6,7,8:
			set_open(false);game._equip_player_tool(0)
			game.player_hud.editor_hint="DEVELOPMENT | "+({6:"Roads",7:"World tools",8:"Actors"}[slot])+" | Esc: configure"
		_:
			set_open(false);game._equip_player_tool(0)
	game.player_hud.refresh();refresh()

func toggle_flight() -> void:
	if not developer or game.world_vehicle.driving:return
	game.fly=not game.fly;game.player.velocity=Vector3.ZERO;game._cancel_edit_input();refresh()
func confirm(text: String,action: Callable) -> void:
	pending_action=action;confirmation.dialog_text=text;confirmation.popup_centered(Vector2i(450,160))
func save_world() -> void:
	if game.world_vehicle.driving and not game.world_vehicle.safe_exit_position(game).is_finite():message.text="Park beside clear ground before saving.";return
	game.terrain.save_world();message.text="Saving..."
func reload_world() -> void:set_open(false);game.terrain.reload_world(false)
func leave_to_browser() -> void:
	if world_browser_path.is_empty() or not ResourceLoader.exists(world_browser_path):
		message.text="No world browser is configured by this project.";return
	if leaving_world or game.shutdown_requested:return
	if game.loading_active or not game.terrain.world_ready or game.terrain.stopping:
		message.text="Wait for world loading before leaving.";return
	if game.world_vehicle.driving and not game.world_vehicle.safe_exit_position(game).is_finite():
		message.text="Park beside clear ground before saving.";return
	leaving_world=true;panel.process_mode=Node.PROCESS_MODE_DISABLED
	game.shutdown_requested=true;game._cancel_edit_input();game._clear_motion()
	if not game.temporary_world:
		message.text="Saving before returning to worlds..."
		var result:={"received":false,"ok":false}
		var listener:=func(ok: bool):result.received=true;result.ok=ok
		game.terrain.save_completed.connect(listener)
		game.terrain.save_world()
		var deadline:=Time.get_ticks_msec()+30000
		while not result.received and game.terrain.latest_error.is_empty() and Time.get_ticks_msec()<deadline:
			await get_tree().process_frame
		game.terrain.save_completed.disconnect(listener)
		if not result.received or not result.ok:
			leaving_world=false;panel.process_mode=Node.PROCESS_MODE_INHERIT;game.shutdown_requested=false
			message.text="Save did not complete. Staying in this world; retry after checking world status.";return
	# Load the browser resource before stopping workers so a missing resource
	# leaves the current session usable.
	var browser=load(world_browser_path)
	if browser==null:
		leaving_world=false;panel.process_mode=Node.PROCESS_MODE_INHERIT;game.shutdown_requested=false;message.text="World browser could not be loaded.";return
	game._close_journal()
	await game.terrain.shutdown_after_edits()
	get_tree().change_scene_to_packed(browser)
func run_command(key: int,shift: bool=false) -> void:
	if not developer:return
	set_open(false);var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=key;event.shift_pressed=shift;game._unhandled_input(event)
func _input(event: InputEvent) -> void:
	if leaving_world:
		get_viewport().set_input_as_handled();return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if not visible_ui() and not game.player_hud.inventory_open and not game.storage.opened and not game.world_vehicle.driving and not game.loading_active and game.app_focused and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
			var slot: int=game.player_hud.developer_slot if developer else game.player_hud.active_slot
			var step:=1 if event.button_index==MOUSE_BUTTON_WHEEL_DOWN else -1
			game.player_hud.equip(posmod(slot+step,10) if slot>=0 and slot<10 else (0 if step>0 else 9))
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or event.echo:return
	if event.physical_keycode==KEY_QUOTELEFT:
		if event.pressed:tilde_down=Time.get_ticks_msec();tilde_chord=false
		elif tilde_down>=0:
			if not tilde_chord:
				if Time.get_ticks_msec()-tilde_down>=450:
					if not developer:toggle_developer()
					toggle_flight()
				else:toggle_developer()
			tilde_down=-1;tilde_chord=false
		get_viewport().set_input_as_handled();return
	# Consume chords before gameplay input; F must never reach the headlamp.
	if tilde_down>=0:
		# Movement releases must reach the controller while the chord is held.
		if event.physical_keycode in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SPACE,KEY_SHIFT,KEY_CTRL]:return
		if event.pressed:
			tilde_chord=true
			if event.physical_keycode==KEY_F:
				if not developer:toggle_developer()
				toggle_flight()
		get_viewport().set_input_as_handled();return
	if event.pressed and event.physical_keycode==KEY_ESCAPE:
		if confirmation.visible:confirmation.hide()
		elif game.storage.opened:game.storage.close()
		elif game.player_hud.inventory_open and not opened:game.player_hud.set_open(false)
		elif not visible_ui() and developer and game.player_hud.developer_slot in [6,7]:show_page("Roads" if game.player_hud.developer_slot==6 else "Development")
		else:set_open(not visible_ui())
		get_viewport().set_input_as_handled();return
	if visible_ui() or (developer_hud.mouse_access and Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED):return
	if event.pressed and not game.player_hud.inventory_open:
		if event.physical_keycode==KEY_G:
			if not developer and game.player_hud.active_slot>=0 and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
				game._drop_inventory_supply(game.player_hud.active_slot,game.player_hud.inventory.snapshot().revision,1)
			get_viewport().set_input_as_handled();return
		if event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8,KEY_9,KEY_0]:
			game.player_hud.equip(9 if event.physical_keycode==KEY_0 else event.physical_keycode-KEY_1);get_viewport().set_input_as_handled()
		elif (event.ctrl_pressed and event.physical_keycode==KEY_R) or event.physical_keycode in [KEY_M,KEY_B,KEY_H,KEY_P,KEY_T,KEY_G] or (not developer and event.physical_keycode in [KEY_F2,KEY_F3,KEY_F4,KEY_F6,KEY_F7,KEY_F8,KEY_F10,KEY_J,KEY_K,KEY_V,KEY_L]):
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:tilde_down=-1;tilde_chord=false
