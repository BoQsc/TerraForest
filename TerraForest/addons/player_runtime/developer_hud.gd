# SPDX-License-Identifier: 0BSD
extends CanvasLayer
var game: Node
var panel: PanelContainer
var content: VBoxContainer
var hidden_by_user:=false
var mouse_access:=false
var resume_mouse_after_focus:=false
var displayed_slot:=-1
var displayed_developer:=false
var title: Label
func context_slot()->int:
	if game.session_menu.developer:return game.player_hud.developer_slot
	if game.equipped_tool in game.player_hud.MATERIALS:return 3
	if game.equipped_tool==4:return 4
	if game.ground_mode:return 5
	return -1
func _ready() -> void:
	layer=25;panel=PanelContainer.new();panel.position=Vector2(1570,200);panel.custom_minimum_size=Vector2(324,0);add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.05,0.05,0.88)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,14)
	panel.add_theme_stylebox_override("panel",style)
	content=VBoxContainer.new();content.add_theme_constant_override("separation",10);panel.add_child(content)
	game.player_hud.menu_changed.connect(func(_value: bool):refresh())
	get_window().focus_entered.connect(_restore_mouse_after_focus,CONNECT_DEFERRED)
	refresh()
func label(text: String) -> Label:
	var out:=Label.new();out.text=text;out.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;out.custom_minimum_size.x=290;content.add_child(out);return out
func button(text: String,action: Callable) -> void:
	var out:=Button.new();out.text=text;out.focus_mode=Control.FOCUS_NONE;out.pressed.connect(action);content.add_child(out)
func option(text: String,values: Array,index: int,action: Callable) -> void:
	label(text);var out:=OptionButton.new();out.focus_mode=Control.FOCUS_NONE
	for entry in values:out.add_item(str(entry))
	out.select(maxi(0,index));out.item_selected.connect(action);content.add_child(out)
func number(text: String,value: float,minimum: float,maximum: float,step: float,action: Callable) -> void:
	label(text);var out:=SpinBox.new();out.min_value=minimum;out.max_value=maximum;out.step=step;out.value=value;out.value_changed.connect(action);content.add_child(out)
