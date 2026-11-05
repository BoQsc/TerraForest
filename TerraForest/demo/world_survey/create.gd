# SPDX-License-Identifier: 0BSD
extends Control
## Create world + generation, re-specified from world_creation_panel.gd and the
## generation stages in progress_meter.gd: the live regional survey, the real
## recipe/landscape/settlement controls, and the embedded generation panel.
## Sample values only; no generation is started.

const KIT := preload("res://demo/world_survey/kit.gd")

## Captured with the game's own planner (tools/capture_survey_map.gd):
## world_generation_plan.preview(seed 2, generator 29, frontier recipe).
const SURVEY_MAP := "res://demo/world_survey/assets/survey_map.png"

const RECIPES := [
	"Forest frontier",
	"Connected countryside",
	"Market towns",
	"City region · experimental",
	"Regional belt · experimental",
	"Frontier expedition",
]

const STAGE := "Placing buildings and interiors"
const STAGE_COMPLETED := 1240
const STAGE_TOTAL := 3600
const PERCENT := 52
const ELAPSED := "0:41"
const REMAINING := "0:38"
const WORK := "streets 18 / 24   ·   sites 3 / 7   ·   photographs 0 / 3"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	KIT.backdrop(self)
	build_header()
	build_survey()
	build_form()
	build_generation()


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
	KIT.text_at(self, "My worlds", 14, KIT.MUTED, KIT.body_font(), 64, 122)
	KIT.text_at(self, "Create world", 14, KIT.ACCENT, KIT.body_font(), 208, 122)
	var underline := ColorRect.new()
	underline.color = KIT.ACCENT
	underline.position = Vector2(208, 146)
	underline.size = Vector2(96, 2)
	underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(underline)
	KIT.rule(self, 64, 152, 1792)
	KIT.text_at(self, "Create your world", 30, KIT.INK, KIT.display_font(), 64, 168)
	KIT.text_at(self, "Choose a character for your world, then refine the landscape and its connections.", 14, KIT.MUTED, KIT.body_font(), 64, 210)
	KIT.right_text_at(self, "01  CONFIGURE    /    02  SURVEY    /    03  PLAY", 12, KIT.ACCENT, KIT.body_font(), 1856, 176, 700)


func build_survey() -> void:
	var frame := KIT.panel(self, 64, 248, 920, 648, KIT.PANEL, KIT.BORDER, 8)
	KIT.text_at(self, KIT.spaced("LIVE REGIONAL SURVEY"), 12, KIT.ACCENT, KIT.body_font(), 84, 266)
	KIT.right_text_at(self, "2 × 2 km", 12, KIT.MUTED, KIT.mono_font(), 964, 266, 160)
	# The game's own 256 x 256 plan render (world_generation_plan.preview) for
	# seed 2 and the frontier recipe: settlements, roads, trails, lakes, rock.
	var map := KIT.photo_frame(self, 84, 300, 452, 452, SURVEY_MAP, 0.0)
	if map != null:
		map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR

	var legend := [
		["Woodland", Color("#4c6940")],
		["Asphalt", Color("#626669")],
		["Dirt trails", Color("#95856c")],
		["Water", Color("#76b8d0")],
		["Roofs / rock", Color("#99938a")],
	]
	KIT.text_at(self, KIT.spaced("LEGEND"), 9, KIT.DIM, KIT.body_font(), 566, 302)
	for i in legend.size():
		var swatch := ColorRect.new()
		swatch.color = legend[i][1]
		swatch.position = Vector2(566, 330 + i * 30)
		swatch.size = Vector2(12, 12)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(swatch)
		KIT.text_at(self, str(legend[i][0]), 13, KIT.MUTED, KIT.body_font(), 590, 326 + i * 30)
	KIT.rule(self, 566, 500, 396)
	KIT.text_at(self, KIT.spaced("PLAN"), 9, KIT.DIM, KIT.body_font(), 566, 514)
	KIT.text_at(self, "15 buildings", 16, KIT.INK, KIT.body_font(), 566, 536)
	KIT.text_at(self, "1.23 km regional roads  ·  1.12 km trails", 13, KIT.MUTED, KIT.body_font(), 566, 564)
	KIT.text_at(self, "2 settlements / 2 districts  ·  4 trails", 13, KIT.MUTED, KIT.body_font(), 566, 588)
	KIT.text_at(self, "Placement plan cached for generation.", 12, KIT.DIM, KIT.body_font(), 566, 616)
	KIT.rule(self, 566, 646, 396)
	KIT.text_at(self, "READY TO PLAN", 12, KIT.ACCENT, KIT.body_font(), 566, 662)
	KIT.text_at(self, "Native terrain fitting  ·  Cached generation", 12, KIT.MUTED, KIT.body_font(), 566, 684)
	KIT.text_at(self, "World plan · north is up · 2 km × 2 km", 12, KIT.MUTED, KIT.body_font(), 84, 766)
	var status := KIT.label("The preview uses the actual placement plan, not a decorative map. Existing worlds are never changed.", 13, KIT.MUTED, KIT.body_font())
	status.position = Vector2(84, 792)
	status.size = Vector2(452, 60)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)


