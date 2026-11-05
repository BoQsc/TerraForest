# SPDX-License-Identifier: 0BSD
extends Control
## World generation screen mockup: the seeded planet is being shaped while the
## stage rail reports progress. Presentation only - sample data and mock timing.

const KIT := preload("res://demo/world_screens/kit.gd")
const Planet := preload("res://demo/world_screens/planet.gd")

const RAIL_LEFT := 1030.0
const RAIL_WIDTH := 806.0
const STEP_TOP := 512.0
const STEP_HEIGHT := 44.0
const MOCK_SECONDS := 42.0
const WORLD_NAME := "ALDERGROVE HOLLOW"
const SEED_TEXT := "8 841 229"

const STEPS := [
	{"title": "World recipe", "detail": "seed 8 841 229 · integrated preset", "work": "RECIPE LOCKED", "at": 0.03},
	{"title": "Carving terrain", "detail": "heightfield · 4 096 chunks", "work": "4 096 / 4 096 CHUNKS", "at": 0.20},
	{"title": "Painting biomes", "detail": "grassland · old growth · wetland", "work": "18 / 18 BIOMES", "at": 0.38},
	{"title": "Planting forest", "detail": "24 861 trees placed", "work": "24 861 / 32 000 TREES", "at": 0.55},
	{"title": "Raising settlements", "detail": "7 sites · 1 town · 6 camps", "work": "3 / 7 SITES", "at": 0.72},
	{"title": "Laying roads", "detail": "grid 24 m · 12 km planned", "work": "4.6 / 12 KM", "at": 0.86},
	{"title": "Baking light", "detail": "sun probes and horizon fog", "work": "0 / 3 PROBES", "at": 0.95},
]

var planet: Planet
var rows: Array[Dictionary] = []
var bar: KIT.SegmentBar
var percent_label: Label
var clock_label: Label
var stage_label: Label
var work_label: Label
var progress := 0.0
var clock := 0.0
var frozen := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	KIT.add_backdrop(self, KIT.AMBER, Vector2(520, 500))
	KIT.add_vignette(self)
	KIT.add_chrome(self, "GENERATION")
	KIT.add_divider(self, 970, 120, 840)
	build_planet()
	build_rail()
	apply()


func build_planet() -> void:
	planet = Planet.new()
	planet.seed_value = 8841229
	planet.radius_px = 250.0
	planet.mesh_detail = 1.0
	planet.tree_count = 2200
	planet.show_scan = true
	planet.show_grid = true
	planet.accent = KIT.AMBER
	planet.scan = 0.0
	var side := planet.viewport_side()
	planet.position = Vector2(520, 500) - Vector2(side, side) * 0.5
	add_child(planet)
	var caption := KIT.label(KIT.spaced("SHAPING WORLD  ·  SEED " + SEED_TEXT), 10, Color(0.87, 0.80, 0.63, 0.75), KIT.body_font())
	caption.position = Vector2(520 - 300, 812)
	caption.size = Vector2(600, 20)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(caption)
	var diagnostics := KIT.label("4 096 CHUNKS   ·   88 214 NODES   ·   1.8 GB", 10, Color(1, 1, 1, 0.3), KIT.mono_font())
	diagnostics.position = Vector2(520 - 300, 838)
	diagnostics.size = Vector2(600, 20)
	diagnostics.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(diagnostics)


