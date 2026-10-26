# SPDX-License-Identifier: 0BSD
extends CanvasLayer
const Mouse=preload("res://addons/world_runtime/mouse_ownership.gd")
# Session/global actions and input focus. Tool controls live in tool_workspace.gd.
# Optional host-owned destination; standalone addons do not depend on demo scenes.
var world_browser_path: String=""
var world_page_factory:Callable
var world_map:CanvasLayer
var game: Node
var opened:=false
var workspace:=false
var developer:=false
var gameplay_slot:=-1
var developer_hud: CanvasLayer
var tool_workspace:CanvasLayer
var tilde_down:=-1
var tilde_chord:=false
var panel: PanelContainer
var mode_label: Label
var session_message:Label
var message:Label:
	get:return tool_workspace.message if workspace and tool_workspace!=null else session_message
var mode_button: Button
var third_person_toggle:CheckButton
var fullscreen_toggle:CheckButton
var player_actions:CanvasLayer
var impact_toggle:CheckButton
var breakup_toggle:CheckButton
var impact_style:OptionButton
var confirmation: ConfirmationDialog
var pending_action: Callable
var leaving_world:=false
var pages: Dictionary={}
var navigation: Dictionary={}
var current_page:="Session"
var scroll: ScrollContainer
var content: VBoxContainer
var ready_to_dock:=false
var spawner:RefCounted
var dev_bag:RefCounted
const DESCRIPTIONS={1:"Pickaxe: hold left mouse to attack or dig. Most effective on stone.",2:"Hatchet: hold left mouse to attack or dig. Most effective on wood.",3:"Repair hammer: left mouse attacks; right mouse repairs damaged blocks, objects and vehicles at swing contact.",4:"Assembly tool: left mouse attacks the aimed target; right mouse places the selected object.",5:"Shovel: hold left mouse to dig terrain or attack, with a two-handed thrust and lift.",6:"Wooden torch: a burning survival light. Equip to carry it; switch slots to put it away. G drops it."}
func button(parent: Node,text: String,action: Callable) -> Button:
	var out:=Button.new();out.text=text;out.custom_minimum_size.y=40;out.pressed.connect(action);parent.add_child(out);return out
func label(parent: Node,text: String) -> Label:
	var out:=Label.new();out.text=text;out.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(out);return out
func page(title: String) -> VBoxContainer:
	var out:=VBoxContainer.new();out.add_theme_constant_override("separation",12);content.add_child(out);pages[title]=out;out.hide();return out
