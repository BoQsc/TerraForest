# SPDX-License-Identifier: 0BSD
extends Control
# Presentation only: callers supply atomic progress or already-published counters.
# No native-world query, disk scan, viewport or extra rendering pass is created here.
var wordmark:HBoxContainer
var live:RichTextLabel
var history:RichTextLabel
var status:Label
var panel:PanelContainer
var latest:Dictionary={}
var environment:Dictionary={}
var stages:Array[Dictionary]=[]
var current_stage:=""
var stage_started:=0
var started:=0
var next_refresh:=0
var provider:Callable
var context:Dictionary={}
var sample_us:=0

func _ready()->void:
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE
 var brand:=VBoxContainer.new();add_child(brand)
 brand.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
 brand.anchor_top=0.34;brand.anchor_bottom=0.34;brand.offset_left=-360;brand.offset_right=360
 brand.add_theme_constant_override("separation",10);brand.mouse_filter=Control.MOUSE_FILTER_IGNORE
 wordmark=HBoxContainer.new();wordmark.alignment=BoxContainer.ALIGNMENT_CENTER;wordmark.add_theme_constant_override("separation",0);brand.add_child(wordmark)
 var font:=SystemFont.new();font.font_names=PackedStringArray(["Georgia","DejaVu Serif"]);font.font_weight=700
 for part in [["Terra",Color("e6c08a")],["Forest",Color("98ddbc")]]:
  var letter:=Label.new();letter.text=part[0];letter.add_theme_font_override("font",font);letter.add_theme_font_size_override("font_size",68)
  letter.add_theme_color_override("font_color",part[1]);letter.add_theme_color_override("font_shadow_color",Color(0.005,0.02,0.025,0.9))
  letter.add_theme_constant_override("shadow_offset_y",4);letter.add_theme_constant_override("shadow_outline_size",5);wordmark.add_child(letter)
 var rule:=ColorRect.new();rule.color=Color("779f8c");rule.custom_minimum_size=Vector2(180,2);rule.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;brand.add_child(rule)
 panel=PanelContainer.new();add_child(panel)
 panel.anchor_left=0.05;panel.anchor_right=0.95;panel.anchor_top=0.53;panel.anchor_bottom=1;panel.offset_bottom=-176
 var skin:=StyleBoxFlat.new();skin.bg_color=Color(0.015,0.035,0.04,0.91);skin.set_corner_radius_all(6);skin.set_content_margin_all(14)
 skin.border_color=Color(0.42,0.67,0.58,0.4);skin.set_border_width_all(1);panel.add_theme_stylebox_override("panel",skin)
 var content:=VBoxContainer.new();content.add_theme_constant_override("separation",8);panel.add_child(content)
 status=Label.new();status.add_theme_font_size_override("font_size",14);status.add_theme_color_override("font_color",Color("a9ddc8"));content.add_child(status)
 var columns:=HBoxContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;columns.add_theme_constant_override("separation",24);content.add_child(columns)
 live=_console(columns,1.6);history=_console(columns,1.0)
 environment={"process_id":OS.get_process_id(),"Godot":Engine.get_version_info().string,"CPU_logical_processors":OS.get_processor_count(),"GPU":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"viewport":get_viewport_rect().size,"fps_cap":Engine.max_fps}
 var args:=OS.get_cmdline_args()
 var log_index:=args.find("--log-file")
 environment["engine_log" if log_index>=0 else "project_log_setting (launcher may override)"]=args[log_index+1] if log_index>=0 and log_index+1<args.size() else ProjectSettings.globalize_path(str(ProjectSettings.get_setting("debug/file_logging/log_path","user://logs/godot.log")))
 reset()

func _console(parent:Node,ratio:float)->RichTextLabel:
 var label:=RichTextLabel.new();label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;label.size_flags_vertical=Control.SIZE_EXPAND_FILL;label.size_flags_stretch_ratio=ratio
 label.selection_enabled=true;label.scroll_following=false;label.bbcode_enabled=false
 var mono:=SystemFont.new();mono.font_names=PackedStringArray(["Consolas","Liberation Mono","monospace"])
 label.add_theme_font_override("normal_font",mono);label.add_theme_font_size_override("normal_font_size",14);label.add_theme_color_override("default_color",Color("d5e3dd"))
 parent.add_child(label);return label

func reset()->void:
 started=Time.get_ticks_usec();stage_started=started;current_stage="Starting";stages.clear();latest.clear();next_refresh=0

func observe(stage:String,data:Dictionary={})->void:
 if stage!=current_stage:
  var now:=Time.get_ticks_usec()
  stages.append({"stage":current_stage,"microseconds":now-stage_started})
  current_stage=stage;stage_started=now
 latest=data.duplicate(true)

func _process(_delta:float)->void:
 if not is_visible_in_tree() or Time.get_ticks_usec()<next_refresh:return
 next_refresh=Time.get_ticks_usec()+250000
 refresh()

func refresh()->void:
 var began:=Time.get_ticks_usec()
 var snapshot:Dictionary=provider.call() if provider.is_valid() else {}
 var text:="LIVE WORK / raw counters · scroll and select to copy\n"
 text+=_lines(latest)+_lines(context)+_lines(snapshot)
 _replace_text(live,text)
 var timing:="COMPLETED STAGES / measured elapsed time\n"
 for row:Dictionary in stages:timing+="%7.2f s  %s\n"%[float(row.microseconds)/1000000.0,row.stage]
 timing+="\nSESSION / hardware and log\n"+_lines(environment)
 _replace_text(history,timing)
 sample_us=Time.get_ticks_usec()-began
 status.text="DEVELOPER DETAILS   ·   elapsed %.1f s   ·   current stage %.1f s   ·   refresh 4 Hz   ·   panel update %.2f ms"%[float(began-started)/1000000.0,float(began-stage_started)/1000000.0,sample_us/1000.0]

func _replace_text(label:RichTextLabel,text:String)->void:
 if label.text==text:return
 var scroll:=label.get_v_scroll_bar().value
 label.text=text
 label.get_v_scroll_bar().value=scroll

func _lines(data:Dictionary,prefix:String="")->String:
 var result:=""
 for key in data:
  var path:=prefix+str(key)
  var value:Variant=data[key]
  if value is Dictionary and not value.is_empty():result+=_lines(value,path+".")
  elif value is Array and not value.is_empty() and value[0] is Dictionary:
   for i in value.size():result+=_lines(value[i],"%s[%d]."%[path,i])
  else:result+="%s = %s\n"%[path,str(value)]
 return result
