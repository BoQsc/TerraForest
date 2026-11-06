# SPDX-License-Identifier: 0BSD
extends Control
## Standalone Kaino SFX audition tool. It reads the pack and the bundled game
## sound definitions, previews WAVs, and saves slot-to-file selections.

const PACK_ROOT := "res://addons/audio_runtime/packs/Kaino"
const MANIFEST := "res://addons/audio_runtime/packs/nox/pack.audio.module.json"
const TextInputFocus := preload("res://addons/player_runtime/text_input_focus.gd")
const WavDecoder := preload("res://addons/audio_runtime/wav_decoder.gd")
const EventCatalog := preload("res://tools/kaino_event_catalog.gd")
const HUMAN_MODEL := "res://addons/characters/runtime/assets/Human.r11.glb"
const ZOMBIE_MODEL := "res://addons/characters/runtime/assets/Zombie.r4.glb"
const VEHICLE_SCENE := "res://vehicle_demo/scenes/car.tscn"
const TOOL_MODEL := "res://addons/characters/runtime/assets/Torch.glb"
const INK := Color(0.91, 0.95, 0.90)
const MUTED := Color(0.54, 0.66, 0.63)
const FAINT := Color(0.33, 0.43, 0.41)
const MINT := Color(0.49, 0.86, 0.70)
const GOLD := Color(0.86, 0.72, 0.42)
const PANEL := Color(0.035, 0.085, 0.08, 0.98)
const PANEL_DEEP := Color(0.015, 0.035, 0.035, 1.0)
const LINE := Color(0.20, 0.36, 0.32, 0.65)

var mapping_path := "res://addons/audio_runtime/kaino_audition_selection.json"
var files: Array[String] = []
var slots: Array[Dictionary] = []
var mapping: Dictionary = {}
var notes: Dictionary = {}
var deferred_sounds: Dictionary = {}
var rejected_sounds: Dictionary = {}
var file_rows: Dictionary = {}
var file_boxes: Dictionary = {}
var file_later_buttons: Dictionary = {}
var file_reject_buttons: Dictionary = {}
var slot_rows: Dictionary = {}
var selected_file := ""
var selected_slot := ""
var audio_player: AudioStreamPlayer
var autosave_timer: Timer
var search: LineEdit
var notes_edit: TextEdit
var loading_notes := false
var event_search: LineEdit
var hide_occupied: CheckButton
var sound_tab: Button
var sound_later_tab: Button
var sound_noted_tab: Button
var sound_rejected_tab: Button
var sound_used_tab: Button
var show_later_sounds := false
var show_noted_sounds := false
var show_rejected_sounds := false
var show_used_sounds := false
var file_count: Label
var slot_count: Label
var selected_file_label: Label
var selected_slot_label: Label
var status: Label
var save_status: Label
var play_slot_button: Button
var assign_button: Button
var clear_button: Button
var preview_container: SubViewportContainer
var preview_viewport: SubViewport
var preview_stage: Node3D
var preview_model_root: Node3D
var preview_model: Node3D
var preview_camera: Camera3D
var preview_animation_player: AnimationPlayer
var preview_label: Label
var preview_kind := ""

func _ready() -> void:
	get_window().title = "Kaino SFX Audition — TerraForest"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ready_audio()
	autosave_timer = Timer.new()
	autosave_timer.one_shot = true
	autosave_timer.wait_time = 0.65
	autosave_timer.timeout.connect(save_mapping)
	add_child(autosave_timer)
	scan_files(PACK_ROOT)
	files.sort()
	parse_slots()
	load_mapping()
	build_ui()
	populate_rows()
	if not files.is_empty(): select_file(files[0], false)
	var initial := first_visible_slot()
	if not initial.is_empty(): select_slot(initial)

