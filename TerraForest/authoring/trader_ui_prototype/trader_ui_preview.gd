# SPDX-License-Identifier: 0BSD
extends Control
## Standalone visual prototype. It builds sample trading data and does not load a world.

const Icons=preload("res://addons/player_runtime/item_icons.gd")
const CAPTURE_DIRECTORY:="res://reports/trader_ui_prototype"
const CAPTURE_PATH:=CAPTURE_DIRECTORY+"/trader_ui_prototype.png"

const INK:=Color("#e9f3ec")
const MUTED:=Color("#91b8ac")
const FAINT:=Color("#5d8a7e")
const GOLD:=Color("#e3bd73")
const GOLD_SOFT:=Color("#b69254")
const MINT:=Color("#7be0bd")
const PANEL:=Color("#0d2524")
const PANEL_DEEP:=Color("#091c1c")
const CARD:=Color("#102d2b")
const CARD_SELECTED:=Color("#173f37")
const LINE:=Color("#285149")
const BACKDROP_TOP:=Color("#071416")
const BACKDROP_BOTTOM:=Color("#0c2925")

const STOCK_ROWS:Array[Dictionary]=[
	{"id":102,"name":"Wood","detail":"Commodity · stackable","price":"4 coins","stock":"STOCK 200","selected":true},
	{"id":101,"name":"Brick","detail":"Commodity · stackable","price":"5 coins","stock":"STOCK 160","selected":false},
	{"id":202,"name":"Iron ore","detail":"Raw material","price":"8 coins","stock":"STOCK 50","selected":false},
	{"id":214,"name":"Field manual","detail":"Readable · travel notes","price":"30 coins","stock":"STOCK 4","selected":false},
	{"id":217,"name":"Tinned beans","detail":"Food · restores hunger","price":"12 coins","stock":"STOCK 16","selected":false},
	{"id":223,"name":"Ranger cartridges","detail":"Ammunition · stackable","price":"3 coins","stock":"STOCK 0","selected":false},
	{"id":6,"name":"Wooden torch","detail":"Tool · lights the way","price":"4 coins","stock":"STOCK 0","selected":false}
]
const PACK_ROWS:Array[Dictionary]=[
	{"id":1,"name":"Pickaxe","detail":"Tool · 82% durability","price":"7 coins","stock":"YOU HAVE 1","selected":false},
	{"id":220,"name":"Coal","detail":"Fuel · stackable","price":"5 coins","stock":"YOU HAVE 14","selected":true},
	{"id":201,"name":"Stone","detail":"Commodity · stackable","price":"1 coin","stock":"YOU HAVE 27","selected":false},
	{"id":216,"name":"Survey journal","detail":"Readable · survey notes","price":"8 coins","stock":"YOU HAVE 1","selected":false},
	{"id":218,"name":"Trail bread","detail":"Food · restores hunger","price":"3 coins","stock":"YOU HAVE 6","selected":false},
	{"id":224,"name":"Metal offcuts","detail":"Salvage · recyclable","price":"1 coin","stock":"YOU HAVE 9","selected":false},
	{"id":401,"name":"Water bucket","detail":"Container · 0 L","price":"2 coins","stock":"YOU HAVE 1","selected":false}
]

func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIRECTORY))
		var error:=get_viewport().get_texture().get_image().save_png(CAPTURE_PATH)
		print("TRADER_UI_PROTOTYPE capture=",error," path=",CAPTURE_PATH)
		get_tree().quit(0 if error==OK else 1)

func _build()->void:
	_background()
	_brand()
	var center:=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var shell:=PanelContainer.new();shell.custom_minimum_size=Vector2(1500,860)
	var shell_style:=_style(Color("#071a19"),Color("#37655a"),22,1,30)
	_pad(shell_style,2);shell.add_theme_stylebox_override("panel",shell_style)
	center.add_child(shell)
	var panel:=PanelContainer.new()
	var panel_style:=_style(PANEL,Color("#1e403b"),18,1)
	_pad(panel_style,24);panel.add_theme_stylebox_override("panel",panel_style)
	shell.add_child(panel)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",14);panel.add_child(column)
	column.add_child(_header())
	column.add_child(_separator(GOLD_SOFT,1))
	var body:=HBoxContainer.new();body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",18);column.add_child(body)
	body.add_child(_market_column("TRADER STOCK","BUY","Finite goods from the counter",STOCK_ROWS,MINT))
	body.add_child(_trade_rail())
	body.add_child(_market_column("YOUR PACK","SELL","Goods and gear you carry",PACK_ROWS,GOLD))
	column.add_child(_footer())
	column.add_child(_footnote())

