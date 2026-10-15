# SPDX-License-Identifier: 0BSD
extends CanvasLayer
var game: Node
var panel: PanelContainer
var content: VBoxContainer
var hidden_by_user:=false
var mouse_access:=false
var displayed_slot:=-1
var title: Label
func _ready() -> void:
	layer=25;panel=PanelContainer.new();panel.position=Vector2(1570,200);panel.custom_minimum_size=Vector2(324,0);add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.05,0.05,0.88)
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,14)
	panel.add_theme_stylebox_override("panel",style)
	content=VBoxContainer.new();content.add_theme_constant_override("separation",10);panel.add_child(content)
	game.player_hud.menu_changed.connect(func(_value: bool):refresh())
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
	if not game.session_menu.developer:mouse_access=false
	var was_visible:=panel.visible
	panel.visible=game.session_menu.developer and not hidden_by_user and not game.session_menu.visible_ui() and not game.player_hud.inventory_open
	var slot: int=game.player_hud.developer_slot
	if displayed_slot==slot and (was_visible or not panel.visible):return
	displayed_slot=slot
	for child in content.get_children():content.remove_child(child);child.queue_free()
	title=label("DEVELOPMENT / "+game.player_hud.DEV_TOOLS[slot]);title.add_theme_color_override("font_color",Color("83d6b2"))
	label("Hold Alt to use controls
F1 hide / show this panel")
	match slot:
		0,1,2:
			label("Left mouse: remove
Right mouse: fill")
			if slot!=2:number("Radius (m)",game.radius,0.25,64,0.25,func(v: float):game.radius=v;game.session_menu.brush_radius.set_value_no_signal(v))
			option("Material",["Stone","Wood","Metal"],game.material_id-1,func(i: int):game.material_id=i+1)
		3:
			label("Left mouse: remove
Right mouse: place")
			option("Shape",["Cube","Slab","Stairs","Slope","Post","Sphere","Round column"],game.structure_shape-1,func(i: int):game._construction_selection("shape",i))
			option("Material",["Brick","Wood","Concrete","Metal"],game.structure_material,func(i: int):game._construction_selection("material",i))
			option("Rotation",["0 degrees","90 degrees","180 degrees","270 degrees"],game.structure_rotation,func(i: int):game._construction_selection("rotation",i))
			button("Prefabs / detailed settings",func():game.session_menu.show_page("Building"))
		4:
			label("Left mouse: remove
Right mouse: place")
			var names: Array=[]
			for entry in game.model_tool.catalog:names.append(entry.title)
			option("Object",names,game.model_tool.selected,func(i: int):game.model_tool.select(i))
			button("Transforms / detailed settings",func():game.session_menu.show_page("Objects"))
		5:
			label("Left mouse: remove
Right mouse: plant / place")
			option("Species",game.player_hud.GroundCatalog.NAMES,game.ground_species,func(i: int):game._activate_ground_tool(i))
		6:
			label("Mark two points, then build.
Esc opens the complete road editor.")
			number("Width (m)",game.road_palette.width.value,1,32,0.5,func(v: float):game.road_palette.width.value=v)
			button("Mark start at aim",func():game._road_action("start"))
			button("Mark end at aim",func():game._road_action("finish"))
			button("Road grading / build",func():game.session_menu.show_page("Roads"))
		7:
			button("Flight on / off",game.session_menu.toggle_flight)
			button("Save world",game.session_menu.save_world)
			button("Water / lakes",func():game.session_menu.show_page("Water"))
			button("World / generation settings",func():game.session_menu.show_page("Development"))
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
				button("Save world",game.session_menu.save_world)
		_:
			label("No development tool selected.")
func _input(event: InputEvent) -> void:
	if not game.session_menu.developer:return
	if event is InputEventKey and event.physical_keycode==KEY_SPACE and not game.session_menu.visible_ui() and not game.player_hud.inventory_open:
		game.controls.set_key(KEY_SPACE,event.pressed,Time.get_ticks_usec());get_viewport().set_input_as_handled();return
	if event is InputEventKey and event.physical_keycode==KEY_F1 and event.pressed and not event.echo:
		hidden_by_user=not hidden_by_user;refresh();get_viewport().set_input_as_handled()
	if event is InputEventKey and event.physical_keycode==KEY_ALT and not event.echo and not game.session_menu.visible_ui() and not game.player_hud.inventory_open:
		mouse_access=event.pressed
		if not mouse_access:
			var focus:=get_viewport().gui_get_focus_owner()
			if focus!=null:focus.release_focus()
			for child in content.get_children():
				if child is OptionButton:child.get_popup().hide()
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if mouse_access else Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:mouse_access=false