func scan_files(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null: return
	for name: String in dir.get_files():
		if name.to_lower().ends_with(".wav"):
			files.append(folder.path_join(name))
	for child: String in dir.get_directories():
		scan_files(folder.path_join(child))

func parse_slots() -> void:
	var known := {}
	var path := ProjectSettings.globalize_path(MANIFEST)
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			for row: Variant in data.get("sounds", []):
				if not row is Dictionary or str(row.get("id", "")).is_empty(): continue
				var id := str(row.id)
				var event := str(row.get("event", ""))
				var label := event
				var matches: Variant = row.get("match", {})
				if matches is Dictionary:
					for key: Variant in matches:
						label += "  ·  " + str(matches[key])
				var preview := "player" if event.begins_with("movement") else ("fire" if event == "fire.burn" else "world")
				var animation := ""
				if event == "movement.footstep" and matches is Dictionary:
					animation = "Run" if str(matches.get("gait", "")) == "run" else "Walk"
				slots.append({"id": id, "label": label, "event": event, "group": "Player" if preview == "player" else "World", "preview": preview, "animation": animation})
				known[id] = true
	for event: Dictionary in EventCatalog.EVENTS:
		var id := str(event.id)
		if known.has(id): continue
		slots.append(event.duplicate(true))
		known[id] = true

func load_mapping() -> void:
	var path := ProjectSettings.globalize_path(mapping_path)
	if not FileAccess.file_exists(path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		if data.get("selection", {}) is Dictionary:
			mapping = (data.selection as Dictionary).duplicate(true)
		if data.get("notes", {}) is Dictionary:
			notes = (data.notes as Dictionary).duplicate(true)
		if data.get("deferred_sounds", []) is Array:
			for deferred_path: Variant in data.deferred_sounds:
				deferred_sounds[str(deferred_path)] = true
		if data.get("rejected_sounds", []) is Array:
			for rejected_path: Variant in data.rejected_sounds:
				rejected_sounds[str(rejected_path)] = true

func style(fill: Color, border: Color, radius: int = 8) -> StyleBoxFlat:
	var out := StyleBoxFlat.new()
	out.bg_color = fill
	out.border_color = border
	out.border_width_left = 1
	out.border_width_top = 1
	out.border_width_right = 1
	out.border_width_bottom = 1
	out.set_corner_radius_all(radius)
	out.set_content_margin_all(16)
	return out

func make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style(PANEL, LINE, 10))
	return panel

func label(text: String, size: int, color: Color, display: bool = false) -> Label:
	var out := Label.new()
	out.text = text
	out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", color)
	if display:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Bahnschrift SemiCondensed", "Bahnschrift", "Segoe UI", "Arial"])
		font.font_weight = 700
		out.add_theme_font_override("font", font)
	return out

func button(text: String, min_size: Vector2 = Vector2.ZERO) -> Button:
	var out := Button.new()
	out.text = text
	out.custom_minimum_size = min_size
	out.focus_mode = Control.FOCUS_NONE
	out.add_theme_font_size_override("font_size", 12)
	out.add_theme_color_override("font_color", INK)
	out.add_theme_color_override("font_hover_color", Color.WHITE)
	out.add_theme_stylebox_override("normal", style(Color(0.055, 0.14, 0.13), LINE, 6))
	out.add_theme_stylebox_override("hover", style(Color(0.09, 0.22, 0.20), MINT.darkened(0.2), 6))
	out.add_theme_stylebox_override("pressed", style(Color(0.12, 0.28, 0.24), MINT, 6))
	return out

func build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#071212")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 28)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	root.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 2)
	header.add_child(titles)
	titles.add_child(label("KAINO SFX AUDITION", 28, INK, true))
	titles.add_child(label("Match the pack's random filenames to actual game events. Listen, assign, save.", 12, MUTED))
	status = label("Ready", 11, MUTED)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.custom_minimum_size.x = 440
	header.add_child(status)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	root.add_child(columns)
	columns.add_child(build_files_panel())
	columns.add_child(build_slots_panel())
	root.add_child(build_actions())

func build_files_panel() -> Control:
	var panel := make_panel()
	panel.custom_minimum_size.x = 650
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var heading_row := HBoxContainer.new()
	column.add_child(heading_row)
	var heading := label("PACK SOUNDS", 14, MINT, true)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading)
	file_count = label("", 10, MUTED)
	heading_row.add_child(file_count)
	search = LineEdit.new()
	TextInputFocus.configure(search)
	search.placeholder_text = "Filter Kaino filenames…"
	search.clear_button_enabled = true
	search.text_changed.connect(func(_value: String) -> void: filter_files())
	column.add_child(search)
	var sound_tabs := HBoxContainer.new()
	sound_tabs.add_theme_constant_override("separation", 6)
	column.add_child(sound_tabs)
	sound_tab = button("SOUNDS", Vector2(110, 30))
	sound_tab.toggle_mode = true
	sound_tab.button_pressed = true
	sound_tab.pressed.connect(set_sound_view.bind(false))
	sound_tabs.add_child(sound_tab)
	sound_used_tab = button("USED (0)", Vector2(110, 30))
	sound_used_tab.toggle_mode = true
	sound_used_tab.pressed.connect(set_sound_view.bind("used"))
	sound_tabs.add_child(sound_used_tab)
	sound_later_tab = button("LATER (0)", Vector2(110, 30))
	sound_later_tab.toggle_mode = true
	sound_later_tab.pressed.connect(set_sound_view.bind(true))
	sound_tabs.add_child(sound_later_tab)
	sound_noted_tab = button("NOTED (0)", Vector2(110, 30))
	sound_noted_tab.toggle_mode = true
	sound_noted_tab.pressed.connect(set_sound_view.bind("noted"))
	sound_tabs.add_child(sound_noted_tab)
	sound_rejected_tab = button("NOT GREAT (0)", Vector2(130, 30))
	sound_rejected_tab.toggle_mode = true
	sound_rejected_tab.pressed.connect(set_sound_view.bind("rejected"))
	sound_tabs.add_child(sound_rejected_tab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "FileList"
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	column.add_child(label("NOTES · SELECTED SOUND", 11, MINT, true))
	notes_edit = TextEdit.new()
	TextInputFocus.configure(notes_edit)
	notes_edit.placeholder_text = "Describe what this sound is good for, its mood, or the event it belongs to…"
	notes_edit.custom_minimum_size.y = 96
	notes_edit.text_changed.connect(sync_note)
	# Leaving the field is what applies the "noted" filter, so typing is never
	# interrupted by the row moving out from under the caret.
	notes_edit.focus_exited.connect(apply_note_filter)
	column.add_child(notes_edit)
	column.add_child(label("Notes save with the selection; later they can guide automatic assignment.", 10, FAINT))
	return panel

func build_slots_panel() -> Control:
	var panel := make_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(label("GAME EVENT SLOTS", 14, MINT, true))
	column.add_child(label("Select an event to see its mini scene; choose a file and assign it.", 11, MUTED))
	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size.y = 252
	preview_panel.add_theme_stylebox_override("panel", style(PANEL_DEEP, LINE, 8))
	column.add_child(preview_panel)
	var preview_column := VBoxContainer.new()
	preview_column.add_theme_constant_override("separation", 4)
	preview_panel.add_child(preview_column)
	preview_container = SubViewportContainer.new()
	preview_container.custom_minimum_size.y = 220
	preview_container.stretch = true
	preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_column.add_child(preview_container)
	build_preview()
	preview_label = label("Select an event for a mini-scene preview", 10, MUTED)
	preview_column.add_child(preview_label)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	column.add_child(filters)
	event_search = LineEdit.new()
	TextInputFocus.configure(event_search)
	event_search.placeholder_text = "Filter game events or entity…"
	event_search.clear_button_enabled = true
	event_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_search.text_changed.connect(func(_value: String) -> void: filter_slots())
	filters.add_child(event_search)
	hide_occupied = CheckButton.new()
	hide_occupied.text = "Hide occupied"
	hide_occupied.button_pressed = true
	hide_occupied.tooltip_text = "Hide slots that already have an assigned sound."
	hide_occupied.toggled.connect(func(_value: bool) -> void: filter_slots())
	filters.add_child(hide_occupied)
	slot_count = label("", 10, MUTED)
	slot_count.custom_minimum_size.x = 100
	filters.add_child(slot_count)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "SlotList"
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return panel

func build_preview() -> void:
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(900, 220)
	preview_viewport.own_world_3d = true
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_viewport.transparent_bg = false
	preview_container.add_child(preview_viewport)
	preview_stage = Node3D.new()
	preview_viewport.add_child(preview_stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#071212")
	environment.environment.ambient_light_color = Color("#8bb7a4")
	environment.environment.ambient_light_energy = 0.42
	preview_stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -28, 0)
	light.light_color = Color("#ffe2b0")
	light.light_energy = 1.25
	light.shadow_enabled = true
	preview_stage.add_child(light)
	var ground := MeshInstance3D.new()
	var ground_mesh := BoxMesh.new()
	ground_mesh.size = Vector3(9, 0.12, 9)
	ground.mesh = ground_mesh
	ground.position.y = -0.08
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("#26352c")
	ground_material.roughness = 0.9
	ground.material_override = ground_material
	preview_stage.add_child(ground)
	preview_model_root = Node3D.new()
	preview_stage.add_child(preview_model_root)
	preview_camera = Camera3D.new()
	preview_camera.fov = 38
	preview_camera.current = true
	preview_stage.add_child(preview_camera)

func update_preview(id: String) -> void:
	var slot := {}
	for candidate: Dictionary in slots:
		if str(candidate.id) == id:
			slot = candidate
			break
	if slot.is_empty() or preview_model_root == null: return
	for child: Node in preview_model_root.get_children(): child.free()
	preview_model = null
	preview_animation_player = null
	preview_kind = str(slot.get("preview", "world"))
	preview_label.text = "Preview · " + str(slot.get("label", id))
	var model_path := ""
	var target := Vector3(0, 0.8, 0)
	var camera_position := Vector3(0, 1.6, 4.2)
	var desired_animation := str(slot.get("animation", "Idle"))
	if preview_kind == "vehicle":
		model_path = VEHICLE_SCENE
		camera_position = Vector3(0, 2.7, 8.0)
		target = Vector3(0, 1.0, 0)
	elif preview_kind == "zombie":
		model_path = ZOMBIE_MODEL
		camera_position = Vector3(0, 1.7, 4.5)
		target = Vector3(0, 0.9, 0)
	elif preview_kind == "player" or preview_kind == "npc":
		model_path = HUMAN_MODEL
		camera_position = Vector3(0, 1.5, 3.7)
		target = Vector3(0, 0.9, 0)
	elif preview_kind == "tool" or preview_kind == "weapon":
		model_path = TOOL_MODEL
		camera_position = Vector3(0, 0.6, 1.8)
		target = Vector3(0, 0.25, 0)
	if not model_path.is_empty():
		var packed := load(model_path) as PackedScene
		if packed != null:
			preview_model = packed.instantiate() as Node3D
			if preview_model != null:
				preview_model_root.add_child(preview_model)
				play_preview_animation(preview_model, desired_animation)
	if preview_model == null:
		make_preview_placeholder(preview_kind)
	preview_camera.position = camera_position
	preview_camera.look_at(target, Vector3.UP)

func play_preview_animation(model: Node3D, desired: String) -> void:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null: return
	preview_animation_player = player
	var names := player.get_animation_list()
	if names.is_empty(): return
	var animation := desired if desired in names else String(names[0])
	var resource := player.get_animation(animation)
	if resource != null: resource.loop_mode = Animation.LOOP_LINEAR
	player.play(animation)
	player.seek(0.15, true)

func make_preview_placeholder(kind: String) -> void:
	preview_model = Node3D.new()
	preview_model_root.add_child(preview_model)
	if kind == "world" or kind == "fire":
		var fire := MeshInstance3D.new()
		var flame := CylinderMesh.new()
		flame.top_radius = 0.05
		flame.bottom_radius = 0.42
		flame.height = 1.25
		fire.mesh = flame
		fire.position.y = 0.63
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#e88a35")
		material.emission_enabled = true
		material.emission = Color("#ff7b22")
		material.emission_energy_multiplier = 1.8
		fire.material_override = material
		preview_model.add_child(fire)
		var light := OmniLight3D.new()
		light.light_color = Color("#ff9d42")
		light.light_energy = 1.2
		light.omni_range = 4
		light.position.y = 1
		preview_model.add_child(light)
	elif kind == "ui":
		var panel := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.7, 0.9, 0.08)
		panel.mesh = box
		panel.position.y = 0.55
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#17352f")
		material.emission_enabled = true
		material.emission = Color("#1d7660")
		material.emission_energy_multiplier = 0.35
		panel.material_override = material
		preview_model.add_child(panel)
	else:
		var body := MeshInstance3D.new()
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.3
		capsule.height = 1.15
		body.mesh = capsule
		body.position.y = 0.58
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#c18b55")
		body.material_override = material
		preview_model.add_child(body)

