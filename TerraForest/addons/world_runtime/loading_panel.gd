# SPDX-License-Identifier: 0BSD
extends PanelContainer
# Shared, viewport-anchored presentation. No timed/fabricated progress animation.
var title:Label
var detail:Label
var percentage:Label
var bar:ProgressBar
var action:Button
var high_water:=0.0
var work:Label
func _ready()->void:
 set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
 anchor_left=0.05;anchor_right=0.95;offset_left=0;offset_right=0;offset_top=-152;offset_bottom=-24;grow_vertical=Control.GROW_DIRECTION_BEGIN
 var skin:=StyleBoxFlat.new();skin.bg_color=Color(0.025,0.065,0.07,0.94)
 skin.set_corner_radius_all(7);skin.set_content_margin_all(14);add_theme_stylebox_override("panel",skin)
 var box:=VBoxContainer.new();box.add_theme_constant_override("separation",6);add_child(box)
 var header:=HBoxContainer.new();box.add_child(header)
 title=Label.new();title.text="Loading your world";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.add_theme_font_size_override("font_size",18);header.add_child(title)
 action=Button.new();action.custom_minimum_size=Vector2(180,26);action.add_theme_font_size_override("font_size",14);action.text="Cancel";header.add_child(action)
 var row:=HBoxContainer.new();row.add_theme_constant_override("separation",20);box.add_child(row)
 detail=Label.new();detail.text="Starting…";detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.add_theme_font_size_override("font_size",17);row.add_child(detail)
 percentage=Label.new();percentage.text="0%";percentage.custom_minimum_size.x=100;percentage.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;percentage.add_theme_font_size_override("font_size",20);row.add_child(percentage)
 bar=ProgressBar.new();bar.custom_minimum_size.y=18;bar.show_percentage=false;bar.max_value=100;box.add_child(bar)
 var track:=StyleBoxFlat.new();track.bg_color=Color("263c40");track.set_corner_radius_all(4);bar.add_theme_stylebox_override("background",track)
 var fill:=StyleBoxFlat.new();fill.bg_color=Color("6cc7aa");fill.set_corner_radius_all(4);bar.add_theme_stylebox_override("fill",fill)
 bar.tooltip_text="Overall completion estimate based on finished stages and work counts. 100% means ready to play."
 work=Label.new();work.visible=false;work.add_theme_font_size_override("font_size",14);box.add_child(work)
func reset()->void:
 high_water=0;bar.value=0;percentage.text="0%"
func show_progress(caption:String,stage:String,value:float)->void:
 title.text=caption;detail.text=stage
 high_water=maxf(high_water,clampf(value,0,100));bar.value=high_water
 percentage.text="%d%%"%int(floor(high_water))

func show_work(text:String)->void:
 work.text=text;work.visible=not text.is_empty()
