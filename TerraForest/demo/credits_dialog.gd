# SPDX-License-Identifier: 0BSD
extends AcceptDialog

const NOTICE_PATH := "res://assets/credits/notices.json"
const SOURCE_URL := "https://github.com/BoQsc/TerraForest"
const INK := Color("e6eee7")
const MUTED := Color("9bafad")
const ACCENT := Color("91d5b4")
var entries: Array[Dictionary] = []
var filter_field: LineEdit
var catalog: ItemList
var document: RichTextLabel

func _ready() -> void:
	theme = theme.duplicate() if theme != null else Theme.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("14292e")
	frame.border_color = Color("577d6c")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(8)
	frame.content_margin_left = 16
	frame.content_margin_right = 16
	frame.content_margin_top = 36
	frame.content_margin_bottom = 12
	theme.set_stylebox("embedded_border", "Window", frame)
	theme.set_stylebox("embedded_unfocused_border", "Window", frame)
	theme.set_color("title_color", "Window", INK)
	var body := frame.duplicate()
	body.content_margin_top = 16
	theme.set_stylebox("panel", "AcceptDialog", body)
	title = "TerraForest · Credits & licenses"
	min_size = Vector2i(760, 440)
	exclusive = true
	get_ok_button().text = "Back"
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 16)
	add_child(panel)
	var intro := Label.new()
	intro.text = "An open-source world-building project for Godot."
	intro.add_theme_color_override("font_color", ACCENT)
	panel.add_child(intro)
	filter_field = LineEdit.new()
	filter_field.placeholder_text = "Find a component or license"
	filter_field.custom_minimum_size.y = 42
	filter_field.text_changed.connect(_filter)
	panel.add_child(filter_field)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(columns)
	catalog = ItemList.new()
	catalog.custom_minimum_size = Vector2(280, 260)
	catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalog.item_selected.connect(_select)
	columns.add_child(catalog)
	document = RichTextLabel.new()
	document.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	document.size_flags_vertical = Control.SIZE_EXPAND_FILL
	document.custom_minimum_size.x = 350
	document.selection_enabled = true
	document.bbcode_enabled = false
	document.add_theme_font_size_override("normal_font_size", 17)
	document.add_theme_color_override("default_color", INK)
	columns.add_child(document)
	var source := LinkButton.new()
	source.text = "Project source on GitHub"
	source.tooltip_text = SOURCE_URL
	source.pressed.connect(func(): OS.shell_open(SOURCE_URL))
	panel.add_child(source)
	_load_entries()
	_filter("")

func open() -> void:
	popup_centered_clamped(Vector2i(1120, 740), 0.9)
	filter_field.grab_focus()

func _load_entries() -> void:
	entries.append({"id": "about", "title": "About TerraForest", "license": "Source & reuse", "summary": "", "text":
		"TerraForest combines editable volumetric terrain, streamed vegetation and modular world systems. The project source is available on GitHub and in the source download.\n\n"
		+ "PROJECT CODE\nTerraForest project code uses Zero-Clause BSD (0BSD). You can use, copy, modify and distribute it, including commercially, under the included terms. Separately identified components retain their own licenses.\n\n"
		+ "ASSETS\nSome supplied assets carry CC0 public-domain dedications. Original woodland samples and the supplied vehicle have their own 0BSD notices. Each entry describes its scope and preserves its source notice. Inherited terrain textures retain their source provenance; no new license is granted for those textures here.\n\n"
		+ "ENGINE & DEPENDENCIES\nGodot, its logo and third-party libraries have separate notices. Engine credits and license texts below come from this running build of Godot.\n\n"
		+ "Choose a component on the left to read its notice. All notices are readable offline; the source link opens the project repository."})
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(NOTICE_PATH))
	if data is Dictionary and data.get("schema") == 1 and data.get("notices") is Array:
		for entry: Dictionary in data.notices:
			entries.append(entry)
	else:
		push_error("Offline credit notices are missing or invalid: " + NOTICE_PATH)
		entries.append({"id": "missing", "title": "Project notices unavailable", "license": "", "summary": "", "text": "The offline project notices could not be loaded. Consult the notices in the source download."})
	entries.append({"id": "godot", "title": "Godot Engine", "license": "MIT", "summary": "The running Godot engine retains the following license.", "text": Engine.get_license_text()})
	var licenses := Engine.get_license_info()
	var tokens := RegEx.new()
	tokens.compile("[A-Za-z0-9.+-]+")
	for component: Dictionary in Engine.get_copyright_info():
		if str(component.name) == "Godot Engine": continue
		var body := ""
		var referenced: Array[String] = []
		for part: Dictionary in component.parts:
			body += "\n".join(PackedStringArray(part.copyright)) + "\nLicense: " + str(part.license) + "\n"
			body += "Files: " + ", ".join(PackedStringArray(part.files)) + "\n\n"
			for token: RegExMatch in tokens.search_all(str(part.license)):
				var key := token.get_string()
				if licenses.has(key) and not key in referenced: referenced.append(key)
		for key: String in referenced:
			body += key + "\n" + str(licenses[key]) + "\n\n"
		entries.append({"id": "engine_component_" + str(component.name), "title": "Godot · " + str(component.name), "license": "Engine component", "summary": "Credits and terms supplied by the running Godot engine.", "text": body.strip_edges()})
	for key: String in licenses:
		entries.append({"id": "engine_license_" + key, "title": "Engine license · " + key, "license": key, "summary": "License text supplied by the running Godot engine.", "text": str(licenses[key])})

func _filter(query: String) -> void:
	var previous := ""
	if not catalog.get_selected_items().is_empty():
		previous = str(entries[int(catalog.get_item_metadata(catalog.get_selected_items()[0]))].id)
	catalog.clear()
	var selected := 0
	for index in entries.size():
		var entry := entries[index]
		var searchable := str(entry.title) + " " + str(entry.license) + " " + str(entry.summary) + " " + str(entry.text)
		if not query.is_empty() and not searchable.to_lower().contains(query.to_lower()): continue
		catalog.add_item(str(entry.title))
		var row := catalog.item_count - 1
		catalog.set_item_metadata(row, index)
		catalog.set_item_tooltip(row, str(entry.title) + " · " + str(entry.license))
		if str(entry.id) == previous: selected = row
	if catalog.item_count > 0:
		catalog.select(selected)
		_select(selected)
	else:
		document.clear()
		document.add_text("No matching notices. Try a component name or a license such as MIT, CC0 or 0BSD.")

func _select(row: int) -> void:
	var entry := entries[int(catalog.get_item_metadata(row))]
	document.clear()
	document.push_font_size(26)
	document.push_color(ACCENT)
	document.add_text(str(entry.title) + "\n")
	document.pop()
	document.pop()
	document.push_color(MUTED)
	document.add_text(str(entry.license) + "\n\n")
	document.pop()
	if not str(entry.summary).is_empty(): document.add_text(str(entry.summary) + "\n\n")
	document.add_text(str(entry.text))
	document.scroll_to_line(0)