func _background()->void:
	var backdrop:=ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var shader:=Shader.new()
	shader.code="""
shader_type canvas_item;
void fragment() {
	vec2 uv = UV;
	vec3 top = vec3(0.020, 0.055, 0.060);
	vec3 bottom = vec3(0.045, 0.145, 0.120);
	vec3 color = mix(top, bottom, uv.y);
	float glow = 1.0 - smoothstep(0.0, 0.78, distance(uv, vec2(0.52, 0.68)));
	color += vec3(0.14, 0.42, 0.31) * glow * 0.22;
	float vignette = 1.0 - smoothstep(0.34, 1.05, distance(uv, vec2(0.5, 0.5)));
	color *= mix(0.52, 1.0, vignette);
	float grain = fract(sin(dot(uv * vec2(1920.0, 1080.0), vec2(12.9898, 78.233))) * 43758.5453);
	color += (grain - 0.5) * 0.010;
	COLOR = vec4(color, 1.0);
}
"""
	var material:=ShaderMaterial.new();material.shader=shader;backdrop.material=material
	add_child(backdrop)
	_glow_orb(Vector2(80,610),Vector2(620,620),Color(0.20,0.72,0.53,0.045))
	_glow_orb(Vector2(1320,40),Vector2(720,720),Color(0.75,0.55,0.25,0.035))
	_glow_orb(Vector2(690,760),Vector2(840,300),Color(0.12,0.33,0.28,0.08))

func _glow_orb(at:Vector2,size:Vector2,tint:Color)->void:
	var orb:=Panel.new();orb.position=at;orb.size=size;orb.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style:=_style(tint,Color(0,0,0,0),int(maxf(size.x,size.y)*0.5),0)
	style.corner_radius_top_left=int(size.x*0.5);style.corner_radius_top_right=int(size.x*0.5)
	style.corner_radius_bottom_left=int(size.x*0.5);style.corner_radius_bottom_right=int(size.x*0.5)
	orb.add_theme_stylebox_override("panel",style);add_child(orb)

func _brand()->void:
	var left:=VBoxContainer.new();left.position=Vector2(188,24);left.add_theme_constant_override("separation",3);add_child(left)
	left.add_child(_label("TERRAFOREST",16,GOLD))
	left.add_child(_label("TRADING COUNTER · STANDALONE UI PROTOTYPE",11,MUTED))
	var right:=Label.new();right.position=Vector2(1370,26);right.size=Vector2(320,30)
	right.text="VISUAL PROTOTYPE / 01";right.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	right.add_theme_font_size_override("font_size",11);right.add_theme_color_override("font_color",FAINT);add_child(right)

func _header()->HBoxContainer:
	var header:=HBoxContainer.new();header.custom_minimum_size.y=86
	header.add_theme_constant_override("separation",20)
	var titles:=VBoxContainer.new();titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation",1);header.add_child(titles)
	titles.add_child(_label("CIVIC DISTRICT · GENERAL SUPPLIES",11,GOLD))
	titles.add_child(_label("THE TRADING POST",38,INK))
	titles.add_child(_label("A fair counter for supplies, salvage and the road ahead.",14,MUTED))
	var purses:=HBoxContainer.new();purses.add_theme_constant_override("separation",10);header.add_child(purses)
	purses.add_child(_purse("YOUR PURSE","1,284",MINT))
	purses.add_child(_purse("TRADER'S PURSE","2,400",GOLD))
	return header

func _purse(caption:String,amount:String,tint:Color)->PanelContainer:
	var card:=PanelContainer.new();card.custom_minimum_size=Vector2(230,72)
	var style:=_style(Color("#0a211f"),Color("#315d53"),11,1);_pad(style,12)
	card.add_theme_stylebox_override("panel",style)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);card.add_child(row)
	var icon:=_icon(601,34);row.add_child(icon)
	var text:=VBoxContainer.new();text.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(text)
	text.add_child(_label(caption,10,FAINT))
	text.add_child(_label(amount+" coins",17,tint))
	return card