func _ready() -> void:
	layer=40;developer=not game.construction_inventory.gameplay;game.help.hide()
	panel=PanelContainer.new();panel.position=Vector2(380,100);panel.size=Vector2(1160,800);add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.045,0.05,0.98)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(edge,24)
	panel.add_theme_stylebox_override("panel",style)
	var root:=VBoxContainer.new();root.add_theme_constant_override("separation",14);panel.add_child(root)
	label(root,"TERRAFOREST / SESSION").add_theme_font_size_override("font_size",26)
	mode_label=label(root,"")
	var columns:=HBoxContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;columns.add_theme_constant_override("separation",24);root.add_child(columns)
	var sidebar:=VBoxContainer.new();sidebar.custom_minimum_size.x=220;columns.add_child(sidebar)
	navigation["Session"]=button(sidebar,"Session",show_page.bind("Session"))
	navigation["Graphics"]=button(sidebar,"Graphics",show_page.bind("Graphics"))
	navigation["Dev Bag"]=button(sidebar,"Dev Bag",show_page.bind("Dev Bag"))
	navigation["Dev Spawner"]=button(sidebar,"Dev Spawner",show_page.bind("Dev Spawner"))
	navigation["Developer"]=button(sidebar,"Developer",show_page.bind("Developer"))
	if world_page_factory.is_valid():navigation["World"]=button(sidebar,"Destinations",show_page.bind("World"))
	button(sidebar,"Resume  ·  Esc",func():set_open(false))
	scroll=ScrollContainer.new();scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;columns.add_child(scroll)
	content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(content)
	if world_page_factory.is_valid():page("World").add_child(world_page_factory.call())
	var session:=page("Session")
	var graphics:=page("Graphics")
	label(graphics,"Graphics").add_theme_font_size_override("font_size",22)
	fullscreen_toggle=CheckButton.new();fullscreen_toggle.text="Fullscreen (off: windowed)"
	fullscreen_toggle.toggled.connect(func(enabled:bool):game.Presentation.set_fullscreen(game.get_window(),enabled,not game.temporary_world));graphics.add_child(fullscreen_toggle)
	label(session,"Your session").add_theme_font_size_override("font_size",22)
	label(session,"Hold Alt for tool controls. Tab: inventory · M: map (keep moving) · Ctrl: crouch · Hold `: player actions · Tap `: development belt.")
	button(session,"Save world",save_world)
	button(session,"Load saved world",func():confirm("Discard unsaved changes and reload?",reload_world))
	button(session,"Headlamp on / off",func():game.headlamp.toggle();refresh())
	third_person_toggle=CheckButton.new();third_person_toggle.text="Third-person camera"
	third_person_toggle.toggled.connect(game.player_view.set_enabled);session.add_child(third_person_toggle)
	var grid_settings:=VBoxContainer.new();grid_settings.name="BuildingGridFit";session.add_child(grid_settings)
	label(grid_settings,"Building-grid fit").add_theme_font_size_override("font_size",20)
	label(grid_settings,"Placement preference. Terrain and road generation preferences are grouped under Building-grid fit when creating a world.")
	var burial_toggle:=CheckButton.new();burial_toggle.text="Prefer embedding when it improves block fit"
	burial_toggle.tooltip_text="Keeps the integer grid. Never bury a cube more than 60 cm or replace a gap of 10 cm or less with deeper burial. Does not alter terrain or intentionally floating face placement."
	var burial_settings:=ConfigFile.new()
	var persist_burial:bool=not game.temporary_world and not ProjectSettings.get_setting("terraforest/offscreen_session",false)
	if persist_burial and burial_settings.load("user://building_preferences.cfg")==OK:game.prefer_block_burial=bool(burial_settings.get_value("building","prefer_embedding",true))
	burial_toggle.button_pressed=game.prefer_block_burial
	burial_toggle.toggled.connect(func(enabled:bool):
		game.prefer_block_burial=enabled
		if persist_burial:burial_settings.set_value("building","prefer_embedding",enabled);burial_settings.save("user://building_preferences.cfg"))
	grid_settings.add_child(burial_toggle)
	var developer_page:=page("Developer")
	label(developer_page,"Developer / diagnostics & experiments").add_theme_font_size_override("font_size",22)
	label(developer_page,"Global debugging and experimental settings. Item grants live in Dev Bag; living entities live in Dev Spawner. Selected-tool controls remain on Alt.")
	mode_button=button(developer_page,"Development mode",toggle_developer)
	var diagnostics:=GridContainer.new();diagnostics.columns=2;developer_page.add_child(diagnostics)
	for entry in [["Diagnostics",KEY_F3],["Next test site",KEY_F2],["Next biome",KEY_F4],["LOD colours",KEY_F6],["Grass texture",KEY_F7],["Debug light",KEY_F8],["Terrain visualization",KEY_F10]]:
		button(diagnostics,entry[0],developer_command.bind(entry[1]))
	var target_toggle:=CheckButton.new();target_toggle.text="Show targeting visuals for all tools / weapons (testing)"
	target_toggle.button_pressed=game.target_overlay.enabled
	target_toggle.toggled.connect(game.target_overlay.set_enabled);developer_page.add_child(target_toggle)
	if game.get("impact_effects")!=null:
		impact_toggle=CheckButton.new();impact_toggle.text="Impact particles (experimental)"
		impact_toggle.toggled.connect(game.impact_effects.set_enabled);developer_page.add_child(impact_toggle)
		var style_row:=HBoxContainer.new();developer_page.add_child(style_row)
		label(style_row,"Impact appearance").size_flags_horizontal=Control.SIZE_EXPAND_FILL
		impact_style=OptionButton.new();impact_style.add_item("Grounded");impact_style.add_item("Original baseline")
		impact_style.item_selected.connect(game.impact_effects.set_style);style_row.add_child(impact_style)
		breakup_toggle=CheckButton.new();breakup_toggle.text="Extra particles when objects break"
		breakup_toggle.toggled.connect(game.impact_effects.set_breakup_enabled);developer_page.add_child(breakup_toggle)
		game.impact_effects.settings_changed.connect(refresh_effects);refresh_effects()
	dev_bag=preload("res://addons/player_runtime/developer_bag.gd").new();dev_bag.build(game,self,page("Dev Bag"))
	spawner=preload("res://addons/player_runtime/developer_spawn.gd").new();spawner.build(game,self,page("Dev Spawner"))
	if not world_browser_path.is_empty():button(session,"World browser",func():confirm("Leave this temporary world and discard its changes?" if game.temporary_world else "Save this world and return to the world browser?",leave_to_browser))
	button(session,"Save and quit",func():game._notification(NOTIFICATION_WM_CLOSE_REQUEST))
	session_message=label(root,"")
	confirmation=ConfirmationDialog.new();confirmation.confirmed.connect(func():pending_action.call());add_child(confirmation)
	game.terrain.save_completed.connect(func(ok: bool):message.text="World saved" if ok else "Temporary world; changes are not saved" if game.temporary_world else "Save failed; check world status")
	game.player_hud.actions_requested.connect(func():set_open(true))
	game.player_hud.developer_tool_requested.connect(activate_developer_slot)
	game.player_hud.developer_belt=developer;game.player_hud.refresh()
	tool_workspace=preload("res://addons/player_runtime/tool_workspace.gd").new();tool_workspace.game=game;tool_workspace.menu=self;add_child(tool_workspace)
	developer_hud=preload("res://addons/player_runtime/developer_hud.gd").new();developer_hud.game=game;add_child(developer_hud)
	player_actions=preload("res://addons/player_runtime/player_actions.gd").new();player_actions.game=game;player_actions.menu=self;add_child(player_actions)
	panel.hide();refresh();dock_palettes.call_deferred()
