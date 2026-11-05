# SPDX-License-Identifier: 0BSD
extends RefCounted
## Compose the actual recipe form and survey; no sample recipe or mock jobs.
static func build(host:Control,tabs:TabContainer)->void:
	preload("res://demo/world_creation_panel.gd").build(host,tabs)
	var page:VBoxContainer=tabs.get_child(tabs.get_child_count()-1)
	var header:HBoxContainer=page.get_child(0)
	var title:Label=header.get_child(0).get_child(0);title.add_theme_font_override("font",host.ui_set.heading_font);title.add_theme_font_size_override("font_size",42)
	var body:HBoxContainer=page.get_child(1)
	var form:Control=body.get_child(0);var survey:Control=body.get_child(1)
	form.custom_minimum_size.x=650;survey.custom_minimum_size.x=900
	body.move_child(survey,0);body.add_theme_constant_override("separation",48)
	page.add_theme_constant_override("separation",24)
	page.set_meta("ui_layout","survey_form")