func _process(delta: float) -> void:
	if preview_model_root != null:
		preview_model_root.rotation.y += delta * 0.45

func build_actions() -> Control:
	var panel := make_panel()
	panel.add_theme_stylebox_override("panel", style(PANEL_DEEP, LINE, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	selected_file_label = label("No file selected", 11, MUTED)
	selected_file_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(selected_file_label)
	var play := button("PLAY FILE", Vector2(90, 36))
	play.pressed.connect(play_selected)
	row.add_child(play)
	var stop := button("STOP", Vector2(62, 36))
	stop.pressed.connect(stop_audio)
	row.add_child(stop)
	play_slot_button = button("PLAY ASSIGNED", Vector2(126, 36))
	play_slot_button.pressed.connect(play_assigned)
	row.add_child(play_slot_button)
	assign_button = button("ASSIGN", Vector2(84, 36))
	assign_button.pressed.connect(assign_selected)
	row.add_child(assign_button)
	clear_button = button("CLEAR", Vector2(70, 36))
	clear_button.pressed.connect(clear_slot)
	row.add_child(clear_button)
	var save := button("SAVE SELECTION", Vector2(132, 36))
	save.pressed.connect(save_mapping)
	row.add_child(save)
	save_status = label("", 10, FAINT)
	save_status.custom_minimum_size.x = 250
	row.add_child(save_status)
	return panel

func populate_rows() -> void:
	var file_list := find_child("FileList", true, false) as VBoxContainer
	if file_list != null:
		for path: String in files:
			var row_box := HBoxContainer.new()
			row_box.add_theme_constant_override("separation", 4)
			var row := button(path.get_file(), Vector2(0, 32))
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.text = path.get_file()
			row.tooltip_text = path
			row.pressed.connect(select_file.bind(path, true))
			row_box.add_child(row)
			var defer := button("LATER", Vector2(68, 32))
			defer.tooltip_text = "Move this Kaino sound to the Later tab"
			defer.pressed.connect(toggle_sound_later.bind(path))
			row_box.add_child(defer)
			var reject := button("NOT GREAT", Vector2(92, 32))
			reject.tooltip_text = "Mark this sound as not great / won't use"
			reject.pressed.connect(toggle_sound_rejected.bind(path))
			row_box.add_child(reject)
			file_list.add_child(row_box)
			file_rows[path] = row
			file_boxes[path] = row_box
			file_later_buttons[path] = defer
			file_reject_buttons[path] = reject
			defer.text = "RESTORE" if deferred_sounds.has(path) else "LATER"
			reject.text = "RESTORE" if rejected_sounds.has(path) else "NOT GREAT"
	var slot_list := find_child("SlotList", true, false) as VBoxContainer
	if slot_list != null:
		for slot: Dictionary in slots:
			var row := button("", Vector2(0, 40))
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.tooltip_text = str(slot.id)
			row.pressed.connect(select_slot.bind(str(slot.id)))
			slot_list.add_child(row)
			slot_rows[str(slot.id)] = row
			refresh_slot(str(slot.id))
	file_count.text = "%d files" % files.size()
	if search != null: filter_files()
	if hide_occupied != null: filter_slots()

func refresh_slot(id: String) -> void:
	if not slot_rows.has(id): return
	var label_text := ""
	var group := ""
	for slot: Dictionary in slots:
		if str(slot.id) == id:
			label_text = str(slot.label)
			group = str(slot.get("group", ""))
			break
	var assigned := ""
	if mapping.has(id) and not str(mapping[id]).is_empty():
		assigned = "   [" + str(mapping[id]).get_file() + "]"
	var row: Button = slot_rows[id]
	row.text = ("[" + group + "]  " if not group.is_empty() else "") + label_text + assigned
	row.modulate = Color(0.82, 1.0, 0.88) if id == selected_slot else Color.WHITE

func filter_slots() -> void:
	if hide_occupied == null: return
	var query := event_search.text.strip_edges().to_lower() if event_search != null else ""
	var visible := 0
	for slot: Dictionary in slots:
		var id := str(slot.id)
		var row: Button = slot_rows.get(id)
		if row == null: continue
		var occupied := mapping.has(id) and not str(mapping[id]).is_empty()
		var text := str(slot.get("label", "")) + " " + str(slot.get("group", ""))
		row.visible = not (hide_occupied.button_pressed and occupied) and (query.is_empty() or query in text.to_lower() or query in id.to_lower())
		if row.visible: visible += 1
	slot_count.text = "%d / %d" % [visible, slots.size()]

func first_visible_slot() -> String:
	for slot: Dictionary in slots:
		var row: Button = slot_rows.get(str(slot.id))
		if row != null and row.visible: return str(slot.id)
	return ""

func filter_files() -> void:
	if search == null: return
	var query := search.text.strip_edges().to_lower()
	var visible := 0
	var used := used_files()
	for path: String in files:
		var row: Button = file_rows.get(path)
		if row == null: continue
		var deferred := deferred_sounds.has(path)
		var rejected := rejected_sounds.has(path)
		var noted := not str(notes.get(path, "")).strip_edges().is_empty()
		var in_view: bool
		if show_used_sounds: in_view = used.has(path)
		elif show_noted_sounds: in_view = noted
		elif show_rejected_sounds: in_view = rejected
		elif show_later_sounds: in_view = deferred and not rejected
		else: in_view = not deferred and not rejected and not noted
		var box: Control = file_boxes.get(path, row)
		box.visible = in_view and (query.is_empty() or query in path.get_file().to_lower())
		if box.visible: visible += 1
	file_count.text = "%d / %d files" % [visible, files.size()]
	if sound_later_tab != null: sound_later_tab.text = "LATER (%d)" % deferred_sounds.size()
	var noted_count := 0
	for path: String in files:
		if not str(notes.get(path, "")).strip_edges().is_empty(): noted_count += 1
	if sound_noted_tab != null: sound_noted_tab.text = "NOTED (%d)" % noted_count
	if sound_rejected_tab != null: sound_rejected_tab.text = "NOT GREAT (%d)" % rejected_sounds.size()
	if sound_used_tab != null: sound_used_tab.text = "USED (%d)" % used.size()

## Sounds already chosen for a game event: what the current selection uses.
func used_files() -> Dictionary:
	var used := {}
	for id in mapping:
		var path := str(mapping[id])
		if not path.is_empty(): used[path] = true
	return used

func first_visible_file() -> String:
	for path: String in files:
		var box: Control = file_boxes.get(path)
		if box != null and box.visible: return path
	return ""

func set_sound_view(value: Variant) -> void:
	var mode := ("later" if value else "sounds") if value is bool else str(value)
	show_used_sounds = mode == "used"
	show_later_sounds = mode == "later"
	show_noted_sounds = mode == "noted"
	show_rejected_sounds = mode == "rejected"
	if sound_tab != null: sound_tab.button_pressed = mode == "sounds"
	if sound_used_tab != null: sound_used_tab.button_pressed = mode == "used"
	if sound_later_tab != null: sound_later_tab.button_pressed = mode == "later"
	if sound_noted_tab != null: sound_noted_tab.button_pressed = mode == "noted"
	if sound_rejected_tab != null: sound_rejected_tab.button_pressed = mode == "rejected"
	filter_files()
	var current_box: Control = file_boxes.get(selected_file)
	if current_box == null or not current_box.visible:
		var next := first_visible_file()
		if not next.is_empty(): select_file(next, false)

func toggle_sound_later(path: String) -> void:
	if deferred_sounds.has(path): deferred_sounds.erase(path)
	else: deferred_sounds[path] = true
	if deferred_sounds.has(path): rejected_sounds.erase(path)
	if file_later_buttons.has(path):
		var defer: Button = file_later_buttons[path]
		defer.text = "RESTORE" if deferred_sounds.has(path) else "LATER"
	if file_reject_buttons.has(path):
		file_reject_buttons[path].text = "RESTORE" if rejected_sounds.has(path) else "NOT GREAT"
	filter_files()
	if selected_file == path and not file_boxes[path].visible:
		var next := first_visible_file()
		if not next.is_empty(): select_file(next, false)
	save_status.text = "Unsaved changes"
	status.text = ("Restored · " if not deferred_sounds.has(path) else "Moved to Later · ") + path.get_file()
	schedule_autosave()

func toggle_sound_rejected(path: String) -> void:
	if rejected_sounds.has(path): rejected_sounds.erase(path)
	else:
		rejected_sounds[path] = true
		deferred_sounds.erase(path)
	if file_reject_buttons.has(path):
		file_reject_buttons[path].text = "RESTORE" if rejected_sounds.has(path) else "NOT GREAT"
	if file_later_buttons.has(path):
		file_later_buttons[path].text = "RESTORE" if deferred_sounds.has(path) else "LATER"
	filter_files()
	if selected_file == path and not file_boxes[path].visible:
		var next := first_visible_file()
		if not next.is_empty(): select_file(next, false)
	save_status.text = "Unsaved changes"
	status.text = ("Restored · " if not rejected_sounds.has(path) else "Marked Not great · ") + path.get_file()
	schedule_autosave()

func select_file(path: String, autoplay: bool = true) -> void:
	var same := path == selected_file
	selected_file = path
	for key: String in file_rows:
		file_rows[key].modulate = Color(0.82, 1.0, 0.88) if key == path else Color.WHITE
	selected_file_label.text = "Selected file:  " + path.get_file()
	if not (same and notes_edit.has_focus()):
		loading_notes = true
		notes_edit.text = str(notes.get(path, ""))
		loading_notes = false
	if autoplay: play_file(path)

func sync_note() -> void:
	if loading_notes or selected_file.is_empty(): return
	var note := notes_edit.text.strip_edges()
	if note.is_empty(): notes.erase(selected_file)
	else: notes[selected_file] = note
	if file_rows.has(selected_file):
		file_rows[selected_file].tooltip_text = selected_file + ("\n\nNOTE: " + note if not note.is_empty() else "")
	save_status.text = "Unsaved notes"
	if notes_edit.has_focus(): return
	apply_note_filter()

## A noted sound leaves the visible tab; applied when the field is left, not
## on every keystroke, or typing would keep switching to another sound.
func apply_note_filter() -> void:
	filter_files()
	if file_boxes.has(selected_file) and not file_boxes[selected_file].visible:
		var next := first_visible_file()
		if not next.is_empty(): select_file(next, false)
	schedule_autosave()

func note_for(path: String) -> String:
	return str(notes.get(path, "")).strip_edges()

func select_slot(id: String) -> void:
	selected_slot = id
	for key: String in slot_rows: refresh_slot(key)
	var assigned := "No file assigned"
	if mapping.has(id): assigned = str(mapping[id]).get_file()
	play_slot_button.disabled = not mapping.has(id)
	status.text = "Slot selected · " + assigned
	update_preview(id)

func play_selected() -> void:
	if selected_file.is_empty():
		status.text = "Select a Kaino file first."
		return
	play_file(selected_file)

func play_file(path: String) -> void:
	var stream: AudioStream = WavDecoder.decode(path)
	if stream == null: stream = load(path)
	if stream == null:
		status.text = "Could not load: " + path.get_file()
		return
	audio_player.stream = stream
	audio_player.play()
	status.text = "Playing · " + path.get_file()
	selected_file = path

func decode_wav(path: String) -> AudioStreamWAV:
	var bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path))
	if bytes.size() < 44 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var channels := 0
	var rate := 0
	var bits := 0
	var data_offset := 0
	var data_size := 0
	var offset := 12
	while offset + 8 <= bytes.size():
		var chunk := bytes.slice(offset, offset + 4).get_string_from_ascii()
		var size := int(bytes.decode_u32(offset + 4))
		var body := offset + 8
		if size < 0 or body + size > bytes.size(): break
		if chunk == "fmt ":
			channels = int(bytes.decode_u16(body + 2))
			rate = int(bytes.decode_u32(body + 4))
			bits = int(bytes.decode_u16(body + 14))
		elif chunk == "data":
			data_offset = body
			data_size = size
			break
		offset = body + size + (size & 1)
	if channels not in [1, 2] or rate <= 0 or data_size <= 0:
		return null
	var converted := PackedByteArray()
	if bits == 16:
		converted = bytes.slice(data_offset, data_offset + data_size)
	elif bits == 24:
		var samples := int(data_size / 3)
		converted.resize(samples * 2)
		for i in samples:
			var at := data_offset + i * 3
			var value := int(bytes[at]) | (int(bytes[at + 1]) << 8) | (int(bytes[at + 2]) << 16)
			if value & 0x800000: value -= 0x1000000
			converted.encode_s16(i * 2, clampi(value >> 8, -32768, 32767))
	else:
		return null
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = channels == 2
	stream.data = converted
	return stream

