# SPDX-License-Identifier: 0BSD
extends RefCounted
const TextInputFocus=preload("res://addons/player_runtime/text_input_focus.gd")
## Preserved shipped world browser. Host owns actions and world state.
static func build(host:Control)->void:
	preload("res://demo/world_creation_panel.gd").apply_theme(host)
	var background:=ColorRect.new();background.color=Color("0b171d");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.add_child(background)
	var margin:=MarginContainer.new();margin.add_theme_constant_override("margin_left",48);margin.add_theme_constant_override("margin_right",48);margin.add_theme_constant_override("margin_top",24);margin.add_theme_constant_override("margin_bottom",20);host.add_child(margin)
	host.get_viewport().size_changed.connect(host._fit_browser.bind(margin));host._fit_browser(margin)
	var panel:=VBoxContainer.new();panel.add_theme_constant_override("separation",14);margin.add_child(panel)
	var branding:=HBoxContainer.new();panel.add_child(branding)
	var identity:=VBoxContainer.new();identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL;identity.add_theme_constant_override("separation",2);branding.add_child(identity)
	var title:Label=host.heading(identity,"TERRAFOREST",32);title.add_theme_color_override("font_color",Color("91d5b4"))
	var tagline:Label=host.heading(identity,"An open-source world-building project",15);tagline.add_theme_color_override("font_color",Color("9bafad"))
	host.heading(branding,"WORLDS / YOUR NEXT CHAPTER",16)
	var workspace:=ScrollContainer.new();workspace.size_flags_vertical=Control.SIZE_EXPAND_FILL;workspace.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;panel.add_child(workspace)
	var columns:=TabContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;columns.size_flags_horizontal=Control.SIZE_EXPAND_FILL;workspace.add_child(columns)
	host.world_tabs=columns
	columns.tab_changed.connect(func(index:int):
		if index==1 and host.preview_view!=null and host.preview_view.texture==null:host.preview_due_ms=Time.get_ticks_msec()+host.PREVIEW_DELAY_MS)
	var saved:=VBoxContainer.new();saved.name="My worlds";saved.custom_minimum_size.x=850;saved.add_theme_constant_override("separation",16);columns.add_child(saved)
	host.heading(saved,"Saved worlds")
	host.sort_order=OptionButton.new();host.sort_order.add_item("Last played · newest first");host.sort_order.add_item("Created · newest first");host.sort_order.add_item("Name");host.sort_order.item_selected.connect(func(_index:int):host.refresh());saved.add_child(host.sort_order)
	host.sort_order.tooltip_text="Older worlds without recorded dates fall back to their last save time."
	var filters:=HBoxContainer.new();saved.add_child(filters)
	host.filter_field=LineEdit.new();TextInputFocus.configure(host.filter_field);host.filter_field.size_flags_horizontal=Control.SIZE_EXPAND_FILL;host.filter_field.placeholder_text="Filter saved worlds";host.filter_field.text_changed.connect(func(_text: String):host.filter_list());filters.add_child(host.filter_field)
	host.show_preparation=CheckBox.new();host.show_preparation.text="Generation drafts (developer, read-only)";host.show_preparation.visible="--developer-worlds" in OS.get_cmdline_user_args();host.show_preparation.toggled.connect(func(_on:bool):host.refresh());filters.add_child(host.show_preparation)
	var library_row:=HBoxContainer.new();library_row.add_theme_constant_override("separation",28);library_row.size_flags_vertical=Control.SIZE_EXPAND_FILL;saved.add_child(library_row)
	host.worlds=ItemList.new();host.worlds.size_flags_vertical=Control.SIZE_EXPAND_FILL;host.worlds.size_flags_horizontal=Control.SIZE_EXPAND_FILL;host.worlds.custom_minimum_size=Vector2(300,250);library_row.add_child(host.worlds)
	var detail_column:=VBoxContainer.new();detail_column.custom_minimum_size.x=380;detail_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;library_row.add_child(detail_column)
	host.saved_title=host.heading(detail_column,"Select a world",24)
	var picture_holder:=Control.new();picture_holder.custom_minimum_size=Vector2(380,200);detail_column.add_child(picture_holder)
	host.saved_picture=TextureRect.new();host.saved_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.saved_picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;host.saved_picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture_holder.add_child(host.saved_picture)
	host.saved_caption=Label.new();host.saved_caption.text="No world picture yet";host.saved_caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.saved_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;host.saved_caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;host.saved_caption.add_theme_font_size_override("font_size",20);host.saved_caption.add_theme_color_override("font_color",Color(1,1,1));host.saved_caption.add_theme_color_override("font_outline_color",Color(0,0,0,0.85));host.saved_caption.add_theme_constant_override("outline_size",6);host.saved_caption.visible=false;picture_holder.add_child(host.saved_caption)
	host.saved_details=host.heading(detail_column,"",18);host.saved_details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	host.worlds.item_selected.connect(host.show_saved_details)
	host.button(saved,"Open selected world",func():host.launch_selected(false))
	var library_actions:=HBoxContainer.new();saved.add_child(library_actions)
	host.button(library_actions,"Refresh saved worlds",host.refresh)
	host.photograph_button=host.button(library_actions,"Create / refresh photographs",host.refresh_photographs)
	host.photograph_cancel=host.button(library_actions,"Cancel photographs",host.cancel_photographs);host.photograph_cancel.hide()
	host.button(library_actions,"Recover interrupted publication",host.show_recovery)
	host.ui_set.creation_view.build(host,columns)
	host.gameplay=CheckBox.new();host.gameplay.text="Gameplay material costs (uncheck for free editor)";host.gameplay.button_pressed=true;panel.add_child(host.gameplay)
	var bottom:=HBoxContainer.new();bottom.alignment=BoxContainer.ALIGNMENT_END;panel.add_child(bottom)
	host.notice=host.heading(bottom,"",16);host.notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;host.notice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	host.credits_button=host.button(bottom,"Credits & licenses",host.show_credits)
	host.button(bottom,"UI sets",host.open_ui_studio)
	host.button(bottom,"Quit",host.request_quit)
