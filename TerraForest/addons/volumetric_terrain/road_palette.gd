# SPDX-License-Identifier: 0BSD
extends CanvasLayer
signal action_requested(action: String)
signal selection_changed
var start: Vector3
var finish: Vector3
var has_start:=false
var has_finish:=false
var panel: PanelContainer
var status: Label
var width: SpinBox
var depth: SpinBox
var clearance: SpinBox
func _ready() -> void:
	layer=15
	panel=PanelContainer.new();panel.position=Vector2(1500,36);panel.custom_minimum_size=Vector2(380,0);add_child(panel)
	var margin:=MarginContainer.new();panel.add_child(margin)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);margin.add_child(column)
	var title:=Label.new();title.text="ASPHALT ROAD";title.add_theme_font_size_override("font_size",22);column.add_child(title)
	var hint:=Label.new();hint.text="Aim at terrain, then Esc to use controls.\nMark both ends, then build.\nClearance cuts terrain above the road.";column.add_child(hint)
	width=_number(column,"Half-width (m)",0.5,16,3)
	depth=_number(column,"Depth (m)",1,8,2)
	clearance=_number(column,"Clearance cut (m; 0 disables)",0,16,0)
	clearance.value_changed.connect(func(_value: float): selection_changed.emit())
	width.value_changed.connect(func(_value: float): selection_changed.emit())
	depth.value_changed.connect(func(_value: float): selection_changed.emit())
	for item in [["start","Mark start at aim"],["finish","Mark end at aim"],["build","Build asphalt road"],["clear","Clear selection"]]:
		var button:=Button.new();button.text=item[1];button.focus_mode=Control.FOCUS_NONE;column.add_child(button)
		button.pressed.connect(func(): action_requested.emit(item[0]))
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.text="Select two terrain points. Maximum length 128 m; maximum grade 25%.";column.add_child(status)
	panel.hide()
func _number(parent: Control,title: String,minimum: float,maximum: float,value: float) -> SpinBox:
	var label:=Label.new();label.text=title;parent.add_child(label)
	var field:=SpinBox.new();field.min_value=minimum;field.max_value=maximum;field.step=0.5;field.value=value;parent.add_child(field);return field
func mark(first: bool,point: Vector3) -> void:
	if first: start=point;has_start=true
	else: finish=point;has_finish=true
	status.text="Start: %s\nEnd: %s" % [str(start) if has_start else "unset",str(finish) if has_finish else "unset"]
	selection_changed.emit()
func clear() -> void:
	has_start=false;has_finish=false;status.text="Road selection cleared."
	selection_changed.emit()
func validation_error() -> String:
	if not has_start or not has_finish: return "Mark both ends first."
	if not start.is_finite() or not finish.is_finite(): return "Invalid endpoint."
	if maxf(start.y,finish.y)+clearance.value>250: return "Clearance reaches the world ceiling."
	var length:=Vector2(finish.x-start.x,finish.z-start.z).length()
	if length<1 or length>128: return "Horizontal length must be 1–128 m."
	if absf(finish.y-start.y)>length*0.25: return "Grade exceeds 25%. Choose a gentler route."
	for point: Vector3 in [start,finish]:
		if point.x<width.value+5 or point.x>1995-width.value or point.z<width.value+5 or point.z>1995-width.value or point.y<depth.value+4 or point.y>250: return "Road is too close to a world boundary."
	return ""
