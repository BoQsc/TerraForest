# SPDX-License-Identifier: 0BSD
extends Control
## Community hub overlay: chat, news, issues and the update placeholder.
##
## Owns no game state. `worlds.gd` adds it to the browser and calls `open()`;
## it drives `Chat` (Forge realtime) and `Feeds` (public Forge files) itself.
const Chat=preload("res://addons/hub/chat.gd")
const Feeds=preload("res://addons/hub/feeds.gd")
const Config=preload("res://addons/hub/config.gd")
const Settings=preload("res://addons/hub/settings.gd")
var chat
var feeds:=Feeds.new()
## `local_identity` lets a test or a second copy join as a distinct name.
func _init(local_identity:Dictionary={})->void:
	chat=Chat.new(local_identity)
var status_label:Label
var room_select:OptionButton
var message_list:VBoxContainer
var scroll:ScrollContainer
var input_box:LineEdit
var nickname_box:LineEdit
var send_button:Button
var news_list:VBoxContainer
var issues_list:VBoxContainer
var updates_label:Label
var _rendered:Dictionary={}
var _pending_scroll:=false
func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	_build()
	# The community request shares the panel's lifetime, so closing the hub
	# releases it instead of leaving an orphan HTTPRequest in the tree.
	feeds.attach_to(self)
	chat.message_added.connect(func(room:String, _line:Dictionary):if room==chat.current_room:request_room_render())
	chat.room_changed.connect(func(_room:String):refresh_rooms();request_room_render())
	chat.presence_changed.connect(func(_room:String, _peers:Array):request_room_render())
	chat.link_changed.connect(_on_link_changed)
	set_process(false)
	visible=false
func _build()->void:
	var backdrop:=ColorRect.new()
	backdrop.color=Color(0.04,0.09,0.11,0.97)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left",48)
	margin.add_theme_constant_override("margin_right",48)
	margin.add_theme_constant_override("margin_top",24)
	margin.add_theme_constant_override("margin_bottom",24)
	add_child(margin)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	margin.add_child(column)
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",16)
	column.add_child(header)
	var title:=Label.new()
	title.text="TERRAFOREST / COMMUNITY"
	title.add_theme_font_size_override("font_size",28)
	title.add_theme_color_override("font_color",Color("91d5b4"))
	header.add_child(title)
	status_label=Label.new()
	status_label.text="offline"
	status_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	status_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color",Color("9bafad"))
	header.add_child(status_label)
	var back:=Button.new()
	back.text="Back"
	back.pressed.connect(close_panel)
	header.add_child(back)
	var tabs:=TabContainer.new()
	tabs.size_flags_vertical=Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	_build_chat_tab(tabs)
	_build_list_tab(tabs,"News","Latest project news.","news")
	_build_list_tab(tabs,"Issues","Reported problems and their status.","issues")
	_build_updates_tab(tabs)
func _build_chat_tab(parent:TabContainer)->void:
	var page:=VBoxContainer.new()
	page.name="Chat"
	page.add_theme_constant_override("separation",8)
	parent.add_child(page)
	var toolbar:=HBoxContainer.new()
	toolbar.add_theme_constant_override("separation",8)
	page.add_child(toolbar)
	room_select=OptionButton.new()
	room_select.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	room_select.item_selected.connect(func(index:int):select_room(room_select.get_item_text(index)))
	toolbar.add_child(room_select)
	toolbar.add_child(_label("Nickname"))
	nickname_box=LineEdit.new()
	nickname_box.text=str(chat.identity.get("nickname",""))
	nickname_box.max_length=24
	nickname_box.custom_minimum_size.x=180
	nickname_box.text_submitted.connect(func(text:String):apply_nickname(text))
	nickname_box.focus_exited.connect(func():apply_nickname(nickname_box.text))
	toolbar.add_child(nickname_box)
	scroll=ScrollContainer.new()
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	message_list=VBoxContainer.new()
	message_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	message_list.add_theme_constant_override("separation",4)
	scroll.add_child(message_list)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	page.add_child(row)
	input_box=LineEdit.new()
	input_box.placeholder_text="Say something to the room…"
	input_box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	input_box.max_length=Chat.MAX_TEXT
	input_box.text_submitted.connect(func(_text:String):send_current())
	row.add_child(input_box)
	send_button=Button.new()
	send_button.text="Send"
	send_button.disabled=true
	send_button.pressed.connect(send_current)
	row.add_child(send_button)
