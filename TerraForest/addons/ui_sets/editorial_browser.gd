# SPDX-License-Identifier: 0BSD
extends RefCounted
## Functional controls arranged like the preserved Survey and Planet references.
## The host remains the sole owner of the catalog, save actions and job state.
const Form=preload("res://demo/world_creation_panel.gd")
const Focus=preload("res://addons/player_runtime/text_input_focus.gd")
static func place(node:Control,parent:Node,rect:Rect2)->void:
	parent.add_child(node);node.position=rect.position;node.size=rect.size
static func build(host:Control,planet_layout:bool)->void:
	Form.apply_theme(host)
	var style:Resource=host.ui_set
	host.theme.default_font=style.body_font
	var background:=ColorRect.new();background.color=style.background;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.add_child(background)
	var canvas:=preload("res://addons/ui_sets/design_canvas.gd").new();canvas.name="EditorialWorldScreens";host.add_child(canvas)
	host.set_meta("ui_layout","planet" if planet_layout else "survey")
	var brand:Label=host.heading(canvas,"TerraForest",28);brand.position=Vector2(64,28);brand.add_theme_font_override("font",style.heading_font);brand.add_theme_color_override("font_color",style.accent)
	var tagline:Label=host.heading(canvas,"An open-source world-building project",13);tagline.position=Vector2(64,68)
	var chapter:Label=host.heading(canvas,"WORLDS / YOUR NEXT CHAPTER",13);chapter.position=Vector2(1460,40)
	var tabs:=TabContainer.new();place(tabs,canvas,Rect2(64,112,1792,866));host.world_tabs=tabs
	tabs.add_theme_stylebox_override("panel",StyleBoxEmpty.new());tabs.add_theme_constant_override("side_margin",0)
	for state:String in ["tab_selected","tab_unselected","tab_hovered"]:
		var skin:=Form.box(Color.TRANSPARENT,Color.TRANSPARENT,0);skin.content_margin_left=0;skin.content_margin_right=60;skin.content_margin_top=12;skin.content_margin_bottom=16
		tabs.add_theme_stylebox_override(state,skin)
	tabs.add_theme_color_override("font_selected_color",style.accent)
	tabs.tab_changed.connect(func(index:int):
		if index==1 and host.preview_view.texture==null:host.preview_due_ms=Time.get_ticks_msec()+host.PREVIEW_DELAY_MS)
	var saved:=Control.new();saved.name="My worlds";tabs.add_child(saved)
	var list_title:Label=host.heading(saved,"CHOOSE A WORLD" if planet_layout else "Saved worlds",48 if planet_layout else 26)
	list_title.position=Vector2(0,20);list_title.add_theme_font_override("font",style.heading_font)
	var subtitle:Label=host.heading(saved,"Pick up where you left off, or shape a new world from a seed.",16);subtitle.position=Vector2(0,84);subtitle.visible=planet_layout
	var tools_y:=126.0 if planet_layout else 72.0
	host.sort_order=OptionButton.new();place(host.sort_order,saved,Rect2(0,tools_y,310,40))
	for text:String in ["Last played · newest first","Created · newest first","Name"]:host.sort_order.add_item(text)
	host.sort_order.item_selected.connect(func(_index:int):host.refresh())
	host.filter_field=LineEdit.new();Focus.configure(host.filter_field);host.filter_field.placeholder_text="Filter saved worlds";place(host.filter_field,saved,Rect2(326,tools_y,550,40));host.filter_field.text_changed.connect(func(_text:String):host.filter_list())
	host.show_preparation=CheckBox.new();host.show_preparation.text="Generation drafts (developer, read-only)";place(host.show_preparation,saved,Rect2(0,tools_y+44,876,32));host.show_preparation.visible="--developer-worlds" in OS.get_cmdline_user_args();host.show_preparation.toggled.connect(func(_on:bool):host.refresh())
	host.worlds=ItemList.new();place(host.worlds,saved,Rect2(0,tools_y+88,876,396));host.worlds.fixed_column_width=850;host.worlds.fixed_icon_size=Vector2i(1,1);host.worlds.add_theme_constant_override("v_separation",20);host.worlds.add_theme_constant_override("line_separation",34);host.worlds.add_theme_font_size_override("font_size",24)
	host.worlds.item_selected.connect(host.show_saved_details)
	host.worlds.item_activated.connect(func(_index:int):host.launch_selected(false))
	var actions:=HFlowContainer.new();place(actions,saved,Rect2(0,tools_y+506,876,100))
	var refresh:Button=host.button(actions,"Refresh worlds",host.refresh);refresh.custom_minimum_size.y=38
	host.photograph_button=host.button(actions,"Create / refresh photographs",host.refresh_photographs);host.photograph_button.custom_minimum_size.y=38
	host.photograph_cancel=host.button(actions,"Cancel photographs",host.cancel_photographs);host.photograph_cancel.hide()
	var recover:Button=host.button(actions,"Recover publication",host.show_recovery);recover.custom_minimum_size.y=38
	var create:Button=host.button(saved,"+  SHAPE A NEW WORLD" if planet_layout else "CREATE A WORLD",func():tabs.current_tab=1);create.position=Vector2(0,736);create.size=Vector2(320,48)
	if planet_layout:
		var planet:Control=preload("res://demo/world_screens/planet.gd").new();planet.radius_px=178.;planet.tree_count=900;planet.position=Vector2(1318,260)-Vector2.ONE*planet.viewport_side()*0.5;saved.add_child(planet)
		var caption:Label=host.heading(saved,"WORLD PORTRAIT · STYLIZED",12);caption.position=Vector2(1130,500);caption.add_theme_color_override("font_color",style.accent)
	host.saved_picture=TextureRect.new();host.saved_picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;host.saved_picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;host.saved_picture.clip_contents=true
	place(host.saved_picture,saved,Rect2(936,24,856,420) if not planet_layout else Rect2(936,546,190,112))
	host.saved_title=host.heading(saved,"Select a world",36);host.saved_title.position=Vector2(936,466) if not planet_layout else Vector2(1150,540);host.saved_title.size=Vector2(856 if not planet_layout else 640,50);host.saved_title.add_theme_font_override("font",style.heading_font)
	var facts:=ScrollContainer.new();facts.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;place(facts,saved,Rect2(936,528,856,230) if not planet_layout else Rect2(936,680,856,90))
	host.saved_details=host.heading(facts,"",16);host.saved_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;host.saved_details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	if planet_layout:host.saved_details.add_theme_font_size_override("font_size",13)
	var open:Button=host.button(saved,"OPEN SELECTED WORLD",func():host.launch_selected(false));open.position=Vector2(936,784);open.size=Vector2(300,48)
	host.ui_set.creation_view.build(host,tabs)
	host.gameplay=CheckBox.new();host.gameplay.text="Gameplay material costs (uncheck for free editor)";host.gameplay.button_pressed=true;place(host.gameplay,canvas,Rect2(64,1004,770,36))
	var bottom:=HBoxContainer.new();place(bottom,canvas,Rect2(870,998,986,48))
	host.notice=host.heading(bottom,"",14);host.notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;host.notice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	host.credits_button=host.button(bottom,"Credits & licenses",host.show_credits)
	host.button(bottom,"UI sets",host.open_ui_studio)
	host.button(bottom,"Quit",host.request_quit)
