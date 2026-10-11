# SPDX-License-Identifier: 0BSD
extends Button
var controller: Object
var side: String="player"
var slot:=0
func _get_drag_data(_at: Vector2) -> Variant:
	var data: Dictionary=controller.drag_data(side,slot)
	if data.is_empty():return null
	var preview:=Label.new();preview.text=text;preview.add_theme_font_size_override("font_size",18);set_drag_preview(preview)
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