func _build_list_tab(parent:TabContainer, tab_name:String, hint:String, feed:String)->void:
	var page:=VBoxContainer.new()
	page.name=tab_name
	page.add_theme_constant_override("separation",8)
	parent.add_child(page)
	var row:=HBoxContainer.new()
	page.add_child(row)
	row.add_child(_label(hint))
	var refresh_button:=Button.new()
	refresh_button.text="Refresh"
	refresh_button.pressed.connect(func():feeds.refresh(feed))
	row.add_child(refresh_button)
	var list_scroll:=ScrollContainer.new()
	list_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(list_scroll)
	var sink:=VBoxContainer.new()
	sink.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	sink.add_theme_constant_override("separation",10)
	list_scroll.add_child(sink)
	if feed=="news":news_list=sink
	else:issues_list=sink
func _build_updates_tab(parent:TabContainer)->void:
	var page:=VBoxContainer.new()
	page.name="Updates"
	page.add_theme_constant_override("separation",10)
	parent.add_child(page)
	var title:=Label.new()
	title.text="Updates"
	title.add_theme_font_size_override("font_size",22)
	page.add_child(title)
	updates_label=Label.new()
	updates_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	page.add_child(updates_label)
	var tray_toggle:=CheckBox.new()
	tray_toggle.text="Experimental: notification-area (tray) icon"
	tray_toggle.button_pressed=Settings.tray_enabled()
	tray_toggle.toggled.connect(_set_tray_enabled)
	page.add_child(tray_toggle)
	_refresh_updates_text()
## Opt-in switch for the experimental tray icon; applies immediately and is
## remembered in user://hub/settings.json. Off means nothing is created.
func _set_tray_enabled(on:bool)->void:
	Settings.set_tray_enabled(on)
	preload("res://addons/hub/hub_window.gd").set_enabled(get_tree(),on)
func _label(text:String)->Label:
	var label:=Label.new()
	label.text=text
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color",Color("9bafad"))
	return label
## Shows the overlay and starts the community link on first open.
func open(connect_in:=0.0)->void:
	visible=true
	if not is_inside_tree():set_process(false)
	chat.start(connect_in)
	refresh_rooms()
	request_room_render()
	feeds.refresh("news")
	feeds.refresh("issues")
	_on_link_changed(chat.link_state,chat.link_detail)
	# Deferred: a direct set_process()/await would replace the caller's value
	# when the same frame still reaches the end of _ready().
	_tick.call_deferred()
func close_panel()->void:
	visible=false
	set_process(false)
## Turns on the per-frame pump only after _ready() (and open()) have finished.
func _tick()->void:
	if is_inside_tree():set_process(true)
func is_open()->bool:
	return visible
func _process(delta:float)->void:
	chat.tick(delta)
	feeds.poll(delta)
	if _pending_scroll:
		_pending_scroll=false
		scroll.scroll_vertical=int(scroll.get_v_scroll_bar().max_value)
	_sync_feed("news",news_list)
	_sync_feed("issues",issues_list)
	_refresh_updates_text()
