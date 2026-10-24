# SPDX-License-Identifier: 0BSD
extends VBoxContainer
# Event-driven presentation: a fixed pool, shared icons, no inventory polling.
const CAPACITY:=5
const DISPLAY_US:=3000000
const FADE_US:=450000
const Icons=preload("res://addons/player_runtime/item_icons.gd")
var allowed:Callable
var names:Dictionary={}
var previous:Dictionary={}
var initialized:=false
var pool:Array[Dictionary]=[]
var active:Array[Dictionary]=[]
func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE;alignment=BoxContainer.ALIGNMENT_END
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left=-344;offset_right=-24;offset_top=-330;offset_bottom=-72
	add_theme_constant_override("separation",6)
	for index in CAPACITY:
		var panel:=PanelContainer.new();panel.custom_minimum_size.y=42;panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var style:=StyleBoxFlat.new();style.bg_color=Color(.025,.055,.05,.82);style.set_corner_radius_all(5)
		style.set_content_margin_all(6);style.content_margin_left=9;style.content_margin_right=10
		panel.add_theme_stylebox_override("panel",style);add_child(panel)
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);row.mouse_filter=Control.MOUSE_FILTER_IGNORE;panel.add_child(row)
		var icon:=TextureRect.new();icon.custom_minimum_size=Vector2(30,30);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(icon)
		var label:=Label.new();label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_size_override("font_size",15);label.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(label)
		var amount:=Label.new();amount.add_theme_font_size_override("font_size",18);amount.add_theme_color_override("font_color",Color("91e4b9"))
		amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;amount.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_child(amount)
		pool.append({"panel":panel,"icon":icon,"label":label,"amount":amount,"item":0,"count":0,"expires_us":0});panel.hide()
	clear()
static func totals(inventory:Dictionary,equipment:Dictionary)->Dictionary:
	var result:Dictionary={}
	# Include worn clothing so equipping/unequipping cannot appear as a pickup.
	for state:Dictionary in [inventory,equipment]:
		for stack:Dictionary in state.get("slots",[]):
			var item:int=stack.item
			if item==0:continue
			if item>=401 and item<=411:item=401 # Bucket fill state is not a new item.
			result[item]=int(result.get(item,0))+int(stack.count)
	return result
func reset(inventory:Dictionary,equipment:Dictionary)->void:
	previous=totals(inventory,equipment);initialized=true;clear()
func observe(inventory:Dictionary,equipment:Dictionary)->void:
	var current:=totals(inventory,equipment)
	if not initialized or (allowed.is_valid() and not allowed.call()):
		previous=current;initialized=true;clear();return
	for item:int in current:
		var gained:int=current[item]-int(previous.get(item,0))
		if gained>0:gain(item,gained)
	previous=current
func gain(item:int,count:int)->void:
	if count<=0:return
	var entry:Dictionary={}
	for candidate:Dictionary in active:
		if candidate.item==item:entry=candidate;break
	if entry.is_empty():
		for candidate:Dictionary in pool:
			if not candidate.panel.visible:entry=candidate;break
		if entry.is_empty():entry=active.pop_front()
		entry.item=item;entry.count=0;entry.icon.texture=Icons.texture(item)
		entry.label.text="Gained "+str(names.get(item,"Item"))
	else:active.erase(entry)
	entry.count+=count;entry.amount.text="+%d"%entry.count
	entry.expires_us=Time.get_ticks_usec()+DISPLAY_US;entry.panel.modulate.a=1
	active.append(entry);move_child(entry.panel,get_child_count()-1);entry.panel.show()
	show();set_process(true)
func clear()->void:
	for entry:Dictionary in pool:entry.panel.hide()
	active.clear();hide();set_process(false)
func _process(_delta:float)->void:
	if allowed.is_valid() and not allowed.call():clear();return
	var now:=Time.get_ticks_usec()
	for index in range(active.size()-1,-1,-1):
		var entry:Dictionary=active[index];var left:int=entry.expires_us-now
		if left<=0:entry.panel.hide();active.remove_at(index)
		else:entry.panel.modulate.a=clampf(float(left)/FADE_US,0,1)
	if active.is_empty():hide();set_process(false)