func _market_column(title:String,verb:String,caption:String,rows:Array[Dictionary],accent:Color)->PanelContainer:
	var panel:=PanelContainer.new();panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size=Vector2(590,0)
	var style:=_style(Color("#0a2221"),Color(LINE),14,1);_pad(style,14)
	panel.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",8);panel.add_child(column)
	var head:=HBoxContainer.new();column.add_child(head)
	var title_box:=VBoxContainer.new();title_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL;head.add_child(title_box)
	title_box.add_child(_label(title,11,accent))
	title_box.add_child(_label(caption,17,INK))
	head.add_child(_badge(verb,accent))
	column.add_child(_separator(Color(0.18,0.36,0.32,0.65),1))
	for row:Dictionary in rows:
		column.add_child(_item_row(row,accent))
	var spacer:=Control.new();spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(spacer)
	var footer:=HBoxContainer.new();column.add_child(footer)
	footer.add_child(_label("Prices are per item · finite coin and stock",11,FAINT))
	var hint:=Label.new();hint.text="DRAG TO TRADE";hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	hint.size_flags_horizontal=Control.SIZE_EXPAND_FILL;hint.add_theme_font_size_override("font_size",10)
	hint.add_theme_color_override("font_color",accent);footer.add_child(hint)
	return panel

func _item_row(data:Dictionary,accent:Color)->PanelContainer:
	var selected:=bool(data.selected)
	var row:=PanelContainer.new();row.custom_minimum_size=Vector2(0,58)
	var style:=_style(CARD_SELECTED if selected else CARD,accent if selected else Color("#234a43"),10,1)
	if selected:style.set_border_width(SIDE_LEFT,4)
	_pad(style,8);row.add_theme_stylebox_override("panel",style)
	var line:=HBoxContainer.new();line.add_theme_constant_override("separation",10);row.add_child(line)
	var icon_panel:=PanelContainer.new();icon_panel.custom_minimum_size=Vector2(48,48)
	var icon_style:=_style(Color("#071b1a"),Color("#2b554c") if not selected else accent,8,1)
	icon_panel.add_theme_stylebox_override("panel",icon_style);line.add_child(icon_panel)
	icon_panel.add_child(_icon(int(data.id),38))
	var info:=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;info.alignment=BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation",0);line.add_child(info)
	info.add_child(_label(str(data.name),16,INK))
	info.add_child(_label(str(data.detail),10,MUTED))
	var values:=VBoxContainer.new();values.custom_minimum_size.x=106;values.alignment=BoxContainer.ALIGNMENT_CENTER
	values.add_theme_constant_override("separation",0);line.add_child(values)
	values.add_child(_label(str(data.price),15,GOLD if not selected else Color("#f5d795"),HORIZONTAL_ALIGNMENT_RIGHT))
	values.add_child(_label(str(data.stock),10,FAINT,HORIZONTAL_ALIGNMENT_RIGHT))
	if selected:
		var marker:=VBoxContainer.new();marker.custom_minimum_size.x=12;marker.alignment=BoxContainer.ALIGNMENT_CENTER;line.add_child(marker)
		marker.add_child(_label("◆",10,accent,HORIZONTAL_ALIGNMENT_CENTER))
	return row

func _trade_rail()->VBoxContainer:
	var rail:=VBoxContainer.new();rail.custom_minimum_size.x=86;rail.alignment=BoxContainer.ALIGNMENT_CENTER
	rail.add_theme_constant_override("separation",10);rail.add_child(_label("↔",30,GOLD_SOFT,HORIZONTAL_ALIGNMENT_CENTER))
	rail.add_child(_label("DRAG",9,FAINT,HORIZONTAL_ALIGNMENT_CENTER))
	rail.add_child(_label("across",10,MUTED,HORIZONTAL_ALIGNMENT_CENTER))
	rail.add_child(_separator(Color(0.25,0.50,0.43,0.55),1))
	rail.add_child(_label("⇄",20,MINT,HORIZONTAL_ALIGNMENT_CENTER))
	rail.add_child(_label("BUY\nSELL",9,FAINT,HORIZONTAL_ALIGNMENT_CENTER))
	return rail

