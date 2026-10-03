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
var shoulder: SpinBox
var surface: OptionButton
var build_button: Button
var continue_button: Button
var pending: Dictionary={}
var completed: Dictionary={}
func material_id() -> int:
	return 4 if surface.selected==0 else 1
func shoulder_width() -> float:
	return shoulder.value if material_id()==1 else 0.0
func _ready() -> void:
	layer=15
	panel=PanelContainer.new();panel.position=Vector2(1500,36);panel.custom_minimum_size=Vector2(380,0);add_child(panel)
	var margin:=MarginContainer.new();panel.add_child(margin)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);margin.add_child(column)
	var title:=Label.new();title.text="ROADS / FOUNDATIONS";title.add_theme_font_size_override("font_size",22);column.add_child(title)
	var hint:=Label.new();hint.text="Aim at terrain, then Esc to use controls.\nMark both ends, then build.\nClearance cuts terrain above the road.";column.add_child(hint)
	surface=OptionButton.new();surface.focus_mode=Control.FOCUS_NONE;surface.add_item("Asphalt road");surface.add_item("Stone foundation");column.add_child(surface)
	surface.item_selected.connect(func(_index: int):
		build_button.text="Build asphalt road" if material_id()==4 else "Grade stone foundation"
		shoulder.editable=material_id()==1
		selection_changed.emit())
	width=_number(column,"Half-width (m)",0.5,16,3)
	depth=_number(column,"Depth (m)",1,8,2)
	clearance=_number(column,"Clearance cut (m; 0 disables)",0,16,0)
	shoulder=_number(column,"Foundation fill shoulder (m)",0,16,0);shoulder.editable=false
	shoulder.value_changed.connect(func(_value: float): selection_changed.emit())
	clearance.value_changed.connect(func(_value: float): selection_changed.emit())
	width.value_changed.connect(func(_value: float): selection_changed.emit())
	depth.value_changed.connect(func(_value: float): selection_changed.emit())
	for item in [["start","Mark start at aim"],["finish","Mark end at aim"],["level","Level end to start height"],["build","Build asphalt road"],["continue","Continue from completed end"],["clear","Clear selection"]]:
		var button:=Button.new();button.text=item[1];button.focus_mode=Control.FOCUS_NONE;column.add_child(button)
		if item[0]=="build": build_button=button
		if item[0]=="continue": continue_button=button;continue_button.disabled=true
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
func level_selection() -> bool:
	if not has_start or not has_finish:
		status.text="Mark both ends before leveling.";return false
	if not start.is_finite() or not finish.is_finite():
		status.text="Invalid endpoint.";return false
	var point:=finish;point.y=start.y
	mark(false,point)
	status.text+="\nLevel preview only · build to apply terrain grading."
	return true
func track_submission(terrain: Node) -> void:
	pending={"epoch":terrain.epoch,"ticket":terrain.edit_ticket,"revision":terrain.density_revision,"finish":finish,"width":width.value,"depth":depth.value,"clearance":clearance.value,"shoulder":shoulder_width(),"surface":surface.selected}
	continue_button.disabled=true
func poll_submission(terrain: Node) -> void:
	if not completed.is_empty() and completed.epoch!=terrain.epoch:
		completed={};continue_button.disabled=true
	if pending.is_empty(): return
	if terrain.epoch!=pending.epoch or terrain.stopping:
		pending={};status.text="Road work interrupted by world change.";return
	if terrain.pending_edit: return
	var outcome: Dictionary=terrain.last_edit_outcome
	var expected: int=pending.revision+(1 if outcome.get("status","")=="published" else 0)
	if outcome.get("epoch",-1)==pending.epoch and outcome.get("ticket",-1)==pending.ticket and outcome.get("status","") in ["published","unchanged"] and outcome.get("revision",-1)==expected and terrain.density_revision==expected:
		completed=pending.duplicate();continue_button.disabled=false
		status.text="Section completed. Continue from its exact end, or mark a new route."
	else:
		status.text="Road section did not publish successfully. Check terrain before retrying."
		continue_button.disabled=completed.is_empty()
	pending={}
func continue_selection(terrain: Node) -> bool:
	if not pending.is_empty() or completed.is_empty() or completed.epoch!=terrain.epoch:
		status.text="No completed section in this world to continue.";return false
	start=completed.finish;has_start=true;has_finish=false
	width.value=completed.width;depth.value=completed.depth;clearance.value=completed.clearance
	surface.select(completed.surface);surface.item_selected.emit(completed.surface);shoulder.value=completed.shoulder
	status.text="Start at completed end: %s\nMark the next end. Use Level to continue at this height." % str(start)
	selection_changed.emit();return true
func validation_error() -> String:
	if not has_start or not has_finish: return "Mark both ends first."
	if not start.is_finite() or not finish.is_finite(): return "Invalid endpoint."
	if maxf(start.y,finish.y)+clearance.value>250: return "Clearance reaches the world ceiling."
	var length:=Vector2(finish.x-start.x,finish.z-start.z).length()
	if length<1 or length>128: return "Horizontal length must be 1–128 m."
	if absf(finish.y-start.y)>length*0.25: return "Grade exceeds 25%. Choose a gentler route."
	for point: Vector3 in [start,finish]:
		var extent: float=width.value+shoulder_width()
		if point.x<extent+5 or point.x>1995-extent or point.z<extent+5 or point.z>1995-extent or point.y<depth.value+4 or point.y>250: return "Road is too close to a world boundary."
	return ""