func play_assigned() -> void:
	if not mapping.has(selected_slot):
		status.text = "This slot has no assigned file."
		return
	play_file(str(mapping[selected_slot]))

func stop_audio() -> void:
	audio_player.stop()
	status.text = "Stopped · " + (selected_file.get_file() if not selected_file.is_empty() else "nothing playing")

func assign_selected() -> void:
	if selected_file.is_empty() or selected_slot.is_empty():
		status.text = "Select both a file and a game slot."
		return
	mapping[selected_slot] = selected_file
	refresh_slot(selected_slot)
	play_slot_button.disabled = false
	filter_slots()
	filter_files()
	status.text = "Assigned · " + selected_file.get_file() + " → " + selected_slot
	save_status.text = "Unsaved changes"
	schedule_autosave()

func clear_slot() -> void:
	if selected_slot.is_empty(): return
	mapping.erase(selected_slot)
	refresh_slot(selected_slot)
	play_slot_button.disabled = true
	filter_slots()
	filter_files()
	save_status.text = "Unsaved changes"
	status.text = "Cleared · " + selected_slot
	schedule_autosave()

func schedule_autosave() -> void:
	if autosave_timer != null: autosave_timer.start()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if autosave_timer != null: autosave_timer.stop()
		save_mapping()
		get_tree().quit()

func save_mapping() -> void:
	var file := FileAccess.open(mapping_path, FileAccess.WRITE)
	if file == null:
		save_status.text = "Could not write " + mapping_path
		return
	file.store_string(JSON.stringify({"schema": 1, "pack": "Kaino", "selection": mapping, "notes": notes, "deferred_sounds": deferred_sounds.keys(), "rejected_sounds": rejected_sounds.keys()}, "\t"))
	file.close()
	save_status.text = "Saved · " + mapping_path.get_file()
	status.text = "Selection, notes and deferred sounds saved to " + mapping_path

func _ready_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.volume_db = -4.0
	audio_player.finished.connect(func() -> void: status.text = "Preview finished")
	add_child(audio_player)