func _footer()->PanelContainer:
	var footer:=PanelContainer.new();footer.custom_minimum_size.y=82
	var style:=_style(Color("#091d1c"),Color("#2b5148"),12,1,8);_pad(style,12)
	footer.add_theme_stylebox_override("panel",style)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",14);footer.add_child(row)
	var quantity:=VBoxContainer.new();quantity.custom_minimum_size.x=150;quantity.add_child(_label("QUANTITY",9,FAINT))
	var stepper:=HBoxContainer.new();stepper.add_theme_constant_override("separation",4);quantity.add_child(stepper)
	stepper.add_child(_small_button("−"))
	var value:=Label.new();value.text="3";value.custom_minimum_size=Vector2(34,34);value.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;value.add_theme_font_size_override("font_size",17);value.add_theme_color_override("font_color",INK);stepper.add_child(value)
	stepper.add_child(_small_button("+"))
	row.add_child(quantity)
	var summary:=VBoxContainer.new();summary.size_flags_horizontal=Control.SIZE_EXPAND_FILL;summary.add_theme_constant_override("separation",0)
	summary.add_child(_label("3 × Wood",15,INK))
	summary.add_child(_label("12 coins total  ·  stock after trade: 197",10,MUTED))
	row.add_child(summary)
	row.add_child(_button("BUY 3 · 12 COINS",Color("#1d5144"),MINT,MINT))
	row.add_child(_button("SELL 3 · 15 COINS",Color("#3b3320"),GOLD,GOLD))
	return footer

func _footnote()->HBoxContainer:
	var note:=HBoxContainer.new();note.custom_minimum_size.y=16
	note.add_child(_label("Drag trader stock to YOUR PACK to buy  ·  Drag YOUR PACK to TRADER STOCK to sell",10,MUTED))
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;note.add_child(spacer)
	note.add_child(_label("PROTOTYPE · SAMPLE DATA",9,FAINT))
	return note

func _small_button(text:String)->Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size=Vector2(30,30);button.focus_mode=Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size",14);button.add_theme_color_override("font_color",INK)
	for state in ["normal","hover","pressed"]:
		var style:=_style(Color("#13332f") if state=="normal" else Color("#1b453d"),Color("#36665b"),7,1)
		button.add_theme_stylebox_override(state,style)
	return button

func _button(text:String,fill:Color,border:Color,text_color:Color)->Button:
	var button:=Button.new();button.text=text;button.custom_minimum_size=Vector2(190,44);button.focus_mode=Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size",12);button.add_theme_color_override("font_color",text_color)
	for state in ["normal","hover","pressed"]:
		var color:=fill if state=="normal" else fill.lightened(0.08) if state=="hover" else fill.darkened(0.08)
		var style:=_style(color,border,9,1);style.set_border_width(SIDE_BOTTOM,2)
		button.add_theme_stylebox_override(state,style)
	return button

func _badge(text:String,tint:Color)->PanelContainer:
	var badge:=PanelContainer.new();badge.custom_minimum_size=Vector2(48,24)
	var style:=_style(Color(tint.r,tint.g,tint.b,0.09),Color(tint.r,tint.g,tint.b,0.45),6,1);_pad(style,5)
	badge.add_theme_stylebox_override("panel",style)
	var label:=_label(text,9,tint,HORIZONTAL_ALIGNMENT_CENTER)
	badge.add_child(label);return badge

func _icon(item:int,size:int)->TextureRect:
	var rect:=TextureRect.new();rect.texture=Icons.texture(item)
	rect.custom_minimum_size=Vector2(size,size);rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return rect

func _label(text:String,size:int,color:Color,align:=HORIZONTAL_ALIGNMENT_LEFT)->Label:
	var label:=Label.new();label.text=text;label.horizontal_alignment=align;label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color",color)
	if size>0:label.add_theme_font_size_override("font_size",size)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return label

func _separator(color:Color,height:int)->ColorRect:
	var line:=ColorRect.new();line.color=color;line.custom_minimum_size.y=height;line.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return line

func _style(bg:Color,border:Color,radius:int,border_width:int=1,shadow:int=0)->StyleBoxFlat:
	var style:=StyleBoxFlat.new();style.bg_color=bg;style.border_color=border
	style.set_border_width_all(border_width);style.set_corner_radius_all(radius);style.anti_aliasing=true
	if shadow>0:
		style.shadow_size=shadow;style.shadow_color=Color(0,0,0,0.55);style.shadow_offset=Vector2(0,12)
	return style

func _pad(style:StyleBoxFlat,value:int)->void:
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(edge,value)