func build_rail() -> void:
	KIT.text_at(self, KIT.spaced("GENERATING NEW WORLD"), 11, KIT.AMBER, KIT.body_font(), RAIL_LEFT, 226)
	KIT.text_at(self, WORLD_NAME, 60, KIT.INK, KIT.display_font(), RAIL_LEFT - 3, 252)
	KIT.text_at(self, "Seed %s  ·  Temperate forest basin  ·  64 km²" % SEED_TEXT, 15, KIT.MUTED, KIT.body_font(), RAIL_LEFT, 334)
	KIT.add_facts(self, RAIL_LEFT, 400, RAIL_WIDTH, [
		{"key_label": "SEED", "value": "8841229", "mono": true},
		{"key_label": "TEMPLATE", "value": "Integrated"},
		{"key_label": "BIOME MIX", "value": "Forest · Plains"},
		{"key_label": "ROADS", "value": "Grid 24 m"},
	])
	KIT.add_rule(self, RAIL_LEFT, 484, RAIL_WIDTH)

	var step_rail := KIT.StepRail.new()
	step_rail.step_height = STEP_HEIGHT
	step_rail.count = STEPS.size()
	step_rail.position = Vector2(RAIL_LEFT, STEP_TOP - 8)
	step_rail.size = Vector2(24, STEP_HEIGHT * float(STEPS.size()) - 2)
	add_child(step_rail)
	for i in STEPS.size():
		var y := STEP_TOP + float(i) * STEP_HEIGHT
		var dot := KIT.StepDot.new()
		dot.accent = KIT.AMBER
		dot.position = Vector2(RAIL_LEFT - 2, y + 1)
		dot.size = Vector2(24, 24)
		add_child(dot)
		var heading := KIT.text_at(self, str(STEPS[i].title), 15, KIT.INK, KIT.display_font(), RAIL_LEFT + 40, y - 3)
		var detail := KIT.text_at(self, str(STEPS[i].detail), 12, KIT.MUTED, KIT.body_font(), RAIL_LEFT + 40, y + 17)
		rows.append({"at": STEPS[i].at, "title": heading, "detail": detail, "dot": dot})

	percent_label = KIT.label("0%", 52, KIT.INK, KIT.display_font())
	percent_label.position = Vector2(RAIL_LEFT - 3, 834)
	add_child(percent_label)
	clock_label = KIT.label("", 13, KIT.MUTED, KIT.mono_font())
	clock_label.position = Vector2(RAIL_LEFT, 866)
	clock_label.size = Vector2(RAIL_WIDTH, 22)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(clock_label)

	stage_label = KIT.label("", 11, Color(0.85, 0.76, 0.55, 0.9), KIT.body_font())
	stage_label.position = Vector2(RAIL_LEFT, 906)
	add_child(stage_label)
	work_label = KIT.label("", 10, Color(0.80, 0.73, 0.58, 0.8), KIT.mono_font())
	work_label.position = Vector2(RAIL_LEFT, 906)
	work_label.size = Vector2(RAIL_WIDTH, 20)
	work_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(work_label)

	bar = KIT.SegmentBar.new()
	bar.accent = KIT.AMBER
	bar.position = Vector2(RAIL_LEFT, 934)
	bar.size = Vector2(RAIL_WIDTH, 8)
	add_child(bar)

	KIT.text_at(self, "Generation continues if you leave this screen — the world is safe to close.", 13, Color(0.87, 0.90, 0.84, 0.7), KIT.body_font(), RAIL_LEFT, 1002)
	KIT.add_keycap(self, 1740, 1002, "ESC")
	KIT.text_at(self, KIT.spaced("CANCEL"), 10, KIT.DIM, KIT.body_font(), 1786, 1006)


func _process(delta: float) -> void:
	if not frozen:
		clock += delta
	progress = 1.0 - pow(1.0 - clampf(clock / MOCK_SECONDS, 0.0, 1.0), 1.25)
	if planet != null:
		planet.set_spin(clock * 0.05)
		planet.show_scan = progress < 0.999
		planet.set_scan_progress(clampf(progress, 0.0, 0.999))
	apply()


func apply() -> void:
	var value := clampf(progress, 0.0, 1.0)
	var finished := value >= 0.999
	bar.value = value
	percent_label.text = "%d%%" % int(round(value * 100.0))
	var remaining := maxf(0.0, (1.0 - value) * 70.0)
	if finished:
		clock_label.text = "READY   ·   %s elapsed" % format_clock(clock)
	else:
		clock_label.text = "%d s remaining   ·   %s elapsed" % [int(ceil(remaining)), format_clock(clock)]
	var active := 0
	for i in rows.size():
		if value >= float(rows[i].at):
			active = i + 1
	active = mini(active, rows.size() - 1)
	for i in rows.size():
		var row := rows[i]
		var dot: KIT.StepDot = row.dot
		var heading: Label = row.title
		var detail: Label = row.detail
		if finished or value >= float(row.at):
			dot.state = 2
			heading.add_theme_color_override("font_color", Color(0.72, 0.78, 0.74, 0.58))
			detail.add_theme_color_override("font_color", Color(0.66, 0.73, 0.69, 0.68))
		elif i == active:
			dot.state = 1
			heading.add_theme_color_override("font_color", KIT.INK)
			detail.add_theme_color_override("font_color", KIT.MUTED)
		else:
			dot.state = 0
			heading.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
			detail.add_theme_color_override("font_color", Color(1, 1, 1, 0.32))
		dot.pulse = clock
	if finished:
		stage_label.text = KIT.spaced("WORLD READY")
		work_label.text = KIT.spaced("ENTER THE FOREST")
	else:
		stage_label.text = KIT.spaced(str(STEPS[active].title).to_upper())
		work_label.text = KIT.spaced(str(STEPS[active].work))


func format_clock(seconds: float) -> String:
	var whole := int(seconds)
	return "%02d:%02d" % [whole / 60, whole % 60]


func set_mock_time(seconds: float) -> void:
	frozen = true
	clock = seconds
	progress = 1.0 - pow(1.0 - clampf(clock / MOCK_SECONDS, 0.0, 1.0), 1.25)
	if planet != null:
		planet.set_spin(clock * 0.05)
		planet.show_scan = progress < 0.999
		planet.set_scan_progress(clampf(progress, 0.0, 0.999))
	apply()
