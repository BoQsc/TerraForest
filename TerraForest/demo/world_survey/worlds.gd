# SPDX-License-Identifier: 0BSD
extends Control
## My worlds, derived from the shipped browser: the real saved slots in
## user://worlds, their presentation.json metadata, the generator -> landscape
## names from worlds.gd, the file modification time as "Last saved", and each
## world's own .preview photographs. Nothing here writes to a save.

const KIT := preload("res://demo/world_survey/kit.gd")

const DIR := "user://worlds"
const SLOTS := ["Amber_Bay", "Bright_Forest", "Calm_Haven"]
const FALLBACK_PHOTO := "res://reports/entry_fly_in/browser/01_aerial.png"
const VIEWS := ["north", "road", "market"]

## worlds.gd: generator identity -> landscape name.
const LANDSCAPES := {
	17: "Regional inland", 18: "Regional inland", 19: "Regional coast",
	20: "Build-friendly inland", 21: "Build-friendly coast",
	22: "Grid-preferred inland", 23: "Grid-preferred coast",
	28: "Varied lakes / build-friendly inland", 29: "Varied lakes / build-friendly coast",
	30: "Varied lakes / natural inland", 31: "Varied lakes / natural coast",
	13: "Earlier regional recipe",
}
const BIOMES := ["Woodland", "Woodland & meadow mosaic", "Open grassland with groves"]

const ROW_X := 64.0
const ROW_W := 876.0
const ROW_Y := 272.0
const ROW_H := 104.0
const ROW_GAP := 10.0

var entries: Array[Dictionary] = []
var selected := 0
var row_panels: Array[Dictionary] = []
var detail_labels: Array[Dictionary] = []
var hero_title: Label
var hero_meta: Label
var hero_photo: TextureRect
var hero_caption: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_entries()
	KIT.backdrop(self)
	build_header()
	build_list()
	build_detail()
	build_bottom()
	select(0)


func load_entries() -> void:
	for slot: String in SLOTS:
		var state := read_json(DIR.path_join(slot + ".presentation.json"))
		var generation := read_json(DIR.path_join(slot + ".generation.json"))
		var seed := int(generation.get("seed", state.get("seed", 0)))
		var generator := int(state.get("generator", 0))
		var options: Dictionary = state.get("world_options", {})
		var photo := DIR.path_join(slot + ".preview/north.png")
		if not FileAccess.file_exists(photo):
			photo = FALLBACK_PHOTO
		var settlements := int(options.get("settlements", 0))
		var districts := settlements * int(options.get("districts", 0))
		var biome := int(options.get("biome", -1))
		entries.append({
			"slot": slot,
			"seed": seed,
			"landscape": str(LANDSCAPES.get(generator, "Saved recipe %d" % generator)),
			"layout": str(state.get("settlement_layout", "")).capitalize() if state.has("settlement_layout") else "Not recorded",
			"created": format_time(int(state.get("created", 0))),
			"played": format_time(int(state.get("last_played", 0))),
			"saved": format_time(FileAccess.get_modified_time(DIR.path_join(slot + ".trw"))),
			"settlements": settlements,
			"districts": districts,
			"biome": BIOMES[biome] if biome >= 0 and biome < BIOMES.size() else "Not recorded",
			"road_grid": "On" if int(options.get("road_grid", 0)) > 0 else "Off",
			"photo": photo,
		})


func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func format_time(unix: int) -> String:
	if unix <= 0:
		return "Not recorded"
	return Time.get_datetime_string_from_unix_time(unix, true) + " UTC"


func build_header() -> void:
	var brand := HBoxContainer.new()
	brand.position = Vector2(64, 34)
	brand.add_theme_constant_override("separation", 0)
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(brand)
	brand.add_child(KIT.label("Terra", 26, KIT.WARM, KIT.font(["Georgia", "DejaVu Serif"], 700)))
	brand.add_child(KIT.label("Forest", 26, Color("#98ddbc"), KIT.font(["Georgia", "DejaVu Serif"], 700)))
	KIT.text_at(self, "An open-source world-building project", 13, KIT.MUTED, KIT.body_font(), 64, 70)
	KIT.right_text_at(self, KIT.spaced("WORLDS / YOUR NEXT CHAPTER"), 11, KIT.MUTED, KIT.body_font(), 1856, 44, 600)
	KIT.rule(self, 64, 104, 1792)
	KIT.text_at(self, "My worlds", 14, KIT.ACCENT, KIT.body_font(), 64, 122)
	KIT.text_at(self, "Create world", 14, KIT.MUTED, KIT.body_font(), 208, 122)
	var underline := ColorRect.new()
	underline.color = KIT.ACCENT
	underline.position = Vector2(64, 146)
	underline.size = Vector2(82, 2)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(underline)
	KIT.rule(self, 64, 152, 1792)


