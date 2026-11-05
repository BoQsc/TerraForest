# SPDX-License-Identifier: 0BSD
extends RefCounted
## A functional adaptation shares live controls/actions with Classic. The
## reference mockup remains intact; it does not pretend its sample buttons work.
static func build(host:Control)->void:
	preload("res://addons/ui_sets/sets/shipped/browser.gd").build(host)
	var set:Resource=host.ui_set
	host.theme=host.theme.duplicate()
	for type:String in ["Button","OptionButton","LineEdit","ItemList","TabContainer"]:
		host.theme.set_color("font_focus_color",type,set.accent)
	if set.body_font!=null:host.theme.default_font=set.body_font
	if set.heading_font!=null:
		for label:Node in host.find_children("*","Label",true,false):
			if label.get_theme_font_size("font_size")>=24:label.add_theme_font_override("font",set.heading_font)
	var background:ColorRect=host.get_child(0);background.color=set.background
	for type:String in ["ItemList","TabContainer"]:
		var skin:=StyleBoxFlat.new();skin.bg_color=set.panel_color;skin.set_content_margin_all(14);skin.set_corner_radius_all(7)
		host.theme.set_stylebox("panel",type,skin)
	host.saved_title.add_theme_color_override("font_color",set.accent)
