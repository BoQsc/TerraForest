# SPDX-License-Identifier: 0BSD
extends "res://addons/world_runtime/loading_details.gd"
## Collapsed developer ribbon; all raw counters and history remain expandable.
var ribbon:Button
func _ready()->void:
	super._ready()
	panel.anchor_top=0.;panel.anchor_bottom=0.72;panel.offset_top=44;panel.offset_bottom=0;panel.hide()
	var brand:Control=wordmark.get_parent();brand.anchor_top=0.26;brand.anchor_bottom=0.26
	ribbon=Button.new();ribbon.text="Developer details · F1 to expand";ribbon.add_theme_font_size_override("font_size",12);ribbon.position=Vector2(24,8);ribbon.custom_minimum_size=Vector2(620,28);ribbon.pressed.connect(toggle_details);add_child(ribbon)
	var style:Resource=get_meta("ui_set",null)
	if style!=null:
		ribbon.add_theme_color_override("font_color",style.accent)
func toggle_details()->void:
	panel.visible=not panel.visible
func _unhandled_key_input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F1:
		toggle_details();get_viewport().set_input_as_handled()
func refresh()->void:
	super.refresh()
	if is_instance_valid(ribbon):ribbon.text="%s  ·  %.1f s  ·  F1 %s details"%[current_stage,float(Time.get_ticks_usec()-started)/1000000.0,"hide" if panel.visible else "expand"]
