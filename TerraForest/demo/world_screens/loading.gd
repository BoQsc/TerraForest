# SPDX-License-Identifier: 0BSD
extends Control
## World loading screen mockup: returning to a saved world, with the planet held
## in an orbit ring while the save streams back in. Presentation only.

const KIT := preload("res://demo/world_screens/kit.gd")
const Planet := preload("res://demo/world_screens/planet.gd")

const GLOBE_CENTER := Vector2(520, 552)
const RING_RADIUS := 336.0
const RAIL_LEFT := 1030.0
const RAIL_WIDTH := 806.0
const STEP_TOP := 512.0
const STEP_HEIGHT := 52.0
const MOCK_SECONDS := 16.0

const STEPS := [
	{"title": "Reading your save", "detail": "8841229 · slot 1", "work": "SAVE LOADED", "at": 0.04},
	{"title": "Streaming terrain", "detail": "radial chunks around your camp", "work": "512 / 512 CHUNKS", "at": 0.24},
	{"title": "Restoring vegetation", "detail": "old growth and meadow", "work": "18 204 / 24 861 TREES", "at": 0.46},
	{"title": "Respawning structures", "detail": "camp, bridge, trail signs", "work": "3 / 7 SITES", "at": 0.64},
	{"title": "Your camp", "detail": "fire pit, bedroll, chest", "work": "1 / 3 OBJECTS", "at": 0.82},
	{"title": "First frame", "detail": "spawn check and warm shaders", "work": "0 / 2 STREAMS", "at": 1.0},
]

var planet: Planet
var ring: KIT.OrbitRing
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
	KIT.add_backdrop(self, KIT.MINT, GLOBE_CENTER)
	KIT.add_vignette(self)
	KIT.add_chrome(self, "LOADING")
	KIT.add_divider(self, 970, 120, 840)
	build_planet()
	build_rail()
	apply()


func build_planet() -> void:
	ring = KIT.OrbitRing.new()
	ring.radius = RING_RADIUS
	ring.accent = KIT.MINT
	ring.position = GLOBE_CENTER - Vector2(ring.radius + 40.0, ring.radius + 40.0)
	ring.size = Vector2(ring.radius + 40.0, ring.radius + 40.0) * 2.0
	add_child(ring)
	planet = Planet.new()
	planet.seed_value = 8841229
	planet.radius_px = 250.0
	planet.mesh_detail = 1.0
	planet.tree_count = 2200
	planet.accent = KIT.MINT
	var side := planet.viewport_side()
	planet.position = GLOBE_CENTER - Vector2(side, side) * 0.5
	add_child(planet)
	var caption := KIT.label(KIT.spaced("TERRAFORMED FROM SEED 8 841 229"), 10, Color(1, 1, 1, 0.5), KIT.body_font())
	caption.position = Vector2(GLOBE_CENTER.x - 300, 952)
	caption.size = Vector2(600, 20)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(caption)


func build_rail() -> void:
	KIT.text_at(self, KIT.spaced("RETURNING TO YOUR WORLD"), 11, KIT.MINT, KIT.body_font(), RAIL_LEFT, 226)
	KIT.text_at(self, "ALDERGROVE HOLLOW", 60, KIT.INK, KIT.display_font(), RAIL_LEFT - 3, 252)
	KIT.text_at(self, "Survived 6 h 12 m  ·  camp at Hollow Creek  ·  seed 8 841 229", 15, KIT.MUTED, KIT.body_font(), RAIL_LEFT, 334)
	KIT.add_facts(self, RAIL_LEFT, 400, RAIL_WIDTH, [
		{"key_label": "SEED", "value": "8841229", "mono": true},
		{"key_label": "BIOME", "value": "Temperate forest"},
		{"key_label": "AREA", "value": "64 km²"},
		{"key_label": "RULESET", "value": "Survival"},
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
		dot.accent = KIT.MINT
		dot.position = Vector2(RAIL_LEFT - 2, y + 4)
		dot.size = Vector2(24, 24)
		add_child(dot)
		var heading := KIT.text_at(self, str(STEPS[i].title), 16, KIT.INK, KIT.display_font(), RAIL_LEFT + 40, y - 1)
		var detail := KIT.text_at(self, str(STEPS[i].detail), 12, KIT.MUTED, KIT.body_font(), RAIL_LEFT + 40, y + 21)
		rows.append({"at": STEPS[i].at, "title": heading, "detail": detail, "dot": dot})

	percent_label = KIT.label("0%", 52, KIT.INK, KIT.display_font())
	percent_label.position = Vector2(RAIL_LEFT - 3, 834)
	add_child(percent_label)
	clock_label = KIT.label("", 13, KIT.MUTED, KIT.mono_font())
	clock_label.position = Vector2(RAIL_LEFT, 866)
	clock_label.size = Vector2(RAIL_WIDTH, 22)
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(clock_label)

	stage_label = KIT.label("", 11, Color(0.70, 0.77, 0.73, 0.9), KIT.body_font())
	stage_label.position = Vector2(RAIL_LEFT, 906)
	add_child(stage_label)
	work_label = KIT.label("", 10, Color(0.64, 0.71, 0.67, 0.8), KIT.mono_font())
	work_label.position = Vector2(RAIL_LEFT, 906)
	work_label.size = Vector2(RAIL_WIDTH, 20)
	work_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(work_label)

	bar = KIT.SegmentBar.new()
	bar.accent = KIT.MINT
	bar.position = Vector2(RAIL_LEFT, 934)
	bar.size = Vector2(RAIL_WIDTH, 8)
	add_child(bar)

	KIT.text_at(self, "Field note — game trails north of the creek lead to the hollow.", 13, Color(0.87, 0.90, 0.84, 0.72), KIT.body_font(), RAIL_LEFT, 1002)
	KIT.add_keycap(self, 1740, 1002, "ESC")
	KIT.text_at(self, KIT.spaced("CANCEL"), 10, KIT.DIM, KIT.body_font(), 1786, 1006)


func _process(delta: float) -> void:
	if not frozen:
		clock += delta
	progress = 1.0 - pow(1.0 - clampf(clock / MOCK_SECONDS, 0.0, 1.0), 1.35)
	if planet != null:
		planet.set_spin(clock * 0.075)
	if ring != null:
		ring.pulse = clock
	apply()


func apply() -> void:
	var value := clampf(progress, 0.0, 1.0)
	var finished := value >= 0.999
	ring.value = value
	bar.value = value
	percent_label.text = "%d%%" % int(round(value * 100.0))
	var remaining := maxf(0.0, (1.0 - value) * 24.0)
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
		stage_label.text = KIT.spaced("WELCOME BACK")
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
	progress = 1.0 - pow(1.0 - clampf(clock / MOCK_SECONDS, 0.0, 1.0), 1.35)
	if planet != null:
		planet.set_spin(clock * 0.075)
	if ring != null:
		ring.pulse = clock
	apply()
