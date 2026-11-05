# SPDX-License-Identifier: 0BSD
extends "res://addons/ui_sets/themed_panel.gd"
## Survey footer uses measured progress, with explicit startup/handoff landmarks.
var rail:Control
func _ready()->void:
	super._ready()
	if embedded:return
	var column:VBoxContainer=bar.get_parent()
	rail=preload("res://demo/world_survey/kit.gd").StageRail.new();rail.stops=[0,94,100];rail.value=bar.value/100.;rail.custom_minimum_size.y=12
	column.add_child(rail);column.move_child(rail,bar.get_index()+1)
	bar.value_changed.connect(func(value:float):rail.value=value/100.;rail.queue_redraw())
	bar.custom_minimum_size.y=8
	var labels:=HBoxContainer.new();column.add_child(labels);column.move_child(labels,rail.get_index()+1)
	for text:String in ["START","HANDOFF 94%  /  PLAYABLE 100%"]:
		var caption:=Label.new();caption.text=text;caption.add_theme_font_size_override("font_size",10);caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if labels.get_child_count()>0:caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		labels.add_child(caption)
	title.add_theme_font_override("font",get_meta("ui_set").heading_font)
	offset_top=-186
