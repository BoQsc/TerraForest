# SPDX-License-Identifier: 0BSD
extends "res://addons/world_runtime/loading_panel.gd"
func _ready()->void:
	super._ready()
	var set:Resource=get_meta("ui_set")
	var skin:=get_theme_stylebox("panel").duplicate()
	if skin is StyleBoxFlat:
		skin.bg_color=set.panel_color;skin.border_color=set.accent;skin.set_border_width_all(1)
		add_theme_stylebox_override("panel",skin)
	var fill:=bar.get_theme_stylebox("fill").duplicate();fill.bg_color=set.accent;bar.add_theme_stylebox_override("fill",fill)
	clock_label.add_theme_color_override("font_color",set.accent)
	if set.body_font!=null:
		var theme_copy:=Theme.new();theme_copy.default_font=set.body_font;theme=theme_copy