func dock_palettes() -> void:
	for pair in [["Building",game.construction_palette.panel],["Objects",game.model_tool.panel],["Roads",game.road_palette.panel]]:tool_workspace.dock(pair[0],pair[1])
	ready_to_dock=true;sync_panels()
	developer_hud.displayed_slot=-1;developer_hud.refresh()
func refresh_effects()->void:
	impact_toggle.set_pressed_no_signal(game.impact_effects.enabled)
	breakup_toggle.set_pressed_no_signal(game.impact_effects.breakup_enabled)
	breakup_toggle.disabled=not game.impact_effects.enabled
	impact_style.select(game.impact_effects.style);impact_style.disabled=not game.impact_effects.enabled
func visible_ui() -> bool:return opened or workspace or (world_map!=null and world_map.opened)
func pauses_world()->bool:return opened or workspace or (player_actions!=null and player_actions.opened)
func set_open(value: bool) -> void:
	if value and player_actions!=null:player_actions.cancel()
	if value and world_map!=null and world_map.opened:world_map.set_open(false)
	var changing_focus: bool=value or visible_ui() or game.storage.opened or game.player_hud.inventory_open
	if changing_focus and developer_hud!=null:developer_hud.end_mouse_access()
	game.storage.close();game.player_hud.set_open(false)
	workspace=false;opened=value;panel.visible=value
	game.player_hud.inventory_open=value;game.player_hud.enabled=not value
	if changing_focus:game._clear_motion()
	Mouse.set_mode(game,Input.MOUSE_MODE_VISIBLE if value or (developer_hud!=null and developer_hud.mouse_access) else Input.MOUSE_MODE_CAPTURED)
	if value:current_page="Session"
	refresh();sync_panels()
func show_page(title: String) -> void:
	# Compatibility for addon callers; tool pages never enter the session window.
	if title=="Development":title="World tools"
	if title in tool_workspace.pages:open_tool_page(title);return
	if not pages.has(title):return
	if not opened:set_open(true)
	current_page=title;session_message.text="";scroll.set_deferred("scroll_vertical",0);refresh();sync_panels()
	if title=="Dev Spawner":spawner.refresh()