func build_list() -> void:
	KIT.text_at(self, "Saved worlds", 24, KIT.INK, KIT.display_font(), 64, 174)
	field(64, 214, 300, 38, "Last played · newest first", false, true)
	field(380, 214, 560, 38, "Filter saved worlds", true, false)
	for i in entries.size():
		build_row(i)
	KIT.text_at(self, "Refresh saved worlds", 12, KIT.ACCENT, KIT.body_font(), 64, 636)
	KIT.text_at(self, "Create / refresh photographs", 12, KIT.ACCENT, KIT.body_font(), 246, 636)
	KIT.text_at(self, "Recover interrupted publication", 12, KIT.MUTED, KIT.body_font(), 468, 636)
	KIT.text_at(self, "%d saved worlds. Save from the Actions menu or with F5 while playing." % entries.size(), 13, KIT.MUTED, KIT.body_font(), 64, 682)
	button(64, 720, 260, 48, "CREATE A WORLD", true)
	var note := KIT.label("Opening hands the world to the game; this browser never writes a save. Photographs are read from each world's .preview folder and refreshed by the game.", 12, KIT.DIM, KIT.body_font())
	note.position = Vector2(64, 790)
	note.size = Vector2(820, 40)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)


func build_row(index: int) -> void:
	var entry: Dictionary = entries[index]
	var y := ROW_Y + float(index) * (ROW_H + ROW_GAP)
	var row := KIT.surface(self, ROW_X, y, ROW_W, ROW_H, KIT.PANEL, Color(1, 1, 1, 0.05), 8)
	var picture := TextureRect.new()
	picture.texture = KIT.photo(photo_for(index))
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.clip_contents = true
	picture.position = Vector2(12, 11)
	picture.size = Vector2(136, 82)
	row.add_child(picture)
	var grid := KIT.SurveyGrid.new()
	grid.position = Vector2(12, 11)
	grid.size = Vector2(136, 82)
	grid.spacing = 24.0
	row.add_child(grid)
	var name_label := KIT.label(str(entry.slot), 20, KIT.INK, KIT.display_font())
	name_label.position = Vector2(164, 12)
	row.add_child(name_label)
	var facts := KIT.label("Seed %d  ·  %s  ·  %s" % [int(entry.seed), str(entry.landscape), district_line(entry)], 13, KIT.MUTED, KIT.body_font())
	facts.position = Vector2(164, 42)
	row.add_child(facts)
	var played := KIT.label("Last played %s  ·  %s" % [str(entry.played), str(entry.biome)], 12, KIT.DIM, KIT.body_font())
	played.position = Vector2(164, 64)
	row.add_child(played)
	var tag := KIT.label(KIT.spaced("OPEN"), 10, KIT.DIM, KIT.body_font())
	tag.position = Vector2(ROW_W - 100, 44)
	row.add_child(tag)
	var bar := ColorRect.new()
	bar.color = KIT.ACCENT
	bar.position = Vector2(1, 14)
	bar.size = Vector2(2, ROW_H - 28)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	row_panels.append({"panel": row, "skin": row.get_theme_stylebox("panel"), "name": name_label, "tag": tag, "bar": bar})


func photo_for(index: int) -> String:
	var entry: Dictionary = entries[index]
	var view: String = VIEWS[index % VIEWS.size()]
	var path := DIR.path_join(str(entry.slot) + ".preview/" + view + ".png")
	return path if FileAccess.file_exists(path) else str(entry.photo)


func hero_photo_for(slot: String) -> Dictionary:
	for view in ["road", "north", "market"]:
		var path := DIR.path_join(slot + ".preview/" + view + ".png")
		if FileAccess.file_exists(path):
			return {"path": path, "view": view}
	return {"path": FALLBACK_PHOTO, "view": "reference"}


func district_line(entry: Dictionary) -> String:
	if int(entry.settlements) <= 0:
		return "settlement recipe not recorded"
	return "%d settlements · %d districts" % [int(entry.settlements), int(entry.districts)]


