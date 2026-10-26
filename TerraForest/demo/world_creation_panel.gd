extends RefCounted
const INK:=Color("e6eee7")
const MUTED:=Color("9bafad")
const ACCENT:=Color("91d5b4")
static func box(color:Color,border:Color=Color("2b4245"),radius:int=8)->StyleBoxFlat:
 var style:=StyleBoxFlat.new();style.bg_color=color;style.border_color=border
 style.set_border_width_all(1);style.set_corner_radius_all(radius)
 style.content_margin_left=16;style.content_margin_right=16;style.content_margin_top=10;style.content_margin_bottom=10
 return style
static func apply_theme(host:Control)->void:
 var theme:=Theme.new();theme.default_font_size=18
 for type:String in ["Label","Button","CheckBox","OptionButton","LineEdit","ItemList","TabContainer"]:theme.set_color("font_color",type,INK)
 theme.set_color("font_placeholder_color","LineEdit",MUTED)
 for type:String in ["Button","OptionButton","LineEdit","SpinBox"]:
  theme.set_stylebox("normal",type,box(Color("1b3035")))
  theme.set_stylebox("hover",type,box(Color("29484a"),ACCENT))
  theme.set_stylebox("pressed",type,box(Color("304f4e"),ACCENT))
  var focus:=box(Color.TRANSPARENT,ACCENT);focus.set_border_width_all(2);theme.set_stylebox("focus",type,focus)
 theme.set_stylebox("panel","TabContainer",box(Color("102126")))
 theme.set_stylebox("tab_selected","TabContainer",box(Color("22423f"),Color("577d6c")))
 theme.set_stylebox("tab_unselected","TabContainer",box(Color("15282d")))
 theme.set_stylebox("panel","ItemList",box(Color("14292e")))
 theme.set_color("font_unselected_color","TabContainer",MUTED)
 for state:String in ["normal","hover","pressed","hover_pressed","disabled"]:theme.set_stylebox(state,"CheckBox",box(Color.TRANSPARENT,Color.TRANSPARENT,0))
 theme.set_constant("separation","VBoxContainer",10);theme.set_constant("separation","HBoxContainer",12)
 host.theme=theme
static func label(parent:Node,text:String,size:int=18,color:Color=INK)->Label:
 var node:=Label.new();node.text=text;node.add_theme_font_size_override("font_size",size);node.add_theme_color_override("font_color",color);parent.add_child(node);return node
static func paragraph(parent:Node,text:String,size:int=16)->Label:
 var node:=label(parent,text,size,MUTED);node.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;return node
static func section(parent:Node,number:String,title:String)->void:
 var row:=HBoxContainer.new();parent.add_child(row)
 label(row,number,16,ACCENT);label(row,title,21)
static func choice(parent:Node,title:String,items:Array)->OptionButton:
 var row:=HBoxContainer.new();parent.add_child(row)
 var caption:=label(row,title,16,MUTED);caption.custom_minimum_size.x=146
 var option:=OptionButton.new();option.custom_minimum_size.y=42;option.fit_to_longest_item=false;option.clip_text=true;option.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(option)
 for item:String in items:option.add_item(item);option.set_item_tooltip(option.item_count-1,item)
 return option
static func category(tabs:TabContainer,title:String)->VBoxContainer:
 var scroll:=ScrollContainer.new();scroll.name=title;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;tabs.add_child(scroll)
 var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",12);scroll.add_child(column)
 return column
