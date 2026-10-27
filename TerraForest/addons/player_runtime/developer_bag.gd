extends RefCounted
const Icons=preload("res://addons/player_runtime/item_icons.gd")
var game:Node
var menu:CanvasLayer
var search:LineEdit
var category:OptionButton
var count:SpinBox
var summary:Label
var empty:Label
var entries:Dictionary={}
var catalog:Dictionary={}
func build(host:Node,session:CanvasLayer,parent:VBoxContainer)->void:
	game=host;menu=session
	menu.label(parent,"Dev Bag").add_theme_font_size_override("font_size",24)
	menu.label(parent,"Click an item to add the chosen quantity to your inventory. These are free developer grants, even in gameplay mode. Carried vehicle items stay here; live vehicles and creatures belong in Dev Spawner.")
	var row:=HBoxContainer.new();parent.add_child(row)
	search=LineEdit.new();search.placeholder_text="Search items by name or ID…";search.clear_button_enabled=true;search.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(search)
	category=OptionButton.new()
	for title:String in ["All items","Tools","Building materials","Resources & plants","Clothing","Water containers","Vehicles"]:category.add_item(title)
	row.add_child(category)
	count=SpinBox.new();count.custom_minimum_size.x=120;count.min_value=1;count.max_value=999;count.value=1;count.prefix="Qty ";row.add_child(count)
	summary=menu.label(parent,"")
	var grid:=GridContainer.new();grid.columns=3;grid.add_theme_constant_override("h_separation",8);grid.add_theme_constant_override("v_separation",8);parent.add_child(grid)
	catalog.merge(game.player_hud.CATALOG);catalog.merge(game.player_hud.MATERIALS);catalog.merge(game.player_hud.RESOURCES)
	var identities:Array=catalog.keys();identities.sort()
	for item:int in identities:
		if item>=401 and item<=411:catalog[item]="Water bucket (empty)" if item==401 else "Water bucket (%d L)"%(item-401)
		var entry:=Button.new();entry.custom_minimum_size=Vector2(0,94);entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		entry.text="%s\n#%d"%[catalog[item],item];entry.icon=Icons.texture(item);entry.expand_icon=true;entry.add_theme_constant_override("icon_max_width",48)
		entry.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;entry.tooltip_text="Add to inventory: "+catalog[item];entry.pressed.connect(give.bind(item));grid.add_child(entry);entries[item]=entry
	empty=menu.label(parent,"No matching items. Clear the search or choose another category.")
	search.text_changed.connect(func(_value:String):filter_items());category.item_selected.connect(func(_index:int):filter_items());filter_items()
func item_category(item:int)->int:
	if game.player_hud.CATALOG.has(item):return 1
	if game.player_hud.MATERIALS.has(item):return 2
	if item<301:return 3
	if item<401:return 4
	if item<501:return 5
	return 6
func filter_items()->void:
	var query:=search.text.strip_edges().to_lower();var matches:=0
	for item:int in entries:
		var found:bool=(category.selected==0 or category.selected==item_category(item)) and (query.is_empty() or query in str(catalog[item]).to_lower() or query in str(item))
		entries[item].visible=found
		if found:matches+=1
	empty.visible=matches==0;summary.text="%d / %d items · Click to add · Full inventories are left unchanged"%[matches,catalog.size()]
func give(item:int)->void:
	if not catalog.has(item):menu.message.text="Unknown inventory item.";return
	if game.loading_active or game.shutdown_requested:menu.message.text="Wait for the world to be ready.";return
	var inventory:RefCounted=game.player_hud.inventory
	var quantity:=int(count.value)
	var result:Dictionary=inventory.grant(item,quantity,inventory.snapshot().revision)
	if not result.ok:
		menu.message.text="Not enough inventory space for %d × %s. Nothing was added."%[quantity,catalog[item]] if result.reason=="full" else "Could not add item: "+str(result.reason)
		return
	game.terrain.changed_since_save=true;game.player_hud.refresh()
	menu.message.text="Added %d × %s to your inventory. Tab opens your bag after resuming."%[quantity,catalog[item]]