func open_tool_page(title:String) -> void:
	if not ready_to_dock or not tool_workspace.pages.has(title):return
	if title=="Building" and not developer and game.equipped_tool not in game.player_hud.MATERIALS:return
	if title in ["Terrain","Roads","World tools","Actors","Water"] and not developer:return
	if game.world_vehicle.driving:message.text="Exit the vehicle before configuring tools.";return
	if game.loading_active or game.shutdown_requested:return
	if title in ["Building","Objects"]:
		set_open(false)
		if developer:activate_developer_slot(3 if title=="Building" else 4)
		elif title=="Objects" and game.equipped_tool!=4 and not game.player_hud.equip_item(4):
			game._show_lake_notice("Equip an owned assembly tool first.");return
	elif developer:
		var slot:int={"Terrain":game.player_hud.developer_slot if game.player_hud.developer_slot in [0,1,2] else 0,"Vegetation":5,"Roads":6,"World tools":7,"Water":7,"Actors":8}[title]
		if title!="Terrain" or not game.editor_tool_active or game.player_hud.developer_slot not in [0,1,2]:activate_developer_slot(slot)
	set_open(false);workspace=true;current_page=title
	game.player_hud.enabled=false;Mouse.set_mode(game,Input.MOUSE_MODE_VISIBLE);game._clear_motion()
	developer_hud.end_mouse_access();refresh();sync_panels()
func open_current_tool() -> void:
	var slot:int=developer_hud.context_slot()
	if slot>=0 and slot<tool_workspace.SLOT_PAGES.size():
		var title:String=tool_workspace.SLOT_PAGES[slot]
		if not title.is_empty():open_tool_page(title)
func sync_panels() -> void:
	for title in pages:pages[title].visible=opened and title==current_page
	if tool_workspace==null:return
	tool_workspace.panel.visible=workspace
	for title in tool_workspace.docked:tool_workspace.docked[title].visible=workspace and title==current_page
	for control in game.construction_palette.editor_controls:control.visible=developer
	if workspace:tool_workspace.show_tool(current_page)
func refresh() -> void:
	fullscreen_toggle.set_pressed_no_signal(DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN])
	mode_label.text=("DEVELOPMENT / free authoring" if developer else "GAMEPLAY / items and material costs")+"    |    Headlamp: "+("on" if game.headlamp.visible else "off")
	mode_button.text="Return to gameplay" if developer else "Enter development (~)"
	for title in navigation:navigation[title].modulate=Color(0.65,1,0.8) if title==current_page else Color.WHITE
	if developer_hud!=null:developer_hud.refresh()
func choose_plant(species: int) -> void:
	if not game.ground_enabled:message.text="Ground cover is disabled in this launch.";return
	set_open(false)
	if developer:
		game.player_hud.active_slot=-1;game.player_hud.active_item=0;game.equipped_tool=0;game.tool_view.equip(0)
		game.player_hud.developer_slot=5;game.editor_tool_active=true;game._activate_ground_tool(species)
	elif not game.player_hud.equip_item(game.player_hud.GroundCatalog.ITEMS[species]):
		game._show_lake_notice("Gather this plant or stone first; its stack must be in your inventory.")
func editor_tool(tool: int) -> void:
	if not developer:return
	set_open(false);game.player_hud.active_slot=-1;game.player_hud.active_item=0;game.editor_tool_active=true;game.equipped_tool=0;game.tool_view.equip(0)
	game.player_hud.developer_slot={3:0,2:1,4:1,1:2}.get(tool,0);game._set_player_tool_mode(false,false,tool)
func open_inventory() -> void:
	if game.world_vehicle.driving:message.text="Exit the vehicle before opening inventory.";return
	set_open(false);game.player_hud.set_open(true)
