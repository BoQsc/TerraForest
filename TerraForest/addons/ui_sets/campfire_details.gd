# SPDX-License-Identifier: 0BSD
extends "res://addons/ui_sets/editorial_details.gd"
func _ready()->void:
	super._ready()
	var brand:Control=wordmark.get_parent();brand.anchor_top=0.08;brand.anchor_bottom=0.08
	var tip:=PanelContainer.new();tip.anchor_left=0.17;tip.anchor_right=0.68;tip.anchor_top=1.;tip.anchor_bottom=1.;tip.offset_top=-350;tip.offset_bottom=-252;add_child(tip)
	tip.add_theme_stylebox_override("panel",preload("res://demo/world_creation_panel.gd").box(Color(0.025,0.035,0.035,0.82)))
	var row:=HBoxContainer.new();tip.add_child(row)
	row.add_child(preload("res://demo/world_loading_mockup.gd").Campfire.new())
	var copy:=Label.new();copy.text="A WORLD WORTH WANDERING\nExplore the roads, woodlands and settlements beyond your camp.";copy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;copy.add_theme_font_size_override("font_size",16);copy.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(copy)
