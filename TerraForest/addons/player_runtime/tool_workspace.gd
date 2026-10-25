# SPDX-License-Identifier: 0BSD
extends CanvasLayer
# Tool configuration owns its own window; the session menu only manages focus.
var game:Node
var menu:CanvasLayer
var panel:PanelContainer
var heading:Label
var mode:Label
var message:Label
var pages:Dictionary={}
var docked:Dictionary={}
var fly_button:Button
var radius:SpinBox
var material:OptionButton
var box_mode:OptionButton
var actors:VBoxContainer
var scroll:ScrollContainer
var current_page:=""
const SLOT_PAGES=["Terrain","Terrain","Terrain","Building","Objects","Vegetation","Roads","World tools","Actors",""]
func _ready()->void:
	layer=35
	panel=PanelContainer.new();panel.name="ToolWorkspace";add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.05,0.05,0.98);style.border_color=Color("407b69")
	style.border_width_top=2
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(edge,20)
	panel.add_theme_stylebox_override("panel",style)
	var root:=VBoxContainer.new();root.add_theme_constant_override("separation",12);panel.add_child(root)
	mode=menu.label(root,"");mode.add_theme_color_override("font_color",Color("83d6b2"))
	var row:=HBoxContainer.new();root.add_child(row)
	heading=menu.label(row,"");heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_theme_font_size_override("font_size",24)
	menu.button(row,"Back to world  ·  Esc",func():menu.set_open(false))
	menu.label(root,"Configure the selected tool here. Close to aim and use it; hold Alt for the quick controls beside your toolbelt.")
	scroll=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO;root.add_child(scroll)
	var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(content)
	for name in ["Terrain","Building","Objects","Vegetation","Roads","World tools","Actors","Water"]:
		var page:=VBoxContainer.new();page.add_theme_constant_override("separation",12);content.add_child(page);pages[name]=page;page.hide()
	menu.label(pages.Terrain,"Brush settings")
	radius=SpinBox.new();radius.min_value=0.25;radius.max_value=64;radius.step=0.25;radius.prefix="Radius (m)  ";pages.Terrain.add_child(radius)
	radius.value_changed.connect(func(value:float):game.radius=value)
	box_mode=OptionButton.new();box_mode.add_item("Grid box");box_mode.add_item("Sculpt box");pages.Terrain.add_child(box_mode)
	box_mode.item_selected.connect(func(index:int):game._set_player_tool_mode(false,false,2 if index==0 else 4);menu.developer_hud.displayed_slot=-1)
	material=OptionButton.new()
	for name in ["Stone","Wood","Metal"]:material.add_item(name)
	pages.Terrain.add_child(material);material.item_selected.connect(func(index:int):game.material_id=index+1)
	menu.label(pages.Terrain,"Left mouse removes terrain; right mouse fills. Choose sphere, box or voxel cube with development belt slots 1–3.")
	menu.label(pages.Vegetation,"Choose a plant or stone, then close this window and right-click to place it. E gathers reachable ground cover.")
	for i in game.player_hud.GroundCatalog.COUNT:menu.button(pages.Vegetation,game.player_hud.GroundCatalog.NAMES[i],menu.choose_plant.bind(i))
	var world:VBoxContainer=pages["World tools"]
	menu.label(world,"World authoring")
	fly_button=menu.button(world,"Flight",menu.toggle_flight)
	menu.button(world,"Vehicles / Dev Bag",func():menu.show_page("Dev Bag"))
	menu.button(world,"Water / lakes",func():menu.open_tool_page("Water"))
	menu.button(world,"Global diagnostics / Developer",func():menu.show_page("Developer"))
	menu.label(world,"Reset")
	menu.button(world,"Reset this world…",func():menu.confirm("Erase this world state and generate it again?",func():menu.set_open(false);game.terrain.reload_world(true)))
	actors=pages.Actors;rebuild_actors()
	var water_editor=preload("res://addons/volumetric_water/lake_editor.gd").new();water_editor.game=game;pages.Water.add_child(water_editor)
	message=menu.label(root,"")
	panel.hide();get_viewport().size_changed.connect(layout);layout()
func layout()->void:
	var viewport:=get_viewport().get_visible_rect().size
	var width:=minf(980,viewport.x-56)
	panel.position=Vector2(viewport.x-width-28,60);panel.size=Vector2(width,maxf(300,viewport.y-220))
func dock(name:String,source:Control)->void:
	source.reparent(pages[name]);source.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	source.position=Vector2.ZERO;source.size=Vector2.ZERO;source.custom_minimum_size=Vector2.ZERO;source.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	docked[name]=source
func show_tool(name:String)->void:
	if current_page!=name:
		current_page=name;scroll.set_deferred("scroll_vertical",0);message.text=""
	for key in pages:pages[key].visible=key==name
	mode.text="DEVELOPMENT / TOOL SETTINGS" if menu.developer else "TOOL SETTINGS / GAMEPLAY"
	heading.text=game.player_hud.DEV_TOOLS[game.player_hud.developer_slot] if name=="Terrain" else name
	radius.set_value_no_signal(game.radius);radius.visible=game.player_hud.developer_slot!=2
	box_mode.visible=name=="Terrain" and game.player_hud.developer_slot==1;box_mode.select(1 if game.tool==4 else 0)
	material.select(game.material_id-1)
	fly_button.text="Flight: "+("on" if game.fly else "off")
	if name=="Actors":rebuild_actors()
	panel.show()
	layout.call_deferred()
func rebuild_actors()->void:
	for child in actors.get_children():actors.remove_child(child);child.queue_free()
	menu.label(actors,"Aim first, then hold Alt and use the actor controls. Orders act on the selected actor.")
	if game.actors.pool==null:
		menu.button(actors,"Enable actor simulation",func():
			if not game.actors.enable():game._show_lake_notice("Could not enable actors.")
			rebuild_actors();menu.developer_hud.displayed_slot=-1;menu.developer_hud.refresh())
		return
	for entry in [["Place actor at aim",KEY_J,false],["Select / send at aim",KEY_K,false],["Stop selected actor",KEY_K,true],["Remove actor at aim",KEY_J,true]]:
		menu.button(actors,entry[0],menu.run_command.bind(entry[1],entry[2]))
	menu.button(actors,"Patrol to aim",menu.patrol_actor)
	if game.has_method("_populate_settlement_actors"):menu.button(actors,"Add residents to nearby street",menu.populate_settlement)
