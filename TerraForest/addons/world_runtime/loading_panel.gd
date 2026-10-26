# SPDX-License-Identifier: 0BSD
extends PanelContainer
# Shared, viewport-anchored presentation. No timed/fabricated progress animation.
const Timing=preload("res://addons/world_runtime/loading_timer.gd")
var timer=Timing.new()
const COMPACT_WIDTH:=1120.0
var preferences_path:="user://loading_presentation.cfg"
var compact_width:=true
var embedded:=false
var clock_label:Label
var next_clock_us:=0
var title:Label
var detail:Label
var percentage:Label
var bar:ProgressBar
var action:Button
var high_water:=0.0
var work:Label
func _ready()->void:
 if not embedded:
  set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
  anchor_left=0.05;anchor_right=0.95;offset_left=0;offset_right=0;offset_top=-152;offset_bottom=-24;grow_vertical=Control.GROW_DIRECTION_BEGIN
 var skin:=StyleBoxFlat.new();skin.bg_color=Color(0.025,0.065,0.07,0.94)
 skin.set_corner_radius_all(7);skin.set_content_margin_all(14);add_theme_stylebox_override("panel",skin)
 var box:=VBoxContainer.new();box.add_theme_constant_override("separation",6);add_child(box)
 var header:=HBoxContainer.new();box.add_child(header)
 title=Label.new();title.text="Loading your world";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.add_theme_font_size_override("font_size",18);header.add_child(title)
 if embedded:title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
 clock_label=Label.new();clock_label.add_theme_font_size_override("font_size",15);clock_label.add_theme_color_override("font_color",Color("a9ddc8"));clock_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;header.add_child(clock_label)
 clock_label.tooltip_text="Elapsed time includes generation, verification and the first load. Remaining time is a rough estimate from recent measured progress, updated as work changes."
 header.add_theme_constant_override("separation",18)
 action=Button.new();action.custom_minimum_size=Vector2(180,26);action.add_theme_font_size_override("font_size",14);action.text="Cancel";header.add_child(action)
 var row:=HBoxContainer.new();row.add_theme_constant_override("separation",20);box.add_child(row)
 detail=Label.new();detail.text="Starting…";detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL;detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.add_theme_font_size_override("font_size",17);row.add_child(detail)
 percentage=Label.new();percentage.text="0%";percentage.custom_minimum_size.x=100;percentage.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT;percentage.add_theme_font_size_override("font_size",20);row.add_child(percentage)
 bar=ProgressBar.new();bar.custom_minimum_size.y=6 if embedded else 18;bar.show_percentage=false;bar.max_value=100;box.add_child(bar)
 var track:=StyleBoxFlat.new();track.bg_color=Color("263c40");track.set_corner_radius_all(4);bar.add_theme_stylebox_override("background",track)
 var fill:=StyleBoxFlat.new();fill.bg_color=Color("6cc7aa");fill.set_corner_radius_all(4);bar.add_theme_stylebox_override("fill",fill)
 bar.tooltip_text="Overall completion estimate based on finished stages and work counts. 100% means ready to play."
 work=Label.new();work.visible=false;work.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;work.add_theme_font_size_override("font_size",14);box.add_child(work)
 if embedded:
  # The selector owns the surrounding layout; this is a footer strip, not a card.
  add_theme_stylebox_override("panel",StyleBoxEmpty.new());box.add_theme_constant_override("separation",4)
  title.hide();row.hide();detail.reparent(header);header.move_child(detail,0)
  percentage.reparent(header);header.move_child(percentage,1)
  header.add_theme_constant_override("separation",12)
  detail.autowrap_mode=TextServer.AUTOWRAP_OFF;detail.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;detail.add_theme_font_size_override("font_size",16)
  percentage.custom_minimum_size.x=40;percentage.add_theme_font_size_override("font_size",14)
  clock_label.add_theme_font_size_override("font_size",13)
  action.custom_minimum_size=Vector2(148,28)
  for state:String in ["normal","hover","pressed","disabled"]:
   var button_skin:=StyleBoxFlat.new();button_skin.bg_color=Color("29484a" if state in ["hover","pressed"] else "1b3035")
   button_skin.set_corner_radius_all(4);button_skin.content_margin_left=10;button_skin.content_margin_right=10;button_skin.content_margin_top=4;button_skin.content_margin_bottom=4
   action.add_theme_stylebox_override(state,button_skin)
  work.autowrap_mode=TextServer.AUTOWRAP_OFF;work.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;work.add_theme_font_size_override("font_size",13);work.add_theme_color_override("font_color",Color("9bafad"))
  work.custom_minimum_size.y=18;work.show()
 var preferences:=ConfigFile.new()
 if preferences.load(preferences_path)==OK:compact_width=bool(preferences.get_value("loading","compact_width",true))
 set_compact_width(compact_width,false)
 get_viewport().size_changed.connect(_apply_width)
 reset()
func set_compact_width(enabled:bool,persist:bool=true)->void:
 compact_width=enabled;_apply_width()
 if persist:
  var preferences:=ConfigFile.new();preferences.load(preferences_path)
  preferences.set_value("loading","compact_width",enabled)
  var result:=preferences.save(preferences_path)
  if result!=OK:push_warning("Could not save loading layout preference: "+error_string(result))
func _apply_width()->void:
 if embedded:return
 grow_horizontal=Control.GROW_DIRECTION_BOTH
 if compact_width:
  var width:=minf(COMPACT_WIDTH,get_viewport_rect().size.x*0.9)
  anchor_left=0.5;anchor_right=0.5;offset_left=-width*0.5;offset_right=width*0.5
 else:
  anchor_left=0.05;anchor_right=0.95;offset_left=0;offset_right=0
func reset(start_ms:int=0,baseline:float=0)->void:
 high_water=baseline;bar.value=baseline;percentage.text="%d%%"%int(baseline)
 timer.reset(Time.get_ticks_usec(),baseline,Timing.carried_elapsed(start_ms));next_clock_us=0;set_process(true);refresh_clock()
func show_idle()->void:
 reset()
 timer.stop("idle",Time.get_ticks_usec());set_process(false)
 title.text="Create world";detail.text="Ready to generate";detail.tooltip_text=detail.text
 clock_label.text="Elapsed 00:00 · Est. remaining —"
func _process(_delta:float)->void:
 if not is_visible_in_tree() or Time.get_ticks_usec()<next_clock_us:return
 next_clock_us=Time.get_ticks_usec()+250000;refresh_clock()
func refresh_clock()->void:
 clock_label.text=Timing.label(timer.snapshot(Time.get_ticks_usec()))
func stop_timer(reason:String)->void:
 timer.stop(reason,Time.get_ticks_usec());refresh_clock()
func timing_snapshot()->Dictionary:
 return timer.snapshot(Time.get_ticks_usec())
func show_progress(caption:String,stage:String,value:float)->void:
 title.text=caption;detail.text=stage
 if embedded:detail.tooltip_text=stage
 high_water=maxf(high_water,clampf(value,0,100));bar.value=high_water
 percentage.text="%d%%"%int(floor(high_water))
 timer.observe(high_water,Time.get_ticks_usec())
 if high_water>=100:refresh_clock();set_process(false)

func show_work(text:String)->void:
 work.text=text;work.visible=embedded or not text.is_empty()
 if embedded:work.tooltip_text=text
