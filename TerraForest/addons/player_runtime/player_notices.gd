# SPDX-License-Identifier: 0BSD
extends CanvasLayer
var allowed:Callable
var general_top:Callable
var toast:PanelContainer
var quest_title:Label
var general:Label
var queued:Array[String]=[]
var current:=""
var quest_age:=0.0
var general_age:=0.0
var shown:=0
const QUEST_DURATION:=3.6
const GENERAL_DURATION:=4.0

func _ready()->void:
	layer=25
	toast=PanelContainer.new();toast.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(toast)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.025,.055,.05,.9);style.border_color=Color("9cffe0");style.border_width_left=3
	for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:style.set_content_margin(side,14)
	toast.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.mouse_filter=Control.MOUSE_FILTER_IGNORE;toast.add_child(column)
	var heading:=Label.new();heading.mouse_filter=Control.MOUSE_FILTER_IGNORE;heading.text="Added quest";heading.add_theme_font_size_override("font_size",14);heading.add_theme_color_override("font_color",Color("9cffe0"));column.add_child(heading)
	quest_title=Label.new();quest_title.mouse_filter=Control.MOUSE_FILTER_IGNORE;quest_title.add_theme_font_size_override("font_size",22);quest_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;column.add_child(quest_title)
	general=Label.new();general.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;general.mouse_filter=Control.MOUSE_FILTER_IGNORE;general.add_theme_font_size_override("font_size",18)
	general.add_theme_color_override("font_shadow_color",Color.BLACK);general.add_theme_constant_override("shadow_offset_x",1);general.add_theme_constant_override("shadow_offset_y",2);add_child(general)
	get_viewport().size_changed.connect(layout);layout();toast.hide();general.hide();set_process(false)

func layout()->void:
	var dimensions:=get_viewport().get_visible_rect().size
	toast.custom_minimum_size.x=minf(380,dimensions.x-48);toast.size=Vector2(toast.custom_minimum_size.x,0)
	toast.position=Vector2((dimensions.x-toast.size.x)*.5,104)
	general.size=Vector2(minf(1100,dimensions.x-48),30)
	general.position=Vector2((dimensions.x-general.size.x)*.5,general_top.call() if general_top.is_valid() else dimensions.y-208)

func quest_added(title:String)->void:
	var value:=title.strip_edges().left(120)
	if value.is_empty() or value==current or queued.has(value):return
	if queued.size()==4:queued.pop_front()
	queued.append(value);set_process(true)

func notify(text:String)->void:
	if general==null:return
	var value:=text.get_slice("\n",0).strip_edges().left(140)
	if value.is_empty():return
	general.text=value;general_age=0.0;set_process(true)

func _process(delta:float)->void:
	if allowed.is_valid() and not allowed.call():toast.hide();general.hide();return
	if current.is_empty() and not queued.is_empty():
		current=queued.pop_front();quest_title.text=current;quest_age=0;shown+=1;layout()
	if not current.is_empty():
		quest_age+=delta
		var enter:=smoothstep(0,.24,quest_age)
		toast.position.y=104-12*(1-enter);toast.modulate.a=enter*(1-smoothstep(QUEST_DURATION-.4,QUEST_DURATION,quest_age));toast.show()
		if quest_age>=QUEST_DURATION:current="";toast.hide()
	if not general.text.is_empty():
		general_age+=delta;general.modulate.a=smoothstep(0,.12,general_age)*(1-smoothstep(GENERAL_DURATION-.35,GENERAL_DURATION,general_age));general.show()
		if general_age>=GENERAL_DURATION:general.text="";general.hide()
	if current.is_empty() and queued.is_empty() and general.text.is_empty():set_process(false)
