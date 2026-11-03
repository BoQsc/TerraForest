# SPDX-License-Identifier: 0BSD
extends PanelContainer
## One mockup-style trading row. The owning list supplies selection and trade data.

signal activated(index:int)
var list:Node
var index:=0
var item_text:=""
var detail_text:=""
var price_text:=""
var stock_text:=""
var tint:=Color.WHITE
var selected:=false
var marker:Label
var name_label:Label
var detail_label:Label
var price_label:Label
var stock_label:Label
var icon_rect:TextureRect

func setup(owner_list:Node,row_index:int,text:String,icon:Texture2D,detail:String,price:String,stock:String)->void:
	list=owner_list;index=row_index;item_text=text;detail_text=detail;price_text=price;stock_text=stock
	custom_minimum_size=Vector2(0,58);mouse_filter=Control.MOUSE_FILTER_STOP
	var line:=HBoxContainer.new();line.add_theme_constant_override("separation",10);line.mouse_filter=Control.MOUSE_FILTER_PASS
	add_child(line)
	var icon_panel:=PanelContainer.new();icon_panel.custom_minimum_size=Vector2(48,48);icon_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var icon_style:=_style(Color("#071b1a"),Color("#2b554c"),8,1)
	icon_panel.add_theme_stylebox_override("panel",icon_style);line.add_child(icon_panel)
	icon_rect=TextureRect.new();icon_rect.texture=icon;icon_rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	icon_panel.add_child(icon_rect)
	var info:=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;info.alignment=BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation",0);info.mouse_filter=Control.MOUSE_FILTER_IGNORE;line.add_child(info)
	name_label=_label(item_text,15,Color("#e9f3ec"));info.add_child(name_label)
	detail_label=_label(detail,10,Color("#91b8ac"));info.add_child(detail_label)
	var values:=VBoxContainer.new();values.custom_minimum_size.x=102;values.alignment=BoxContainer.ALIGNMENT_CENTER
	values.add_theme_constant_override("separation",0);values.mouse_filter=Control.MOUSE_FILTER_IGNORE;line.add_child(values)
	price_label=_label(price,14,Color("#e3bd73"),HORIZONTAL_ALIGNMENT_RIGHT);values.add_child(price_label)
	stock_label=_label(stock,9,Color("#5d8a7e"),HORIZONTAL_ALIGNMENT_RIGHT);values.add_child(stock_label)
	marker=_label("◆",10,Color("#e3bd73"),HORIZONTAL_ALIGNMENT_CENTER)
	marker.custom_minimum_size.x=12;marker.mouse_filter=Control.MOUSE_FILTER_IGNORE;line.add_child(marker)
	tooltip_text=item_text
	set_selected(false)

func set_selected(value:bool)->void:
	selected=value
	var style:=_style(Color("#173f37") if selected else Color("#102d2b"),Color("#e3bd73") if selected else Color("#234a43"),9,1)
	if selected:style.set_border_width(SIDE_LEFT,4)
	_pad(style,8);add_theme_stylebox_override("panel",style)
	marker.visible=selected
	modulate=Color.WHITE if selected else tint
	price_label.add_theme_color_override("font_color",Color("#f5d795") if selected else Color("#e3bd73"))

func set_tint(color:Color)->void:
	tint=color
	if not selected:modulate=color

func set_tooltip(text:String)->void:
	tooltip_text=text

func _gui_input(event:InputEvent)->void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		list.activate(index)

func _get_drag_data(_at:Vector2)->Variant:
	list.select(index)
	var data:Dictionary=list.drag_offer(index)
	if data.is_empty():return null
	var preview:=Label.new();preview.text=list.trade.drag_caption(data)
	preview.add_theme_font_size_override("font_size",18)
	preview.add_theme_color_override("font_color",Color("#f5d795"))
	set_drag_preview(preview)
	return data

func _can_drop_data(_at:Vector2,data:Variant)->bool:
	return list.trade.accepts_drop(list.side,data)

func _drop_data(_at:Vector2,data:Variant)->void:
	list.trade.drop_data(list.side,data)

func _label(text:String,size:int,color:Color,align:=HORIZONTAL_ALIGNMENT_LEFT)->Label:
	var label:=Label.new();label.text=text;label.horizontal_alignment=align;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",size);label.add_theme_color_override("font_color",color)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return label

func _style(bg:Color,border:Color,radius:int,border_width:int)->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=bg;style.border_color=border
	style.set_border_width_all(border_width);style.set_corner_radius_all(radius);style.anti_aliasing=true
	return style

func _pad(style:StyleBoxFlat,value:int)->void:
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(edge,value)
