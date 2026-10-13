# SPDX-License-Identifier: 0BSD
extends Button
var controller: Object
var side: String="player"
var slot:=0
func _get_drag_data(_at: Vector2) -> Variant:
	var data: Dictionary=controller.drag_data(side,slot)
	if data.is_empty():return null
	var preview:=Label.new();preview.text=tooltip_text;preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	if item_texture!=null:
		var picture:=TextureRect.new();picture.texture=item_texture;picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.custom_minimum_size=Vector2(64,64);picture.position=Vector2(0,-68);picture.mouse_filter=Control.MOUSE_FILTER_IGNORE;preview.add_child(picture)
	preview.add_theme_font_size_override("font_size",18);set_drag_preview(preview)
	return data
func _can_drop_data(_at: Vector2,data: Variant) -> bool:
	return controller.accepts_drag(side,slot,data)
func _drop_data(_at: Vector2,data: Variant) -> void:
	controller.drop_stack(side,slot,data)

var appearance: int=-1
var styles: Dictionary={}
func _ready() -> void:
	for state in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new()
		for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(edge,5)
		style.set_corner_radius_all(5);add_theme_stylebox_override(state,style);styles[state]=style
	set_appearance(true,false,false)
func set_appearance(empty: bool,active: bool=false,selected: bool=false) -> void:
	var next:=int(empty)+int(active)*2+int(selected)*4
	if next==appearance or styles.is_empty():return
	appearance=next
	for state in styles:
		var style: StyleBoxFlat=styles[state]
		style.bg_color=Color(0.10,0.23,0.20,0.94) if active else Color(0.06,0.105,0.12,0.30 if empty else 0.88)
		if state in ["hover","pressed"]:style.bg_color=Color(0.13,0.26,0.23,0.80 if empty else 0.98)
		style.border_color=Color("f1cf83") if selected else (Color("88e8c5") if active else Color(0.30,0.46,0.43,0.45 if empty else 0.8))
		for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_border_width(edge,2 if active or selected else 1)
		style.set_border_width(SIDE_BOTTOM,4 if active else (2 if selected else 1))
	add_theme_color_override("font_color",Color("ecfff6") if active else (Color(0.75,0.82,0.81,0.65) if empty else Color("e0ebe8")))

# Presentation is updated only by inventory events. No per-frame work.
var item_texture: Texture2D
var durability_ratio: float=-1.0
var item_picture: TextureRect
var item_label: Label
var count_label: Label
var key_label: Label
func present(row: Dictionary,title: String,key: String="") -> void:
	var carries_water: bool=int(row.get("water_capacity_ml",0))>0
	if carries_water:title="Water bucket"
	if item_picture==null:
		item_picture=TextureRect.new();item_picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;item_picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(item_picture);item_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);item_picture.offset_top=3;item_picture.offset_bottom=-22;item_picture.offset_left=20;item_picture.offset_right=-20
		item_label=Label.new();item_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;item_label.add_theme_font_size_override("font_size",12);item_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		add_child(item_label);item_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);item_label.offset_top=-23;item_label.offset_bottom=-7
		count_label=Label.new();count_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;count_label.add_theme_font_size_override("font_size",14)
		add_child(count_label);count_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE);count_label.offset_right=-6;count_label.offset_top=4
		key_label=Label.new();key_label.position=Vector2(6,3);key_label.add_theme_font_size_override("font_size",13);add_child(key_label)
		for child in [item_picture,item_label,count_label,key_label]:child.mouse_filter=Control.MOUSE_FILTER_IGNORE
	text="";key_label.text=key
	var occupied: bool=int(row.get("count",0))>0
	item_texture=preload("res://addons/player_runtime/item_icons.gd").texture(row.get("item",0)) if occupied else null
	item_picture.texture=item_texture;item_picture.visible=occupied
	item_label.text=title if occupied else "Empty";item_label.modulate.a=1.0 if occupied else 0.5
	count_label.text=str(row.count) if int(row.get("count",0))>1 else ""
	tooltip_text=title if occupied else "Empty slot"
	if occupied and carries_water:
		var water_amount:int=row.water_ml
		count_label.text="1 / 1" if water_amount==1000000 else "0 / 1" if water_amount==0 else "Refill"
		tooltip_text+="\nWater: %s\nOne unit = 1 m³"%("1 unit" if water_amount==1000000 else "Empty" if water_amount==0 else "Older partial bucket; collect water to refill")
	var maximum: int=row.get("max_durability",0)
	durability_ratio=clampf(float(row.get("durability",0))/maximum,0,1) if occupied and maximum>0 else -1.0
	if durability_ratio>=0:tooltip_text+="\nDurability: %d / %d (%d%%)"%[row.durability,maximum,roundi(durability_ratio*100)]
	queue_redraw()
func clear_presentation() -> void:
	item_texture=null;durability_ratio=-1.0
	if item_picture!=null:
		item_picture.hide();item_label.text="";count_label.text="";key_label.text=""
	alignment=HORIZONTAL_ALIGNMENT_CENTER;add_theme_font_size_override("font_size",16);queue_redraw()
func durability_color() -> Color:
	return Color("ef6660") if durability_ratio<=0.25 else (Color("edc96a") if durability_ratio<=0.6 else Color("75dba1"))
func _draw() -> void:
	if durability_ratio<0:return
	var bar:=Rect2(7,size.y-7,maxf(0,size.x-14),3)
	draw_rect(bar,Color(0.025,0.035,0.04,0.95));bar.size.x*=durability_ratio;draw_rect(bar,durability_color())

func _make_custom_tooltip(value: String) -> Object:
	var panel:=PanelContainer.new();panel.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.045,0.04,0.98);style.border_color=Color("52776a");style.set_border_width_all(1);style.set_corner_radius_all(5)
	for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(edge,10)
	panel.add_theme_stylebox_override("panel",style)
	var label:=Label.new();label.text=value;label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.add_theme_font_size_override("font_size",16);panel.add_child(label)
	return panel