static func build(host:Control,tabs:TabContainer)->void:
 var page:=VBoxContainer.new();page.name="Create world";page.add_theme_constant_override("separation",18);tabs.add_child(page)
 var header:=HBoxContainer.new();page.add_child(header)
 var intro:=VBoxContainer.new();intro.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(intro)
 label(intro,"Shape your next world",30)
 paragraph(intro,"Plan a landscape. Connect its settlements. Make it yours.",18)
 label(header,"2 × 2 km  /  VOLUMETRIC WORLD",16,ACCENT)
 var body:=HBoxContainer.new();body.add_theme_constant_override("separation",24);body.size_flags_vertical=Control.SIZE_EXPAND_FILL;page.add_child(body)
 var left:=VBoxContainer.new();left.custom_minimum_size.x=500;left.add_theme_constant_override("separation",12);body.add_child(left)
 var settings:=left
 section(settings,"01","World identity")
 host.name_field=LineEdit.new();host.name_field.placeholder_text="World name · or leave blank";host.name_field.max_length=48;host.name_field.custom_minimum_size.y=42;settings.add_child(host.name_field)
 var seed_row:=HBoxContainer.new();settings.add_child(seed_row)
 host.seed_field=SpinBox.new();host.seed_field.min_value=0;host.seed_field.max_value=2147483647;host.seed_field.step=1;host.seed_field.value=1703;host.seed_field.prefix="Seed ";host.seed_field.size_flags_horizontal=Control.SIZE_EXPAND_FILL;seed_row.add_child(host.seed_field)
 host.shuffle_button=Button.new();host.shuffle_button.text="Shuffle";host.shuffle_button.tooltip_text="Choose a new seed without changing your recipe.";seed_row.add_child(host.shuffle_button);host.shuffle_button.pressed.connect(func():host.seed_field.value=randi_range(0,2147483647))
 var categories:=TabContainer.new();categories.size_flags_vertical=Control.SIZE_EXPAND_FILL;left.add_child(categories)
 settings=category(categories,"Landscape");section(settings,"02","Landscape & biomes")
 host.preset=OptionButton.new();settings.add_child(host.preset)
 for identity:int in host.Launch.PRESETS:
  if identity==host.Launch.INTEGRATED_PRESET or "--developer-worlds" in OS.get_cmdline_user_args():host.preset.add_item(host.Launch.PRESETS[identity],identity)
 host.preset.visible="--developer-worlds" in OS.get_cmdline_user_args()
 host.biome=choice(settings,"Vegetation biome",["Woodland","Woodland & meadow mosaic","Open grassland with groves"])
 paragraph(settings,"Coherent forest boundaries and open ground; the same native field drives tree placement and the preview.")
 host.ocean=CheckBox.new();host.ocean.text="Ocean coastline & beaches";host.ocean.button_pressed=true;settings.add_child(host.ocean)
 var grid_panel:=PanelContainer.new();grid_panel.name="BuildingGridFit";grid_panel.add_theme_stylebox_override("panel",box(Color("1b2b30")));settings.add_child(grid_panel)
 var grid_settings:=VBoxContainer.new();grid_panel.add_child(grid_settings)
 label(grid_settings,"Building-grid fit",20,ACCENT)
 paragraph(grid_settings,"Generation preferences · new worlds only",15)
 host.buildable_ground=CheckBox.new();host.buildable_ground.text="Terrain";host.buildable_ground.button_pressed=true;grid_settings.add_child(host.buildable_ground)
 host.buildable_ground.tooltip_text="Softly raise low ground and lower high ground toward shallow grid contact in eligible gentle terrain. Steep slopes and protected shores stay natural. The 1 m building grid, floating construction and terrain editing stay unchanged."
 host.buildable_roads=CheckBox.new();host.buildable_roads.text="Roads & shoulders";host.buildable_roads.button_pressed=true;grid_settings.add_child(host.buildable_roads)
 host.buildable_roads.tooltip_text="Plan roads and their support beds against building-block footprints before baking. Protect entrances and terrain-fit budgets. No terrain changes when placing blocks; gaps or deeper embedding can still occur on transitions."
 settings=category(categories,"Settlements");section(settings,"03","Settlements & connections")
 host.settlement_count=choice(settings,"Settlements",["1 · isolated community","2 · linked communities","3 · regional network"]);host.settlement_count.select(1)
 host.district_count=choice(settings,"Settlement scale",["Compact · 1 district each","Expanded · 2 districts each"])
 host.road_network=choice(settings,"Regional roads",["Direct connections","Network + alternate route"])
 host.offroads=choice(settings,"Unpaved offroads",["None","Up to 1 per district","Up to 2 per district"]);host.offroads.select(1)
 paragraph(settings,"All districts connect. Additional routes and trails depend on safe terrain. Roads remain editable; sidewalks remain individual flat plates.")
 var future:=PanelContainer.new();future.add_theme_stylebox_override("panel",box(Color("1b2b30")));settings.add_child(future)
 paragraph(future,"Cities are planned for a later stage. Expanded settlements use the current building catalogue, not a finished city generator.")
 var map_panel:=PanelContainer.new();map_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;map_panel.add_theme_stylebox_override("panel",box(Color("14282d")));body.add_child(map_panel)
 var map_column:=VBoxContainer.new();map_column.add_theme_constant_override("separation",14);map_panel.add_child(map_column)
 var map_heading:=HBoxContainer.new();map_column.add_child(map_heading)
 var title:=label(map_heading,"REGIONAL SURVEY",16,ACCENT);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 label(map_heading,"N ↑",20)
 var map_space:=Control.new();map_space.custom_minimum_size=Vector2(320,100);map_space.size_flags_vertical=Control.SIZE_EXPAND_FILL;map_column.add_child(map_space)
 host.preview_view=TextureRect.new();host.preview_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.preview_view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;host.preview_view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;map_space.add_child(host.preview_view)
 host.preview_empty=Label.new();host.preview_empty.text="YOUR WORLD STARTS HERE\n\nChoose a seed and recipe. The preview updates automatically.\nTerrain, buildings, roads and water are planned together.";host.preview_empty.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;host.preview_empty.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;host.preview_empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;host.preview_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.preview_empty.add_theme_color_override("font_color",MUTED);map_space.add_child(host.preview_empty)
 var legend:=HBoxContainer.new();legend.alignment=BoxContainer.ALIGNMENT_CENTER;map_column.add_child(legend)
 label(legend,"■ Woodland",16,Color("8fb38c"));label(legend,"■ Roads / trails",16,Color("dec386"));label(legend,"■ Buildings",16,INK);label(legend,"■ Water",16,Color("76b8d0"))
 host.preview_metrics=label(map_column,"READY TO PLAN  ·  Native terrain fitting  ·  Cached generation",16,ACCENT);host.preview_metrics.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
 host.preview_status=paragraph(map_column,"The preview uses the actual placement plan, not a decorative map. Existing worlds are never changed.",17)
 host.preparation_panel=preload("res://addons/world_runtime/loading_panel.gd").new();host.preparation_panel.embedded=true;page.add_child(host.preparation_panel)
 host.preparation_panel.show_idle()
 host.recipe_summary=host.preparation_panel.work
 host.generate_button=host.preparation_panel.action;host.generate_button.text="Generate & play"
 host.cancel_button=host.generate_button
 host.generate_button.pressed.connect(func():
  if host.preparation_pid>=0:host.cancel_preparation()
  else:host.launch_selected(true))
 var actions:HBoxContainer=host.generate_button.get_parent()
 host.preview_button=host.generate_button.duplicate(0);host.preview_button.text="Refresh preview";host.preview_button.pressed.connect(host.start_preview)
 actions.add_child(host.preview_button);actions.move_child(host.preview_button,host.generate_button.get_index())
 for option:OptionButton in [host.preset,host.biome,host.settlement_count,host.district_count,host.road_network,host.offroads]:option.item_selected.connect(func(_index:int):host.invalidate_preview())
 host.ocean.toggled.connect(func(_value:bool):host.invalidate_preview())
 host.buildable_ground.toggled.connect(func(_value:bool):host.invalidate_preview())
 host.buildable_roads.toggled.connect(func(_value:bool):host.invalidate_preview())
 host.seed_field.value_changed.connect(func(_value:float):host.invalidate_preview())
 host.preset.item_selected.connect(func(_index:int):
  var supported:bool=host.preset.get_selected_id()==host.Launch.INTEGRATED_PRESET
  host.ocean.visible=supported;grid_panel.visible=supported
  for option:OptionButton in [host.biome,host.settlement_count,host.district_count,host.road_network,host.offroads]:option.disabled=not supported)
 host.update_recipe_summary()
 host.invalidate_preview()