func toggle_developer() -> void:
	if game.loading_active or game.shutdown_requested or game.site_preparation.status=="running" or game.site_survey.busy or not game._foundation_placement.is_empty() or not game.road_palette.pending.is_empty() or not game.road_authoring.phase.is_empty() or game.terrain.pending_edit or game.construction_inventory.busy or not game.construction_inventory.pending_prefab.is_empty():
		message.text="Wait for the current world edit to finish.";return
	if not developer:gameplay_slot=game.player_hud.active_slot
	session_message.text=""
	developer=not developer
	game.construction_inventory.gameplay=not developer;game.model_tool.gameplay=not developer;game.player_hud.gameplay_construction=not developer;game.mining_rewards.enabled=not developer
	if not developer:game.fly=false
	developer_hud.end_mouse_access()
	var had_ui:=visible_ui();set_open(false)
	game.player_hud.developer_belt=developer;game.player_hud.active_slot=-1;game.player_hud.active_item=0;game._equip_player_tool(0)
	if developer:activate_developer_slot(game.player_hud.developer_slot)
	elif gameplay_slot>=0:game.player_hud.equip(gameplay_slot)
	else:game.player_hud.equip_first_tool_if_unselected()
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
			game.player_hud.editor_hint="DEVELOPMENT | "+({6:"Roads",7:"World tools",8:"Actors"}[slot])+" | Hold Alt: tool controls"
		_:
			set_open(false);game._equip_player_tool(0)
	game.player_hud.refresh();refresh()

func toggle_flight() -> void:
	if game.world_vehicle.driving or game.loading_active or game.shutdown_requested:return
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
func populate_settlement() -> void:
	if not developer:return
	set_open(false)
	game._populate_settlement_actors()
func patrol_actor() -> void:
	if not developer:return
	set_open(false)
	game._show_lake_notice(game.actor_authoring.command(game,false,true))
func run_command(key: int,shift: bool=false) -> void:
	if not developer:return
	set_open(false);var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=key;event.shift_pressed=shift;game._unhandled_input(event)
func developer_command(key:int)->void:
	if not developer:message.text="Enter development mode above to use world diagnostics.";return
	run_command(key)
func _input(event: InputEvent) -> void:
	if opened and event is InputEventKey and event.physical_keycode!=KEY_ESCAPE:
		var focused:=get_viewport().gui_get_focus_owner()
		if focused is LineEdit or focused is TextEdit:return
	if game.vehicle_radial.consume(event):get_viewport().set_input_as_handled();return
	if player_actions!=null and player_actions.consume(event):get_viewport().set_input_as_handled();return
	if world_map!=null and world_map.opened:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_M,KEY_ESCAPE]:world_map.set_open(false)
		if event is InputEventKey and event.physical_keycode not in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SPACE,KEY_CTRL,KEY_SHIFT]:get_viewport().set_input_as_handled()
		return
	if world_map!=null and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_M and tilde_down<0:
		world_map.set_open(true);get_viewport().set_input_as_handled();return

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
		elif workspace:set_open(false)
		else:set_open(not visible_ui())
		get_viewport().set_input_as_handled();return
	if workspace:
		# GUI gets typing, dropdowns and scrolling; world keys never reach tools.
		return
	if visible_ui() or (developer_hud.mouse_access and Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED):return
	if event.pressed and not game.player_hud.inventory_open:
		if event.physical_keycode==KEY_G:
			if not developer and game.player_hud.active_slot>=0 and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
				game._drop_inventory_supply(game.player_hud.active_slot,game.player_hud.inventory.snapshot().revision,1)
			get_viewport().set_input_as_handled();return
		if event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8,KEY_9,KEY_0]:
			game.player_hud.equip(9 if event.physical_keycode==KEY_0 else event.physical_keycode-KEY_1);get_viewport().set_input_as_handled()
		elif (event.ctrl_pressed and event.physical_keycode==KEY_R) or event.physical_keycode in [KEY_B,KEY_H,KEY_P,KEY_T,KEY_G] or (not developer and event.physical_keycode in [KEY_F2,KEY_F3,KEY_F4,KEY_F6,KEY_F7,KEY_F8,KEY_F10,KEY_J,KEY_K,KEY_V,KEY_L]):
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:tilde_down=-1;tilde_chord=false
