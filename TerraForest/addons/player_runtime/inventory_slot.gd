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

func _ready() -> void:
	for state in ["normal","hover","pressed","disabled"]:
		var style:=StyleBoxFlat.new();style.bg_color=Color("192b29") if state=="hover" else Color("101b1e")
		style.border_color=Color("49766a") if state=="hover" else Color("304442")
		for edge in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_border_width(edge,1);style.set_content_margin(edge,5)
		style.set_corner_radius_all(5);add_theme_stylebox_override(state,style)
