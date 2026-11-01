# SPDX-License-Identifier: 0BSD
extends VBoxContainer
const TYPES={301:0,302:1,303:2}
const NAMES=["Head","Body","Feet"]
var hud: Node
var buttons: Array[Button]=[]
var portrait:Control
func _ready() -> void:
	add_theme_constant_override("separation",12)
	var title:=Label.new();title.text="CHARACTER";title.add_theme_font_size_override("font_size",26);add_child(title)
	portrait=preload("res://addons/player_runtime/character_portrait.gd").new();add_child(portrait)
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",8);add_child(row)
	for i in 3:
		var button=preload("res://addons/player_runtime/inventory_slot.gd").new();button.controller=self;button.side="equipment";button.slot=i;button.custom_minimum_size=Vector2(116,84)
		row.add_child(button);buttons.append(button)
	var help:=Label.new();help.text="Drag clothing into Head, Body or Feet.\nDrag it back to your backpack to remove.";help.add_theme_font_size_override("font_size",14);add_child(help)
	refresh()
func set_active(value:bool)->void:
	if portrait!=null:portrait.set_active(value)
func refresh() -> void:
	if buttons.is_empty():return
	var state: Dictionary=hud.equipment.snapshot(1)
	for i in 3:
		var item: int=state.slots[i].item
		buttons[i].present(state.slots[i],hud.RESOURCES.get(item,"Empty"),NAMES[i])
		buttons[i].set_appearance(item==0,item!=0,false)
func drag_data(side: String,slot: int) -> Dictionary:
	if side!="equipment" or slot<0 or slot>=NAMES.size() or not hud.inventory_open:return {}
	var state: Dictionary=hud.equipment.snapshot(1)
	if not hud.inventory_open or state.slots[slot].count==0:return {}
	return {"owner":hud.get_instance_id(),"side":"equipment","slot":slot,"count":1,"revision":hud.inventory.snapshot().revision,"equipment_revision":state.store_revision}
func accepts_drag(side: String,slot: int,data: Variant) -> bool:
	if side!="equipment" or slot<0 or slot>=NAMES.size() or not hud.inventory_open or not data is Dictionary or data.get("owner",0)!=hud.get_instance_id() or data.get("side","")!="player":return false
	for field in ["slot","count","revision","equipment_revision"]:
		if not data.has(field) or typeof(data[field])!=TYPE_INT:return false
	if data.slot<0 or data.slot>=32 or data.count<1 or data.revision<0 or data.equipment_revision<0:return false
	var state: Dictionary=hud.inventory.snapshot()
	return state.revision==data.revision and hud.equipment.snapshot(1).store_revision==data.equipment_revision and state.slots[data.slot].count>0 and TYPES.get(int(state.slots[data.slot].item),-1)==slot
func drop_stack(side: String,slot: int,data: Variant) -> void:
	if not accepts_drag(side,slot,data):return
	var result: Dictionary=hud.equipment.drag_slots(1,hud.inventory,false,true,data.slot,slot,1,data.revision,data.equipment_revision)
	if result.ok:hud.inventory_changed.emit()
	hud.message.text="Clothing equipped" if result.ok else "Equipment changed; try again"
	hud.refresh()