func refresh() -> void:
	if panel==null:return
	var was_visible:=panel.visible
	var slot:int=context_slot()
	panel.visible=slot>=0 and not hidden_by_user and not game.session_menu.visible_ui() and not game.player_hud.inventory_open and not game.storage.opened and not game.loading_active and not game.world_vehicle.driving
	if slot<0:return
	if displayed_slot==slot and displayed_developer==game.session_menu.developer and (was_visible or not panel.visible):return
	displayed_slot=slot;displayed_developer=game.session_menu.developer
	for child in content.get_children():content.remove_child(child);child.queue_free()
	title=label(("DEVELOPMENT / " if game.session_menu.developer else "TOOL / ")+game.player_hud.DEV_TOOLS[slot]);title.add_theme_color_override("font_color",Color("83d6b2"))
	label("Hold Alt to use controls
F1 hide / show this panel")
	match slot:
		0,1,2:
			label("Left mouse: remove
Right mouse: fill")
			if slot==1:option("Box mode",["Grid box","Sculpt box"],1 if game.tool==4 else 0,func(i:int):game._set_player_tool_mode(false,false,2 if i==0 else 4))
			if slot!=2:number("Radius (m)",game.radius,0.25,64,0.25,func(v: float):game.radius=v)
			option("Material",["Stone","Wood","Metal"],game.material_id-1,func(i: int):game.material_id=i+1)
		3:
			label(("Left mouse: remove" if game.session_menu.developer else "Left mouse: attack")+"\nRight mouse: place")
			option("Shape",["Cube","Slab","Stairs","Slope","Post","Sphere","Round column"],game.structure_shape-1,func(i: int):game._construction_selection("shape",i))
			option("Material",["Brick","Wood","Concrete","Metal"],game.structure_material,func(i: int):game._construction_selection("material",i))
			option("Rotation",["0 degrees","90 degrees","180 degrees","270 degrees"],game.structure_rotation,func(i: int):game._construction_selection("rotation",i))
			button("Prefabs / detailed settings",game.session_menu.open_current_tool)
			label("Prefab outline: red means blocked; amber means placement checks are pending; green means block space is clear. Materials are checked when placing.")
		4:
			label(("Left mouse: remove" if game.session_menu.developer else "Left mouse: attack")+"\nRight mouse: place")
			var names: Array=[]
			for entry in game.model_tool.catalog:names.append(entry.title)
			option("Object",names,game.model_tool.selected,func(i: int):game.model_tool.select(i))
			button("Transforms / detailed settings",game.session_menu.open_current_tool)
		5:
			label(("Left mouse: remove" if game.session_menu.developer else "E: collect")+"\nRight mouse: plant / place")
			option("Species",game.player_hud.GroundCatalog.NAMES,game.ground_species,func(i: int):
				if game.session_menu.developer:game._activate_ground_tool(i)
				else:game.session_menu.choose_plant(i)
				displayed_slot=-1;refresh())
		6:
			label("Mark two points, then build.
Hold Alt for grading and build controls.")
			number("Width (m)",game.road_palette.width.value,1,32,0.5,func(v: float):game.road_palette.width.value=v)
			button("Mark start at aim",func():game._road_action("start"))
			button("Mark end at aim",func():game._road_action("finish"))
			button("Road grading / build",game.session_menu.open_current_tool)
		7:
			button("Flight on / off",game.session_menu.toggle_flight)
			button("Place vehicle at aim",func():game.session_menu.run_command(KEY_V))
			button("Water / lakes",func():game.session_menu.open_tool_page("Water"))
			button("World tools / diagnostics",game.session_menu.open_current_tool)
		8:
			label("Aim at the world, then hold Alt and click an action. Release Alt to look around.")
			if game.actors.pool==null:
				button("Enable actor simulation",func():
					if not game.actors.enable():game._show_lake_notice("Could not enable actors.")
					displayed_slot=-1;refresh())
			else:
				button("Place actor at aim",func():game.session_menu.run_command(KEY_J))
				button("Select / send at aim",func():game.session_menu.run_command(KEY_K))
				button("Patrol to aim",func():game.session_menu.patrol_actor())
				button("Stop selected actor",func():game.session_menu.run_command(KEY_K,true))
				button("Remove actor at aim",func():game.session_menu.run_command(KEY_J,true))
				label("Select an actor, then aim at ground. Select / send walks once; Patrol to aim repeats between its current position and that point (1-16 m). Stop clears either order.")
				button("Actor settings / residents",game.session_menu.open_current_tool)
		_:
			label("No development tool selected.")
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode==KEY_ALT and not event.pressed and mouse_access:
		end_mouse_access()
		if not game.session_menu.visible_ui() and not game.player_hud.inventory_open and not game.storage.opened:Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.physical_keycode==KEY_ALT and event.pressed and not event.echo and not game.session_menu.visible_ui() and not game.player_hud.inventory_open:
		if game.loading_active or game.storage.opened or game.world_vehicle.driving or not game.app_focused:return
		game._cancel_edit_input()
		mouse_access=true;Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;get_viewport().set_input_as_handled();return
	if context_slot()<0:return
	if game.session_menu.developer and event is InputEventKey and event.physical_keycode==KEY_SPACE and not game.session_menu.visible_ui() and not game.player_hud.inventory_open:
		game.controls.set_key(KEY_SPACE,event.pressed,Time.get_ticks_usec());get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.physical_keycode==KEY_F1 and event.pressed and not event.echo:
		hidden_by_user=not hidden_by_user;refresh();get_viewport().set_input_as_handled()
func end_mouse_access()->void:
	mouse_access=false
	var focus:=get_viewport().gui_get_focus_owner()
	if focus!=null and panel.is_ancestor_of(focus):focus.release_focus()
	for child in content.get_children():
		if child is OptionButton:child.get_popup().hide()
func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		# Alt's release may go to another application. End the temporary UI lease,
		# then restore aiming only after focus returns and real menus are checked.
		resume_mouse_after_focus=resume_mouse_after_focus or mouse_access
		end_mouse_access()
	elif what==NOTIFICATION_APPLICATION_FOCUS_IN and resume_mouse_after_focus:
		_restore_mouse_after_focus.call_deferred()
func _restore_mouse_after_focus()->void:
	if not resume_mouse_after_focus or not game.app_focused:return
	resume_mouse_after_focus=false
	if game.loading_active or game.shutdown_requested or game.session_menu.visible_ui() or game.player_hud.inventory_open or game.storage.opened:return
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
