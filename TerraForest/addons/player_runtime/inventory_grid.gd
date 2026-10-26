# SPDX-License-Identifier: 0BSD
extends GridContainer
var buttons: Array[Button]=[]
var selected:=-1
var cursor:=0
var first_slot:=0
var capacity:=32
var empty_slots: Array[bool]=[]
func configure(controller: Object,side: String,start_slot:int=0) -> void:
	first_slot=clampi(start_slot,0,32)
	columns=4;add_theme_constant_override("h_separation",6);add_theme_constant_override("v_separation",6)
	for i in 32:
		var button=preload("res://addons/player_runtime/inventory_slot.gd").new()
		button.controller=controller;button.side=side;button.slot=i;button.custom_minimum_size=Vector2(124,54)
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.focus_mode=Control.FOCUS_NONE
		button.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		button.pressed.connect(select.bind(i));add_child(button);buttons.append(button);empty_slots.append(true)
	set_capacity(32)
func contains_slot(index:int)->bool:
	return index>=first_slot and index<capacity
func set_capacity(count:int)->void:
	capacity=clampi(count,0,buttons.size())
	for index in buttons.size():buttons[index].visible=contains_slot(index)
	if not contains_slot(selected):select(-1)
func select(index: int) -> void:
	selected=index if contains_slot(index) else -1
	for i in buttons.size():buttons[i].set_appearance(empty_slots[i],false,i==selected)
func get_selected_items() -> PackedInt32Array:
	return PackedInt32Array([selected]) if selected>=0 else PackedInt32Array()
func clear() -> void:
	cursor=first_slot;select(-1)
func add_item(text: String,empty: bool=false) -> void:
	empty_slots[cursor]=empty;buttons[cursor].text=text;buttons[cursor].set_appearance(empty,false,cursor==selected);cursor+=1
