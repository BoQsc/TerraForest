# SPDX-License-Identifier: 0BSD
extends "res://addons/ui_sets/themed_panel.gd"
## Live editorial loading rail beside the planet; inherited clocks/counters/actions.
func _ready()->void:
	super._ready()
	if embedded:return
	add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var column:VBoxContainer=title.get_parent().get_parent()
	column.add_theme_constant_override("separation",28)
	title.add_theme_font_size_override("font_size",42)
	title.add_theme_font_override("font",get_meta("ui_set").heading_font)
	title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	clock_label.reparent(column);column.move_child(clock_label,1)
	clock_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_LEFT
	action.reparent(column);action.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN;action.custom_minimum_size=Vector2(220,44)
	percentage.add_theme_font_size_override("font_size",46)
	detail.add_theme_font_size_override("font_size",24)
	bar.custom_minimum_size.y=12
	work.show();work.add_theme_font_size_override("font_size",15)
	column.move_child(action,column.get_child_count()-1)
	_apply_width()
	for sibling:Node in get_parent().get_children():
		if sibling.has_method("observe_progress"):bar.value_changed.connect(sibling.observe_progress)
func _apply_width()->void:
	if embedded:return
	anchor_left=0.54;anchor_right=0.95;anchor_top=0.24;anchor_bottom=0.90
	offset_left=0;offset_right=0;offset_top=0;offset_bottom=0
