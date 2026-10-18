# SPDX-License-Identifier: 0BSD
extends Control
const Launch=preload("res://demo/world_launch.gd")
var worlds: ItemList
var name_field: LineEdit
var seed_field: SpinBox
var preset: OptionButton
var gameplay: CheckBox
var notice: Label
var filter_field: LineEdit
var slots:=PackedStringArray()
var preparation_pid:=-1
var preparation_status:=""
var preparation_slot:=""
var preparation_gameplay:=true
var preparation_poll:=0.0
func heading(parent: Node,text: String,size: int=24) -> Label:
	var label:=Label.new();label.text=text;label.add_theme_font_size_override("font_size",size);parent.add_child(label);return label
func button(parent: Node,text: String,action: Callable) -> Button:
	var out:=Button.new();out.text=text;out.custom_minimum_size.y=48;out.pressed.connect(action);parent.add_child(out);return out
func _ready() -> void:
	get_tree().auto_accept_quit=true
	Engine.max_fps=60;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var background:=ColorRect.new();background.color=Color("101e22");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	var panel:=VBoxContainer.new();panel.position=Vector2(160,100);panel.size=Vector2(1600,880);panel.add_theme_constant_override("separation",24);add_child(panel)
	heading(panel,"TERRAFOREST / WORLDS",36)
	heading(panel,"Choose where to play. Each named world keeps its own saved progress.",20)
	var columns:=HBoxContainer.new();columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;columns.add_theme_constant_override("separation",48);panel.add_child(columns)
	var saved:=VBoxContainer.new();saved.custom_minimum_size.x=850;saved.add_theme_constant_override("separation",16);columns.add_child(saved)
	heading(saved,"Saved worlds")
	filter_field=LineEdit.new();filter_field.placeholder_text="Filter saved worlds";filter_field.text_changed.connect(func(_text: String):filter_list());saved.add_child(filter_field)
	worlds=ItemList.new();worlds.size_flags_vertical=Control.SIZE_EXPAND_FILL;worlds.custom_minimum_size.y=360;saved.add_child(worlds)
	button(saved,"Open selected world",func():launch_selected(false))
	button(saved,"Refresh saved worlds",refresh)
	var create:=VBoxContainer.new();create.size_flags_horizontal=Control.SIZE_EXPAND_FILL;create.add_theme_constant_override("separation",16);columns.add_child(create)
	heading(create,"Create a world")
	heading(create,"World name",18);name_field=LineEdit.new();name_field.placeholder_text="e.g. woodland_home";name_field.max_length=48;create.add_child(name_field)
	heading(create,"Landscape",18);preset=OptionButton.new();create.add_child(preset)
	for id: int in Launch.PRESETS:preset.add_item(Launch.PRESETS[id],id)
	preset.select(0)
	heading(create,"Seed",18);seed_field=SpinBox.new();seed_field.min_value=0;seed_field.max_value=2147483647;seed_field.step=1;seed_field.value=1703;create.add_child(seed_field)
	var explanation:=heading(create,"The seed and landscape apply only to new worlds. Saved worlds retain their generation settings. Integrated worlds are prepared and verified before play; first creation can take several minutes.",18);explanation.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	button(create,"Create and play",func():launch_selected(true))
	gameplay=CheckBox.new();gameplay.text="Gameplay material costs (uncheck for free editor)";gameplay.button_pressed=true;panel.add_child(gameplay)
	notice=heading(panel,"",18);notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;notice.custom_minimum_size.y=54
	button(panel,"Quit",func():get_tree().quit())
	refresh()
func refresh() -> void:
	if preparation_pid>=0:return
	slots=Launch.saved_slots();filter_list()
	notice.text="%d saved worlds. Save from the Actions menu or with F5 while playing."%slots.size()
func filter_list() -> void:
	worlds.clear()
	for slot: String in slots:
		if filter_field.text.is_empty() or slot.to_lower().contains(filter_field.text.to_lower()):worlds.add_item(slot)
func launch_selected(create: bool) -> void:
	if preparation_pid>=0:return
	var slot:=name_field.text.strip_edges()
	if not create:
		if worlds.get_selected_items().is_empty():notice.text="Select a saved world first.";return
		slot=worlds.get_item_text(worlds.get_selected_items()[0])
	var result:=Launch.command(slot,create,preset.get_selected_id(),int(seed_field.value),gameplay.button_pressed)
	if not result.ok:notice.text=result.reason;return
	if result.get("prepare",false):
		preparation_slot=slot;preparation_gameplay=gameplay.button_pressed
		preparation_status="user://world_preparation_%d_%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
		result.args.append_array(PackedStringArray(["--status-file",ProjectSettings.globalize_path(preparation_status)]))
		preparation_pid=OS.create_process("python",result.args,false)
		if preparation_pid<0:notice.text="Could not start Python for world preparation. Install Python or use the preparation command.";return
		Engine.max_fps=10
		notice.text="Preparing and verifying %s. The preparation window will close when finished, then your world will open. Existing saves are preserved."%slot
		return
	# The browser owns no world worker or canonical save. Launch one world and
	# exit the browser instead of replacing a live world's storage ownership.
	_open_game(result.args)

func _process(delta:float)->void:
	if preparation_pid<0:return
	preparation_poll-=delta
	if preparation_poll>0:return
	preparation_poll=0.5
	if OS.is_process_running(preparation_pid):return
	preparation_pid=-1;Engine.max_fps=60
	var result:Variant=JSON.parse_string(FileAccess.get_file_as_string(preparation_status)) if FileAccess.file_exists(preparation_status) else null
	refresh()
	if not result is Dictionary or result.get("state","")!="ready":
		notice.text="World preparation did not finish. Existing saves are preserved. " + (str(result.get("reason",""))+" Logs: "+str(result.get("report","")) if result is Dictionary else "Check that Python is available.")
		return
	var launch:=Launch.command(preparation_slot,false,12,0,preparation_gameplay)
	if not launch.ok:notice.text=launch.reason;return
	_open_game(launch.args)

func _open_game(args:PackedStringArray)->void:
	var pid:=OS.create_process(OS.get_executable_path(),args)
	if pid<0:notice.text="Could not start Godot. Select the saved world to try again.";return
	get_tree().quit()
