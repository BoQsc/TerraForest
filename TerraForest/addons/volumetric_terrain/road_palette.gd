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
var prepared_street: Dictionary={}
var prepared_streets: Array=[]
var street_selector: OptionButton
var entrance_target: OptionButton
var street_choice: HBoxContainer
var selected_street: int=-1
var street_controls: HBoxContainer
var anchor_storage: RefCounted
var anchor_terrain: Node
func prepare_persistence(terrain: Node,persistence: RefCounted) -> bool:
	if not ClassDB.class_exists("NativeRoadAnchors"):
		GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	if not ClassDB.class_exists("NativeRoadAnchors"): return false
	anchor_terrain=terrain
	anchor_storage=ClassDB.instantiate("NativeRoadAnchors")
	return anchor_storage!=null and persistence.register_component("road_anchors",capture_anchors,restore_anchors,anchor_storage,PackedByteArray())
func capture_anchors() -> PackedByteArray:
	if prepared_street.is_empty() or prepared_street.epoch!=anchor_terrain.epoch: return PackedByteArray()
	var records:=PackedByteArray()
	for street: Dictionary in prepared_streets:
		var record: PackedByteArray=anchor_storage.encode(street.ends,street.width)
		if record.is_empty() or street.epoch!=anchor_terrain.epoch: return PackedByteArray([0])
		records.append_array(record)
	var data: PackedByteArray=records if prepared_streets.size()==1 else anchor_storage.encode_collection(records,selected_street)
	return PackedByteArray([0]) if data.is_empty() else data
func restore_anchors(data: PackedByteArray) -> bool:
	var decoded: Dictionary=anchor_storage.decode(data)
	if not decoded.ok: return false
	pending={};completed={};has_start=false;has_finish=false
	prepared_streets=decoded.streets
	for street: Dictionary in prepared_streets: street["epoch"]=anchor_terrain.epoch
	selected_street=decoded.selected
	prepared_street=prepared_streets[selected_street] if decoded.present else {}
	_refresh_street_selector()
	if is_instance_valid(continue_button): continue_button.disabled=true
	selection_changed.emit()
	return true
func _refresh_street_selector() -> void:
	if not is_instance_valid(street_selector): return
	street_selector.clear()
	for i in prepared_streets.size():
		var midpoint: Vector3=(prepared_streets[i].ends[0]+prepared_streets[i].ends[1])*0.5
		street_selector.add_item("Street %d · %.0f, %.0f" % [i+1,midpoint.x,midpoint.z])
	if selected_street>=0: street_selector.select(selected_street)
	street_selector.visible=not prepared_streets.is_empty()
	street_choice.visible=not prepared_streets.is_empty()
	street_controls.visible=not prepared_streets.is_empty()
func select_prepared_street(index: int) -> bool:
	if index<0 or index>=prepared_streets.size(): return false
	selected_street=index;prepared_street=prepared_streets[index]
	if is_instance_valid(street_selector): street_selector.select(index)
	return true
func material_id() -> int:
	return 4 if surface.selected==0 else 1
func shoulder_width() -> float:
	return shoulder.value if material_id()==1 else 0.0
func _ready() -> void:
	layer=15
	panel=PanelContainer.new();panel.position=Vector2(1500,36);panel.custom_minimum_size=Vector2(380,0);add_child(panel)
	var margin:=MarginContainer.new();panel.add_child(margin)
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,20)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",6);margin.add_child(column)
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
	for item in [["start","Mark start at aim"],["finish","Mark end at aim"],["level","Level end to start height"],["smooth","Preview smooth terrain road"],["build","Build asphalt road"],["continue","Continue from completed end"],["clear","Clear selection"]]:
		var button:=Button.new();button.text=item[1];button.focus_mode=Control.FOCUS_NONE;column.add_child(button)
		if item[0]=="build": build_button=button
		if item[0]=="continue": continue_button=button;continue_button.disabled=true
		button.pressed.connect(func(): action_requested.emit(item[0]))
	street_choice=HBoxContainer.new();column.add_child(street_choice);street_choice.hide()
	street_selector=OptionButton.new();street_selector.focus_mode=Control.FOCUS_NONE;street_selector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;street_choice.add_child(street_selector);street_selector.hide()
	entrance_target=OptionButton.new();entrance_target.focus_mode=Control.FOCUS_NONE;entrance_target.add_item("Set start");entrance_target.add_item("Set end");street_choice.add_child(entrance_target)
	entrance_target.tooltip_text="Choose which road endpoint the Street end A / B buttons set."
	street_selector.item_selected.connect(select_prepared_street)
	street_controls=HBoxContainer.new();column.add_child(street_controls);street_controls.hide()
	for end in 2:
		var button:=Button.new();button.text="Street end A" if end==0 else "Street end B";button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;button.focus_mode=Control.FOCUS_NONE;street_controls.add_child(button)
		button.pressed.connect(func(): action_requested.emit("street_a" if end==0 else "street_b"))
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.text="Select two terrain points. Maximum length 128 m; maximum grade 25%.";column.add_child(status)
	_refresh_street_selector()
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
	if not prepared_street.is_empty() and prepared_street.epoch!=terrain.epoch:
		prepared_street={};prepared_streets=[];selected_street=-1;_refresh_street_selector()
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
func register_prepared_street(plan: Dictionary,epoch: int) -> void:
	if plan.get("paving_segments",0)<=0 or not plan.has("street_ends"): return
	var lines: PackedVector3Array=plan.get("street_lines",plan.street_ends)
	if lines.size()<2 or lines.size()>20 or lines.size()%2!=0: return
	var next: Array=prepared_streets.duplicate(true) if prepared_street.is_empty() or prepared_street.epoch==epoch else []
	var selected: int=-1
	for offset in range(0,lines.size(),2):
		var ends:=lines.slice(offset,offset+2)
		selected=-1
		for i in next.size():
			if next[i].ends==ends: selected=i;break
		if selected<0:
			if next.size()>=256:
				status.text="Street entrance catalog is full (256). Existing entrances retained.";return
			selected=next.size();next.append({"ends":ends,"width":plan.street_width,"epoch":epoch})
		else: next[selected].width=plan.street_width
	prepared_streets.assign(next);selected_street=selected;prepared_street=prepared_streets[selected]
	_refresh_street_selector()
func select_street_end(index: int,terrain: Node,as_finish: bool=false) -> bool:
	if not pending.is_empty() or index<0 or index>1 or prepared_street.is_empty() or prepared_street.epoch!=terrain.epoch:
		status.text="No prepared street in this world, or a road section is still pending.";return false
	if prepared_street.width>32:
		status.text="This street exceeds the road tool's 32 m width. Connect narrower lanes manually.";return false
	if as_finish:
		if not has_start:
			status.text="Set the connecting road's start first.";return false
		if material_id()!=4 or not is_equal_approx(width.value*2,prepared_street.width):
			status.text="Use asphalt and match this street's %.1f m width before connecting." % prepared_street.width;return false
		finish=prepared_street.ends[index];has_finish=true
		var error:=validation_error()
		status.text="Exact street connection preview · build to apply." if error.is_empty() else error
		selection_changed.emit();return true
	start=prepared_street.ends[index];has_start=true;has_finish=false
	width.value=prepared_street.width*0.5;depth.value=8;clearance.value=12;shoulder.value=0
	surface.select(0);surface.item_selected.emit(0)
	status.text="Start at prepared street end %s: %s\nMark the connecting road's end, then build." % ["A" if index==0 else "B",str(start)]
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
