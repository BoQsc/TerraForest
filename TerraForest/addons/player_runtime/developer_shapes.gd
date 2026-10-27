extends RefCounted

const Catalog=preload("res://addons/structures/shape_catalog.gd")
const Icons=preload("res://addons/player_runtime/shape_icons.gd")
const MATERIALS=["Brick","Wood","Concrete","Metal"]
var game:Node
var menu:CanvasLayer
var search:LineEdit
var category:OptionButton
var material:OptionButton
var count:SpinBox
var summary:Label
var empty:Label
var entries:Dictionary={}
var equipped_shapes:Dictionary={}

func build(host:Node,session:CanvasLayer,parent:VBoxContainer)->void:
	game=host;menu=session
	menu.label(parent,"Dev Shapes").add_theme_font_size_override("font_size",24)
	menu.label(parent,"Click a native block shape to get free materials and equip it for placement. Works in gameplay and development.")
	var filters:=HBoxContainer.new();parent.add_child(filters)
	search=LineEdit.new();search.placeholder_text="Search shapes by name or ID…";search.clear_button_enabled=true;search.size_flags_horizontal=Control.SIZE_EXPAND_FILL;filters.add_child(search)
	category=OptionButton.new()
	for title:String in ["All shapes","Blocks & round pieces","Frame & arch pieces","Roof pieces"]:category.add_item(title)
	filters.add_child(category)
	var options:=HBoxContainer.new();options.add_theme_constant_override("separation",12);parent.add_child(options)
	var material_label:Label=menu.label(options,"Material");material_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	material=OptionButton.new();material.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for title:String in MATERIALS:material.add_item(title)
	options.add_child(material)
	count=SpinBox.new();count.custom_minimum_size.x=140;count.min_value=1;count.max_value=999;count.value=64;count.prefix="Qty ";options.add_child(count)
	menu.label(parent,"Uses shared material stacks, not separate items. One destructible grid cell per piece; combine pieces for arches/frames. R turns · Shift+R tips. Shape choices last for this session.")
	summary=menu.label(parent,"")
	var grid:=GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);parent.add_child(grid)
	for shape in range(1,Catalog.NAMES.size()+1):
		var tile:=Button.new();tile.custom_minimum_size=Vector2(0,100);tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tile.text="%s\n#%d"%[Catalog.NAMES[shape-1],shape];tile.icon=Icons.texture(shape);tile.expand_icon=true;tile.add_theme_constant_override("icon_max_width",72);tile.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		tile.tooltip_text="Get materials and use "+Catalog.NAMES[shape-1]+" · native single-cell block";tile.pressed.connect(use_shape.bind(shape));grid.add_child(tile);entries[shape]=tile
	empty=menu.label(parent,"No matching shapes. Clear the search or choose another category.")
	search.text_changed.connect(func(_value:String):filter_shapes());category.item_selected.connect(func(_index:int):filter_shapes());refresh()

func shape_category(shape:int)->int:return 1 if shape<=9 else (2 if shape<=11 else 3)
func shape_for_material(item:int)->int:return int(equipped_shapes.get(item,1))
func refresh()->void:
	material.select(clampi(game.structure_material,0,3));filter_shapes()
func filter_shapes()->void:
	var query:=search.text.strip_edges().to_lower();var matches:=0
	for shape:int in entries:
		var found:bool=(category.selected==0 or category.selected==shape_category(shape)) and (query.is_empty() or query in Catalog.NAMES[shape-1].to_lower() or query in str(shape))
		entries[shape].visible=found
		if found:matches+=1
	empty.visible=matches==0;summary.text="%d / %d native shapes · Click to get & use"%[matches,entries.size()]

func use_shape(shape:int)->void:
	if not entries.has(shape):menu.message.text="Unknown block shape.";return
	if game.loading_active or game.shutdown_requested or game.benchmark_enabled or not game.terrain.world_ready or not game.app_focused:
		menu.message.text="Wait for the world to be ready.";return
	if game.world_vehicle.driving:menu.message.text="Exit the vehicle before equipping a building shape.";return
	if game.construction_inventory.busy or not game.construction_inventory.pending_prefab.is_empty() or game.site_preparation.status=="running":menu.message.text="Wait for the current construction to finish.";return
	var selected_material:=material.selected;var item:=101+selected_material;var quantity:=int(count.value)
	var hud:CanvasLayer=game.player_hud;var before:Dictionary=hud.inventory.snapshot()
	var granted:Dictionary=hud.inventory.grant(item,quantity,before.revision)
	if not granted.ok:menu.message.text="Not enough inventory space. Nothing was added or equipped.";return
	menu.set_open(false)
	if menu.developer:menu.activate_developer_slot(3)
	else:hud.equip_item(item)
	if not game.structure_mode or game.model_tool.active:
		hud.inventory.restore(before,hud.inventory.snapshot().revision);hud.refresh();menu.show_page("Dev Shapes");menu.message.text="Could not activate building. The material grant was restored.";return
	game._construction_selection("shape",shape-1);game._construction_selection("material",selected_material);game._construction_selection("rotation",0)
	equipped_shapes[item]=shape;game.terrain.changed_since_save=true;hud.refresh()
	game._show_lake_notice("%s · %s · added %d materials · Right mouse places · R rotates"%[Catalog.NAMES[shape-1],MATERIALS[selected_material],quantity])