func build_form() -> void:
	var recipe := KIT.panel(self, 1016, 248, 840, 116, Color("#203637"), Color("#496356"), 8)
	KIT.text_at(self, KIT.spaced("STARTING RECIPE"), 10, KIT.ACCENT, KIT.body_font(), 1034, 262)
	field(1034, 282, 400, 38, "Frontier expedition", true)
	var copy := KIT.label("Six connected districts, a trader introduction and coal-mine expedition. Includes wilderness locations, sleepers, supplies, lakes and material veins.", 12, KIT.MUTED, KIT.body_font())
	copy.position = Vector2(1034, 328)
	copy.size = Vector2(804, 30)
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(copy)

	KIT.text_at(self, "Name & seed", 20, KIT.INK, KIT.display_font(), 1016, 380)
	field(1016, 412, 520, 40, "Mossy_Hollow", false, false)
	field(1548, 412, 168, 40, "Seed 2", false, false)
	button(1724, 412, 132, 40, "SHUFFLE", false)

	KIT.text_at(self, "Landscape & biomes", 20, KIT.INK, KIT.display_font(), 1016, 468)
	KIT.text_at(self, "Temperate vegetation", 13, KIT.MUTED, KIT.body_font(), 1016, 508)
	field(1176, 500, 680, 34, "Forest & meadow mosaic", true)
	checkbox(1016, 548, "Ocean coastline & beaches", true)
	checkbox(1016, 578, "Material veins & surface stones", true)
	checkbox(1016, 608, "Trader introduction & coal-mine expedition", true)

	var grid_panel := KIT.panel(self, 1016, 642, 840, 92, Color("#1b2b30"), KIT.BORDER, 8)
	KIT.text_at(self, "Building-grid fit", 16, KIT.ACCENT, KIT.display_font(), 1034, 654)
	KIT.text_at(self, "Generation preferences · new worlds only", 12, KIT.MUTED, KIT.body_font(), 1034, 678)
	checkbox(1034, 702, "Terrain", true)
	checkbox(1210, 702, "Roads & shoulders", true)

	KIT.text_at(self, "Places & connections", 20, KIT.INK, KIT.display_font(), 1016, 748)
	option(1016, 796, 404, "Settlements", "2 · linked communities")
	option(1446, 796, 410, "Settlement scale", "Town · 2 districts each")
	option(1016, 856, 404, "Regional roads", "Interconnected network")
	option(1446, 856, 410, "Unpaved offroads", "Up to 2 per district")


func build_generation() -> void:
	var panel := KIT.panel(self, 64, 908, 1792, 108, Color(0.05, 0.12, 0.13, 0.96), Color(KIT.ACCENT.r, KIT.ACCENT.g, KIT.ACCENT.b, 0.5), 8)
	KIT.text_at(self, "Generating Mossy_Hollow", 18, KIT.INK, KIT.display_font(), 84, 928)
	KIT.text_at(self, "%s  ·  %d / %d" % [STAGE, STAGE_COMPLETED, STAGE_TOTAL], 14, KIT.MUTED, KIT.body_font(), 84, 958)
	KIT.right_text_at(self, "%d%%" % PERCENT, 30, KIT.ACCENT, KIT.display_font(), 1608, 924, 220)
	KIT.right_text_at(self, "elapsed %s  ·  remaining ≈ %s" % [ELAPSED, REMAINING], 12, KIT.DIM, KIT.mono_font(), 1836, 960, 460)
	var meter := KIT.Meter.new()
	meter.accent = KIT.ACCENT
	meter.value = float(PERCENT) / 100.0
	meter.position = Vector2(84, 986)
	meter.size = Vector2(1600, 8)
	add_child(meter)
	KIT.text_at(self, WORK, 11, KIT.DIM, KIT.mono_font(), 84, 1000)
	button(1700, 952, 136, 34, "CANCEL", false)


func field(x: float, y: float, width: float, height: float, caption: String, muted: bool, chevron: bool = true) -> void:
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


func option(x: float, y: float, width: float, caption: String, value: String) -> void:
	KIT.text_at(self, caption, 11, KIT.MUTED, KIT.body_font(), x, y - 20)
	field(x, y, width, 36, value, true)


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


func set_mock_time(_seconds: float) -> void:
	pass
