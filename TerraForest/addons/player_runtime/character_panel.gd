# SPDX-License-Identifier: 0BSD
extends VBoxContainer
const TYPES={301:0,302:1,303:2}
const NAMES=["Head","Body","Feet"]
var hud: Node
var buttons: Array[Button]=[]
func _ready() -> void:
	add_theme_constant_override("separation",18)
	var title:=Label.new();title.text="CHARACTER";title.add_theme_font_size_override("font_size",26);add_child(title)
	var help:=Label.new();help.text="Drag clothing onto its matching slot.\nDrag it back to your backpack to remove.";add_child(help)
	for i in 3:
		var button=preload("res://addons/player_runtime/inventory_slot.gd").new();button.controller=self;button.side="equipment";button.slot=i;button.custom_minimum_size=Vector2(370,110)
		add_child(button);buttons.append(button)
	refresh()
func refresh() -> void:
	if buttons.is_empty():return
	var state: Dictionary=hud.equipment.snapshot(1)
	for i in 3:
		var item: int=state.slots[i].item
		buttons[i].text=NAMES[i]+"\n"+hud.RESOURCES.get(item,"Empty")
		buttons[i].set_appearance(item==0,item!=0,false)
func drag_data(_side: String,slot: int) -> Dictionary:
	var state: Dictionary=hud.equipment.snapshot(1)
	if not hud.inventory_open or state.slots[slot].count==0:return {}
	return {"owner":hud.get_instance_id(),"side":"equipment","slot":slot,"count":1,"revision":hud.inventory.snapshot().revision,"equipment_revision":state.store_revision}
func accepts_drag(_side: String,slot: int,data: Variant) -> bool:
	if not hud.inventory_open or not data is Dictionary or data.get("owner",0)!=hud.get_instance_id() or data.get("side","")!="player":return false
	var state: Dictionary=hud.inventory.snapshot()
	return state.revision==data.revision and TYPES.get(int(state.slots[data.slot].item),-1)==slot
func drop_stack(side: String,slot: int,data: Variant) -> void:
	if not accepts_drag(side,slot,data):return
	var result: Dictionary=hud.equipment.drag_slots(1,hud.inventory,false,true,data.slot,slot,1,data.revision,data.equipment_revision)
	if result.ok:hud.inventory_changed.emit()
	hud.message.text="Clothing equipped" if result.ok else "Equipment changed; try again"
	hud.refresh()
