# SPDX-License-Identifier: 0BSD
extends Control
const Registry=preload("res://addons/ui_sets/registry.gd")
var sets:Dictionary
var chooser:OptionButton
var mode:OptionButton
var screen:OptionButton
var description:Label
var status:Label
var activate_button:Button
var viewport:SubViewport
var preview:Node
var ids:Array=[]
signal activated(id:String)
func _ready()->void:
	get_tree().auto_accept_quit=true
	preload("res://addons/world_runtime/mouse_ownership.gd").set_mode(self,Input.MOUSE_MODE_VISIBLE)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preload("res://demo/world_creation_panel.gd").apply_theme(self)
	var background:=ColorRect.new();background.color=Color("0b171d");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side:String in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,20)
	add_child(margin)
	var column:=VBoxContainer.new();margin.add_child(column)
	var heading:=Label.new();heading.text="World UI studio";heading.add_theme_font_size_override("font_size",28);column.add_child(heading)
	var row:=HBoxContainer.new();column.add_child(row)
	chooser=OptionButton.new();chooser.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(chooser)
	mode=OptionButton.new();mode.add_item("Preserved reference");mode.add_item("Live adapter preview");row.add_child(mode)
	screen=OptionButton.new();row.add_child(screen)
	var reload:=Button.new();reload.text="Rescan sets";reload.pressed.connect(rescan);row.add_child(reload)
	description=Label.new();description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;description.custom_minimum_size.y=48;column.add_child(description)
	var frame:=TextureRect.new();frame.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;frame.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;frame.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(frame)
	viewport=SubViewport.new();viewport.size=Vector2i(1920,1080);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;viewport.gui_disable_input=true;add_child(viewport);frame.texture=viewport.get_texture()
	var footer:=HBoxContainer.new();column.add_child(footer)
	status=Label.new();status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;footer.add_child(status)
	activate_button=Button.new();activate_button.text="Activate set";activate_button.pressed.connect(activate_selected);footer.add_child(activate_button)
	var back:=Button.new();back.text="Back to worlds";back.pressed.connect(func():get_tree().change_scene_to_file("res://demo/worlds.tscn"));footer.add_child(back)
	chooser.item_selected.connect(func(_index:int):refresh_preview())
	mode.item_selected.connect(func(_index:int):refresh_preview())
	screen.item_selected.connect(func(index:int):
		if is_instance_valid(preview) and preview.has_method("show_screen"):preview.show_screen(index))
	rescan()
func rescan()->void:
	sets=Registry.discover();ids=sets.keys();ids.sort();chooser.clear()
	var active_id:String=Registry.active().id
	for id:String in ids:
		var value:Resource=sets[id];chooser.add_item(value.title+(" · reference only" if not value.runtime_enabled else ""))
		if id==active_id:chooser.select(chooser.item_count-1)
	refresh_preview()
func refresh_preview()->void:
	if ids.is_empty():status.text="No valid UI sets discovered";return
	var value:Resource=sets[ids[chooser.selected]]
	description.text=value.description
	var error:=Registry.validate(value,true);activate_button.disabled=not error.is_empty()
	status.text=("Active: "+Registry.active().title) if error.is_empty() else error
	if is_instance_valid(preview):preview.free();preview=null
	screen.clear()
	if mode.selected==1 and error.is_empty():
		# Preview selection is process-local and restored before any real UI event.
		var old:=Registry.session_id;Registry.session_id=value.id
		viewport.size=Vector2i(1920,1080)
		preview=Registry.resolve(value).runtime_preview.instantiate();viewport.add_child(preview)
		Registry.session_id=old
	else:
		var old:=Registry.session_id
		if error.is_empty():Registry.session_id=value.id
		viewport.size=value.preview_size
		preview=value.preview.instantiate();viewport.add_child(preview)
		Registry.session_id=old
	var pages:PackedStringArray=Registry.resolve(value).runtime_preview_pages if mode.selected==1 and error.is_empty() else value.preview_pages
	var count:=pages.size()
	for label:String in pages:screen.add_item(label)
	screen.disabled=count==1
	if preview.has_method("set_mock_time"):preview.set_mock_time(9.4)
func activate_selected()->void:
	if ids.is_empty():return
	var result:=Registry.activate(ids[chooser.selected])
	if not result.ok:status.text=result.reason;return
	status.text="Activated · "+Registry.active().title
	activated.emit(Registry.active().id)
	# Only navigate a real studio scene. Embedded test/preview instances stay isolated.
	if get_tree().current_scene==self:get_tree().change_scene_to_file.call_deferred("res://demo/worlds.tscn")
