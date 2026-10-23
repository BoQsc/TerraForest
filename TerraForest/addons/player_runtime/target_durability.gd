# SPDX-License-Identifier: 0BSD
extends PanelContainer
# Reused presentation only. Accepted attacks supply authoritative health values;
# no target queries, world nodes or per-hit tweens are created by this display.
const DISPLAY_US:=2200000
const FADE_US:=350000
var allowed:Callable
var expires_us:=0
var name_label:Label
var amount_label:Label
var health_bar:ProgressBar
var remaining:=0
var maximum:=0
var _fill:StyleBoxFlat

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left=22;offset_right=258;offset_top=-66;offset_bottom=-16
	var skin:=StyleBoxFlat.new();skin.bg_color=Color(0.015,0.035,0.035,0.8)
	skin.set_corner_radius_all(4);skin.set_content_margin_all(8);add_theme_stylebox_override("panel",skin)
	var column:=VBoxContainer.new();column.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_theme_constant_override("separation",6);add_child(column)
	var row:=HBoxContainer.new();row.mouse_filter=Control.MOUSE_FILTER_IGNORE;row.add_theme_constant_override("separation",10);column.add_child(row)
	name_label=Label.new();name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;name_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;name_label.add_theme_font_size_override("font_size",14);row.add_child(name_label)
	amount_label=Label.new();amount_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;amount_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;amount_label.add_theme_font_size_override("font_size",14);row.add_child(amount_label)
	health_bar=ProgressBar.new();health_bar.custom_minimum_size.y=7;health_bar.show_percentage=false;health_bar.mouse_filter=Control.MOUSE_FILTER_IGNORE;column.add_child(health_bar)
	var track:=StyleBoxFlat.new();track.bg_color=Color("283d3b");track.set_corner_radius_all(2);health_bar.add_theme_stylebox_override("background",track)
	_fill=StyleBoxFlat.new();_fill.set_corner_radius_all(2);health_bar.add_theme_stylebox_override("fill",_fill)
	clear()

func show_hit(target_name:String,current:int,total:int)->void:
	if total<=0 or (allowed.is_valid() and not allowed.call()):return
	maximum=total;remaining=clampi(current,0,total)
	name_label.text=target_name;amount_label.text="%d / %d"%[remaining,maximum]
	health_bar.max_value=maximum;health_bar.value=remaining
	var ratio:=float(remaining)/maximum
	_fill.bg_color=Color("8adeb0") if ratio>0.5 else Color("e5bd69") if ratio>0.25 else Color("df7b73")
	amount_label.modulate=Color("df7b73") if remaining==0 else Color.WHITE
	expires_us=Time.get_ticks_usec()+DISPLAY_US;modulate.a=1.0;show();set_process(true)

func clear()->void:
	expires_us=0;hide();set_process(false)

func _process(_delta:float)->void:
	var left:=expires_us-Time.get_ticks_usec()
	if left<=0 or (allowed.is_valid() and not allowed.call()):clear();return
	modulate.a=clampf(float(left)/FADE_US,0,1)
