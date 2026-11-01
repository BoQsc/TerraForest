# SPDX-License-Identifier: 0BSD
extends VBoxContainer
var hud:Node
var choices:OptionButton
var content:RichTextLabel
var seen_revision:=-1

func _ready()->void:
	add_theme_constant_override("separation",16)
	var title:=Label.new();title.text="JOURNAL";title.add_theme_font_size_override("font_size",26);add_child(title)
	choices=OptionButton.new();choices.custom_minimum_size=Vector2(370,42);choices.item_selected.connect(show_entry);add_child(choices)
	content=RichTextLabel.new();content.custom_minimum_size=Vector2(370,420);content.size_flags_vertical=Control.SIZE_EXPAND_FILL;content.bbcode_enabled=false;add_child(content)
	refresh()

func refresh()->void:
	if choices==null:return
	var state:Dictionary=hud.survival.snapshot()
	if seen_revision==state.revision:return
	seen_revision=state.revision
	var selected:int=choices.get_selected_id() if choices.item_count else -1
	choices.clear()
	for identity:int in hud.Consumables.ITEMS:
		if state.readings.has(identity):choices.add_item(hud.Consumables.ITEMS[identity].name,identity)
	if choices.item_count==0:content.text="Books, letters and journals you read are kept here.\n\nEquip and left-click, double-click an inventory item, or right-click → Use.";choices.disabled=true;return
	choices.disabled=false
	choices.select(maxi(0,choices.get_item_index(selected)));show_entry(choices.selected)

func show_entry(index:int)->void:
	if index<0 or index>=choices.item_count:return
	var identity:=choices.get_item_id(index);var entry:Dictionary=hud.Consumables.ITEMS[identity]
	content.text=entry.name+"\n\n"+entry.text+"\n\nRead %d time(s)."%hud.survival.snapshot().readings[identity]