func build_detail() -> void:
	var first := hero_photo_for(str(entries[0].slot))
	hero_photo = KIT.photo_frame(self, 1000, 176, 856, 420, str(first.path), 0.3)
	var grid := KIT.SurveyGrid.new()
	grid.position = Vector2(0, 0)
	grid.size = Vector2(856, 420)
	grid.spacing = 56.0
	hero_photo.add_child(grid)
	KIT.right_text_at(self, "N ↑", 14, Color(0.9, 0.95, 0.92, 0.85), KIT.mono_font(), 1796, 192, 70)
	KIT.right_text_at(self, "2 × 2 km", 12, Color(0.9, 0.95, 0.92, 0.8), KIT.mono_font(), 1796, 560, 180)
	hero_caption = KIT.text_at(self, KIT.spaced("PHOTOGRAPH · " + str(first.view).to_upper()), 10, Color(0.9, 0.95, 0.92, 0.75), KIT.body_font(), 1016, 190)
	hero_title = KIT.text_at(self, "", 34, KIT.INK, KIT.display_font(), 1000, 616)
	hero_meta = KIT.text_at(self, "", 13, KIT.MUTED, KIT.body_font(), 1000, 660)
	var fields := [
		["CREATED", "created"], ["LAST PLAYED", "played"], ["LAST SAVED", "saved"], ["SEED", "seed"],
		["LANDSCAPE", "landscape"], ["LAYOUT", "layout"], ["SETTLEMENTS", "settlements"], ["ROAD GRID", "road_grid"],
	]
	for i in fields.size():
		var x := 1000.0 + 432.0 * float(i % 2)
		var y := 700.0 + 52.0 * float(i / 2)
		KIT.text_at(self, KIT.spaced(str(fields[i][0])), 9, KIT.DIM, KIT.body_font(), x, y)
		var value := KIT.text_at(self, "", 15, KIT.INK, KIT.mono_font() if str(fields[i][1]) == "seed" else KIT.body_font(), x, y + 18)
		detail_labels.append({"key": str(fields[i][1]), "label": value})
	button(1000, 924, 260, 48, "OPEN SELECTED WORLD", true)
	button(1276, 924, 210, 48, "CREDITS & LICENSES", false)
	KIT.right_text_at(self, KIT.spaced("QUIT"), 11, KIT.DIM, KIT.body_font(), 1856, 940, 160)


func build_bottom() -> void:
	checkbox(64, 1006, "Gameplay material costs (uncheck for free editor)", true)
	KIT.text_at(self, "Opening uses this world's saved generation settings.", 12, KIT.DIM, KIT.body_font(), 560, 1008)



func select(index: int) -> void:
	selected = clampi(index, 0, entries.size() - 1)
	for i in row_panels.size():
		var row: Dictionary = row_panels[i]
		var skin: StyleBoxFlat = row.skin
		var is_selected := i == selected
		skin.bg_color = Color(0.13, 0.23, 0.23, 0.95) if is_selected else KIT.PANEL
		skin.border_color = Color(KIT.ACCENT.r, KIT.ACCENT.g, KIT.ACCENT.b, 0.55) if is_selected else Color(1, 1, 1, 0.05)
		var bar: ColorRect = row.bar
		bar.visible = is_selected
		var tag: Label = row.tag
		tag.add_theme_color_override("font_color", KIT.ACCENT if is_selected else KIT.DIM)
	var entry: Dictionary = entries[selected]
	hero_title.text = str(entry.slot)
	hero_meta.text = "Seed %d  ·  %s  ·  %s layout" % [int(entry.seed), str(entry.landscape), str(entry.layout).to_lower()]
	if hero_photo != null:
		var view := hero_photo_for(str(entry.slot))
		hero_photo.texture = KIT.photo(str(view.path))
		hero_caption.text = KIT.spaced("PHOTOGRAPH · " + str(view.view).to_upper())
	for item in detail_labels:
		var key := str(item.key)
		var value: Label = item.label
		match key:
			"created":
				value.text = str(entry.created)
			"played":
				value.text = str(entry.played)
			"saved":
				value.text = str(entry.saved)
			"seed":
				value.text = str(entry.seed)
			"landscape":
				value.text = str(entry.landscape)
			"layout":
				value.text = str(entry.layout)
			"settlements":
				var biome := str(entry.biome)
				value.text = district_line(entry) if biome == "Not recorded" else district_line(entry) + " · " + biome
			"road_grid":
				value.text = str(entry.road_grid)


func set_mock_time(_seconds: float) -> void:
	pass


func field(x: float, y: float, width: float, height: float, caption: String, muted: bool, chevron: bool) -> void:
	var box := KIT.panel(self, x, y, width, height, KIT.PANEL_HI, KIT.BORDER, 6)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	box.add_child(margin)
	var row := HBoxContainer.new()
	margin.add_child(row)
	var text_node := KIT.label(caption, 14, KIT.MUTED if muted else KIT.INK, KIT.body_font())
	text_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(text_node)
	if chevron:
		var arrow := KIT.label("▾", 12, KIT.MUTED, KIT.body_font())
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(arrow)


func button(x: float, y: float, width: float, height: float, caption: String, filled: bool) -> void:
	var box := KIT.panel(self, x, y, width, height, KIT.ACCENT if filled else KIT.PANEL_HI, Color(0, 0, 0, 0) if filled else KIT.BORDER, 6)
	var text_node := KIT.label(KIT.spaced(caption), 11, Color("#08171a") if filled else KIT.INK, KIT.body_font())
	text_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(text_node)


func checkbox(x: float, y: float, caption: String, on: bool) -> void:
	var box := KIT.surface(self, x, y, 18, 18, KIT.PANEL_HI, KIT.BORDER, 3)
	if on:
		var inner := ColorRect.new()
		inner.color = KIT.ACCENT
		inner.position = Vector2(4, 4)
		inner.size = Vector2(10, 10)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(inner)
	KIT.text_at(self, caption, 14, KIT.INK, KIT.body_font(), x + 28, y - 2)
