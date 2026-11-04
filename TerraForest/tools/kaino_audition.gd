# SPDX-License-Identifier: 0BSD
extends Control
## Standalone Kaino SFX audition tool. It reads the pack and the bundled game
## sound definitions, previews WAVs, and saves slot-to-file selections.

const PACK_ROOT := "res://addons/audio_runtime/packs/Kaino"
const MANIFEST := "res://addons/audio_runtime/packs/nox/pack.audio.module.json"
const TextInputFocus := preload("res://addons/player_runtime/text_input_focus.gd")
const WavDecoder := preload("res://addons/audio_runtime/wav_decoder.gd")
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
var file_rows: Dictionary = {}
var slot_rows: Dictionary = {}
var selected_file := ""
var selected_slot := ""
var audio_player: AudioStreamPlayer
var search: LineEdit
var file_count: Label
var selected_file_label: Label
var selected_slot_label: Label
var status: Label
var save_status: Label
var play_slot_button: Button
var assign_button: Button
var clear_button: Button

func _ready() -> void:
	get_window().title = "Kaino SFX Audition — TerraForest"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ready_audio()
	scan_files(PACK_ROOT)
	files.sort()
	parse_slots()
	load_mapping()
	build_ui()
	populate_rows()
	if not files.is_empty(): select_file(files[0], false)
	if not slots.is_empty(): select_slot(str(slots[0].id))

func scan_files(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null: return
	for name: String in dir.get_files():
		if name.to_lower().ends_with(".wav"):
			files.append(folder.path_join(name))
	for child: String in dir.get_directories():
		scan_files(folder.path_join(child))

func parse_slots() -> void:
	var path := ProjectSettings.globalize_path(MANIFEST)
	if not FileAccess.file_exists(path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: return
	for row: Variant in data.get("sounds", []):
		if not row is Dictionary or str(row.get("id", "")).is_empty(): continue
		var label := str(row.get("event", row.id))
		var matches: Variant = row.get("match", {})
		if matches is Dictionary:
			for key: Variant in matches:
				label += "  ·  " + str(matches[key])
		slots.append({"id": str(row.id), "label": label, "event": str(row.get("event", ""))})

func load_mapping() -> void:
	var path := ProjectSettings.globalize_path(mapping_path)
	if not FileAccess.file_exists(path): return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("selection", {}) is Dictionary:
		mapping = (data.selection as Dictionary).duplicate(true)

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
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "FileList"
	list.add_theme_constant_override("separation", 3)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return panel

func build_slots_panel() -> Control:
	var panel := make_panel()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(label("GAME EVENT SLOTS", 14, MINT, true))
	column.add_child(label("Select a slot on the right, then choose a file and assign it.", 11, MUTED))
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
			var row := button(path.get_file(), Vector2(0, 32))
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.text = path.get_file()
			row.tooltip_text = path
			row.pressed.connect(select_file.bind(path, true))
			file_list.add_child(row)
			file_rows[path] = row
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

func refresh_slot(id: String) -> void:
	if not slot_rows.has(id): return
	var label_text := ""
	for slot: Dictionary in slots:
		if str(slot.id) == id:
			label_text = str(slot.label)
			break
	var assigned := ""
	if mapping.has(id) and not str(mapping[id]).is_empty():
		assigned = "   [" + str(mapping[id]).get_file() + "]"
	var row: Button = slot_rows[id]
	row.text = label_text + assigned
	row.modulate = Color(0.82, 1.0, 0.88) if id == selected_slot else Color.WHITE

func filter_files() -> void:
	if search == null: return
	var query := search.text.strip_edges().to_lower()
	var visible := 0
	for path: String in files:
		var row: Button = file_rows.get(path)
		if row == null: continue
		row.visible = query.is_empty() or query in path.get_file().to_lower()
		if row.visible: visible += 1
	file_count.text = "%d / %d files" % [visible, files.size()]

func select_file(path: String, autoplay: bool = true) -> void:
	selected_file = path
	for key: String in file_rows:
		file_rows[key].modulate = Color(0.82, 1.0, 0.88) if key == path else Color.WHITE
	selected_file_label.text = "Selected file:  " + path.get_file()
	if autoplay: play_file(path)

func select_slot(id: String) -> void:
	selected_slot = id
	for key: String in slot_rows: refresh_slot(key)
	var assigned := "No file assigned"
	if mapping.has(id): assigned = str(mapping[id]).get_file()
	selected_slot_label = null
	play_slot_button.disabled = not mapping.has(id)
	status.text = "Slot selected · " + assigned

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
	status.text = "Assigned · " + selected_file.get_file() + " → " + selected_slot
	save_status.text = "Unsaved changes"

func clear_slot() -> void:
	if selected_slot.is_empty(): return
	mapping.erase(selected_slot)
	refresh_slot(selected_slot)
	play_slot_button.disabled = true
	save_status.text = "Unsaved changes"
	status.text = "Cleared · " + selected_slot

func save_mapping() -> void:
	var file := FileAccess.open(mapping_path, FileAccess.WRITE)
	if file == null:
		save_status.text = "Could not write " + mapping_path
		return
	file.store_string(JSON.stringify({"schema": 1, "pack": "Kaino", "selection": mapping}, "\t"))
	file.close()
	save_status.text = "Saved · " + mapping_path.get_file()
	status.text = "Selection saved to " + mapping_path

func _ready_audio() -> void:
	audio_player = AudioStreamPlayer.new()
	audio_player.volume_db = -4.0
	audio_player.finished.connect(func() -> void: status.text = "Preview finished")
	add_child(audio_player)