func _sync_feed(feed:String, sink:VBoxContainer)->void:
	if _rendered.get(feed)==feeds.data.get(feed,null):return
	_rendered[feed]=feeds.data.get(feed,null)
	for child:Node in sink.get_children():child.queue_free()
	var list:Array=feeds.items(feed)
	if list.is_empty():
		sink.add_child(_label("Offline: "+feeds.error(feed) if not feeds.error(feed).is_empty() else "Nothing here yet."))
		return
	for entry:Variant in list:
		if not entry is Dictionary:continue
		var card:=VBoxContainer.new()
		card.add_theme_constant_override("separation",2)
		var head:=Label.new()
		head.text=str(entry.get("title",entry.get("name","Untitled")))
		head.add_theme_font_size_override("font_size",18)
		card.add_child(head)
		var meta:=Label.new()
		meta.text="%s%s"%[str(entry.get("date",entry.get("created","")))," · cached" if feeds.is_cached(feed) else ""]
		meta.add_theme_color_override("font_color",Color("9bafad"))
		meta.add_theme_font_size_override("font_size",13)
		card.add_child(meta)
		var body:=Label.new()
		body.text=str(entry.get("body",entry.get("summary","")))
		body.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		card.add_child(body)
		sink.add_child(card)
func _refresh_updates_text()->void:
	var latest:=feeds.latest_version()
	var current:=str(ProjectSettings.get_setting("application/config/version","unknown"))
	var text:="This build: %s\nUpdate checks are a placeholder in this build. Nothing is downloaded or installed."%current
	if not latest.is_empty():text+="\nLatest announced: %s"%latest
	if updates_label!=null and updates_label.text!=text:updates_label.text=text
func refresh_rooms()->void:
	if room_select==null:return
	room_select.clear()
	for room:String in chat.rooms:room_select.add_item(room)
	for index:int in chat.rooms.size():
		if chat.rooms[index]==chat.current_room:room_select.select(index)
func _on_link_changed(state:int, detail:String)->void:
	if status_label==null:return
	status_label.text=chat.state_name() if detail.is_empty() else "%s · %s"%[chat.state_name(),detail]
	send_button.disabled=state!=Chat.Realtime.State.OPEN
func request_room_render()->void:
	if not is_inside_tree():return
	_render_room.call_deferred()
func _render_room()->void:
	if message_list==null:return
	for child:Node in message_list.get_children():
		message_list.remove_child(child)
		child.queue_free()
	var names:Array=[]
	for peer:Variant in chat.peers():
		names.append(str(peer.get("nickname","anonymous")) if peer is Dictionary else str(peer))
	var who:=_label("%d in %s%s" % [names.size(),chat.current_room,(": "+", ".join(names)) if not names.is_empty() else ""])
	who.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	message_list.add_child(who)
	for line:Dictionary in chat.lines():
		var row:=Label.new()
		var kind:=str(line.get("kind","chat"))
		row.text="%s  %s: %s"%[_clock(line),line.get("nickname","system"),Chat.plain(str(line.get("text","")))] if kind!="error" else "⚠ "+str(line.get("text",""))
		if kind=="error":row.add_theme_color_override("font_color",Color("e0a060"))
		elif kind=="dm":row.add_theme_color_override("font_color",Color("91d5b4"))
		row.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		message_list.add_child(row)
	_pending_scroll=true
func _clock(line:Dictionary)->String:
	var ms:=int(line.get("ts",0))
	var seconds:=int(ms/1000.0) if ms>100000000000 else ms
	var bias:=int(Time.get_time_zone_from_system().get("bias",0))
	var stamp:=Time.get_datetime_dict_from_unix_time(seconds+bias*60)
	return "%02d:%02d"%[stamp.hour,stamp.minute]
func apply_nickname(text:String)->void:
	chat.set_nickname(text)
	nickname_box.text=str(chat.identity.get("nickname",""))
	request_room_render()
## Sends the input line. Returns true when Forge accepted the message (headless
## checks call this directly; the Send button and Enter call it too).
func send_current()->bool:
	if input_box==null:return false
	var sent:bool=chat.send_text(input_box.text)
	if sent:input_box.text=""
	request_room_render()
	return sent
## Switches the room shown in the chat tab and refreshes the selector.
func select_room(room:String)->void:
	chat.switch_room(room)
	refresh_rooms()
	request_room_render()
