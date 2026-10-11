# SPDX-License-Identifier: 0BSD
extends GridContainer
var buttons: Array[Button]=[]
var selected:=-1
var cursor:=0
var empty_slots: Array[bool]=[]
func configure(controller: Object,side: String) -> void:
	columns=4;add_theme_constant_override("h_separation",6);add_theme_constant_override("v_separation",6)
	for i in 32:
		var button=preload("res://addons/player_runtime/inventory_slot.gd").new()
		button.controller=controller;button.side=side;button.slot=i;button.custom_minimum_size=Vector2(124,54)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.focus_mode=Control.FOCUS_NONE
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(select.bind(i));add_child(button);buttons.append(button);empty_slots.append(true)
func select(index: int) -> void:
	selected=index
	for i in buttons.size():buttons[i].set_appearance(empty_slots[i],false,i==index)
func get_selected_items() -> PackedInt32Array:
	return PackedInt32Array([selected]) if selected>=0 else PackedInt32Array()
func clear() -> void:
	cursor=0;select(-1)
func add_item(text: String,empty: bool=false) -> void:
	empty_slots[cursor]=empty;buttons[cursor].text=text;buttons[cursor].set_appearance(empty,false,cursor==selected);cursor+=1
