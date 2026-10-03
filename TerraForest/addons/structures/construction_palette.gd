# SPDX-License-Identifier: 0BSD
extends CanvasLayer
signal selection_requested(field: String,value: int)
signal capture_requested(action: String,title: String)
signal supply_requested(item: int)
signal stack_requested(count: int,title: String)
signal frontage_requested(lots: int,width: int,gap: int,seed: int,title: String)
var frontage_button: Button
var frontage_dialog: AcceptDialog
var frontage_lots: SpinBox
var frontage_width: SpinBox
var frontage_gap: SpinBox
var stack_count: SpinBox
var stack_button: Button
var supply: OptionButton
var supply_button: Button
var capture_name: LineEdit
var capture_status: Label
var archive_button: Button
var shape: OptionButton
var material: OptionButton
var rotation_choice: OptionButton
var prefab: OptionButton
var panel: PanelContainer
func _ready() -> void:
	layer=15
	panel=PanelContainer.new();panel.position=Vector2(1500,36);panel.custom_minimum_size=Vector2(380,0);add_child(panel)
	var margin:=MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	panel.add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);margin.add_child(column)
	var title:=Label.new();title.text="CONSTRUCTION";title.add_theme_font_size_override("font_size",22);column.add_child(title)
	shape=_option(column,"Shape",["Cube","Slab","Stairs","Slope","Post","Sphere"],"shape")
	material=_option(column,"Material",["Brick","Wood","Concrete","Metal"],"material")
	rotation_choice=_option(column,"Rotation",["0°","90°","180°","270°"],"rotation")
	prefab=_option(column,"Prefab",["Single blocks"],"prefab")
	var corners:=HBoxContainer.new();column.add_child(corners)
	for action: String in ["a","b"]:
		var button:=Button.new();button.text="Mark corner "+action.to_upper();button.focus_mode=Control.FOCUS_NONE
		button.pressed.connect(func(): capture_requested.emit(action,""));corners.add_child(button)
	var clear:=Button.new();clear.text="Clear";clear.focus_mode=Control.FOCUS_NONE;clear.pressed.connect(func(): capture_requested.emit("clear",""));corners.add_child(clear)
	capture_status=Label.new();capture_status.text="Aim at a block, then mark each corner.";capture_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(capture_status)
	capture_name=LineEdit.new();capture_name.placeholder_text="Prefab name";capture_name.max_length=48;column.add_child(capture_name)
	capture_name.text_submitted.connect(func(_text: String): capture_name.release_focus())
	var save:=Button.new();save.text="Capture and save prefab";save.focus_mode=Control.FOCUS_NONE
	save.pressed.connect(func(): capture_requested.emit("save",capture_name.text));column.add_child(save)
	var stack_row:=HBoxContainer.new();column.add_child(stack_row)
	stack_count=SpinBox.new();stack_count.custom_minimum_size=Vector2(130,0);stack_count.min_value=2;stack_count.max_value=32;stack_count.value=4;stack_count.step=1;stack_count.suffix="repeats";stack_row.add_child(stack_count)
	stack_button=Button.new();stack_button.text="Stack selected prefab";stack_button.focus_mode=Control.FOCUS_NONE
	stack_button.pressed.connect(func(): stack_requested.emit(int(stack_count.value),capture_name.text));stack_row.add_child(stack_button)
	frontage_button=Button.new();frontage_button.text="Create street frontage from selected prefab";frontage_button.focus_mode=Control.FOCUS_NONE;column.add_child(frontage_button)
	frontage_dialog=AcceptDialog.new();frontage_dialog.title="Street frontage";frontage_dialog.ok_button_text="Create and save";add_child(frontage_dialog)
	var frontage_fields:=VBoxContainer.new();frontage_dialog.add_child(frontage_fields)
	frontage_lots=_number(frontage_fields,"Buildings per side",1,64,2,1)
	frontage_width=_number(frontage_fields,"Street width (m)",4,64,8,2)
	frontage_gap=_number(frontage_fields,"Building gap / setback (m)",1,32,3,1)
	var notice:=Label.new();notice.text="Uses the prefab name entered in the construction panel.\nBuilding fronts must face local +Z.\nLayout only: terrain is not graded and asphalt is not laid.";frontage_fields.add_child(notice)
	frontage_button.pressed.connect(func(): frontage_dialog.popup_centered(Vector2i(550,330)))
	frontage_dialog.confirmed.connect(func(): frontage_requested.emit(int(frontage_lots.value),int(frontage_width.value),int(frontage_gap.value),1703,capture_name.text))
	archive_button=Button.new();archive_button.text="Archive selected personal prefab";archive_button.focus_mode=Control.FOCUS_NONE;archive_button.disabled=true
	archive_button.pressed.connect(func(): capture_requested.emit("archive",""));column.add_child(archive_button)
	var restore:=Button.new();restore.text="Restore last archived prefab";restore.focus_mode=Control.FOCUS_NONE
	restore.pressed.connect(func(): capture_requested.emit("restore",""));column.add_child(restore)
	var supply_row:=HBoxContainer.new();column.add_child(supply_row)
	supply=OptionButton.new();supply.focus_mode=Control.FOCUS_NONE
	for title_text: String in ["Brick","Wood","Concrete","Metal"]: supply.add_item(title_text)
	supply_row.add_child(supply)
	supply_button=Button.new();supply_button.text="Place supply at aim";supply_button.focus_mode=Control.FOCUS_NONE
	supply_button.pressed.connect(func(): supply_requested.emit(101+supply.selected));supply_row.add_child(supply_button)
	var hint:=Label.new();hint.text="[ / ] mark aimed corners A / B\nEsc releases / captures mouse\nLMB removes · RMB places\nCtrl+Z / Ctrl+Y undo / redo";column.add_child(hint)
	panel.hide()
func _option(parent: Control,title: String,values: Array,field: String) -> OptionButton:
	var label:=Label.new();label.text=title;parent.add_child(label)
	var option:=OptionButton.new();option.custom_minimum_size=Vector2(340,36);option.focus_mode=Control.FOCUS_NONE
	for value: String in values: option.add_item(value)
	option.item_selected.connect(func(index: int): selection_requested.emit(field,index))
	parent.add_child(option)
	return option
func _number(parent: Control,title: String,lo: int,hi: int,value: int,step: int) -> SpinBox:
	var row:=HBoxContainer.new();parent.add_child(row)
	var label:=Label.new();label.text=title;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(label)
	var field:=SpinBox.new();field.min_value=lo;field.max_value=hi;field.step=step;field.value=value;row.add_child(field)
	return field
func configure(assets: Array[Resource]) -> void:
	prefab.clear();prefab.add_item("Single blocks")
	for asset in assets: prefab.add_item(asset.resource_name)
func synchronize(active: bool,shape_id: int,material_id: int,quarter_turn: int,prefab_index: int) -> void:
	if panel==null: return
	panel.visible=active
	shape.select(shape_id-1);material.select(material_id);rotation_choice.select(quarter_turn);prefab.select(prefab_index+1)
	shape.disabled=prefab_index>=0
	material.disabled=prefab_index>=0
	stack_button.disabled=prefab_index<0
	frontage_button.disabled=prefab_index<0
	if not active: frontage_dialog.hide()
