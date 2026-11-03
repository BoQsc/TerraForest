# SPDX-License-Identifier: 0BSD
extends ScrollContainer
## ItemList-compatible trading list with mockup-style rows.
signal item_selected(index:int)
const Row=preload("res://addons/player_runtime/trade_row.gd")
var trade:Node
var side:="merchant"
var item_count:=0
var selected:=-1
var entries:Array[Dictionary]=[]
var rows:Array=[] 
var content:VBoxContainer

func _ready()->void:
	horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	focus_mode=Control.FOCUS_ALL
	content=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",6);add_child(content)

func add_item(text:String,icon:Texture2D=null,detail:String="",price:String="",stock:String="")->void:
	entries.append({"text":text,"icon":icon,"detail":detail,"price":price,"stock":stock,"metadata":0,"tooltip":text,"color":Color.WHITE})
	var row=Row.new();row.list=self;row.index=item_count
	row.setup(self,item_count,text,icon,detail,price,stock)
	content.add_child(row);rows.append(row);item_count+=1

func clear()->void:
	for row in rows:
		if is_instance_valid(row):row.queue_free()
	rows.clear();entries.clear();item_count=0;selected=-1

func select(index:int)->void:
	selected=index if index>=0 and index<item_count else -1
	for row in rows:row.set_selected(row.index==selected)

func activate(index:int)->void:
	select(index)
	item_selected.emit(index)

func get_selected_items()->PackedInt32Array:
	return PackedInt32Array([selected]) if selected>=0 else PackedInt32Array()

func get_item_metadata(index:int)->int:
	return int(entries[index].metadata) if index>=0 and index<entries.size() else 0

func set_item_metadata(index:int,value:int)->void:
	if index>=0 and index<entries.size():entries[index].metadata=value

func get_item_text(index:int)->String:
	return str(entries[index].text) if index>=0 and index<entries.size() else ""

func set_item_tooltip(index:int,tooltip:String)->void:
	if index<0 or index>=entries.size():return
	entries[index].tooltip=tooltip;rows[index].set_tooltip(tooltip)

func set_item_custom_fg_color(index:int,color:Color)->void:
	if index<0 or index>=entries.size():return
	entries[index].color=color;rows[index].set_tint(color)

func ensure_current_is_visible()->void:
	if selected>=0 and selected<rows.size():ensure_control_visible(rows[selected])

func get_item_at_position(at:Vector2,_exact:bool=false)->int:
	var point:=get_global_transform()*at
	for row in rows:
		if row.get_global_rect().has_point(point):return row.index
	return -1

func drag_offer(index:int)->Dictionary:
	return trade.drag_offer(side,index)

func _get_drag_data(at:Vector2)->Variant:
	var index:=get_item_at_position(at,true)
	if index<0:return null
	return rows[index]._get_drag_data(at)

func _can_drop_data(_at:Vector2,data:Variant)->bool:
	return trade.accepts_drop(side,data)

func _drop_data(_at:Vector2,data:Variant)->void:
	trade.drop_data(side,data)
