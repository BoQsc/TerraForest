# SPDX-License-Identifier: 0BSD
extends "res://addons/ui_sets/themed_panel.gd"
func _ready()->void:
	super._ready()
	if embedded:return
	var skin:=StyleBoxFlat.new();skin.bg_color=Color(0.015,0.020,0.020,0.95);skin.border_color=Color(0.28,0.32,0.30,0.30);skin.border_width_top=1
	skin.content_margin_left=68;skin.content_margin_right=68;skin.content_margin_top=22;skin.content_margin_bottom=22;add_theme_stylebox_override("panel",skin)
	bar.custom_minimum_size.y=10
	title.add_theme_font_size_override("font_size",26)
	bar.get_parent().add_theme_constant_override("separation",16)
	_apply_width()
func _apply_width()->void:
	if embedded:return
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top=-220;offset_bottom=0
