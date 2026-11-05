# SPDX-License-Identifier: 0BSD
extends Control
## Loading, re-specified from progress_meter.gd + loading_panel.gd +
## loading_details.gd: the photograph background, the real loading stages with
## their probe/coverage counters, the measured clock, and the developer readout.

const KIT := preload("res://demo/world_survey/kit.gd")

const PHOTO_FALLBACK := "res://reports/entry_fly_in/browser/01_aerial.png"
const PERCENT := 68
const STAGE := "Loading nearby terrain and collision · 812 / 1 200 probes ready"
const STAGE_NAME := "Loading nearby terrain and collision"
const ELAPSED := "0:19"
const REMAINING := "0:09"
const WORK := "coverage 24 / 40 (world)   ·   collision 812 / 1 200   ·   worker idle   ·   queued 0   ·   in flight 2   ·   upload queue 0   ·   cache hits 148 / misses 6"

const STOPS := [0, 15, 75, 94, 100]
const STOP_LABELS := ["READ DATA", "SPAWN", "COVERAGE", "OBJECTS", "PLAY"]

const LIVE := [
	"coverage.ready = 24",
	"coverage.total = 40",
	"local = 812",
	"local_total = 1200",
]

const HISTORY := [
	"  0.42 s  Reading saved world data",
	"  3.18 s  Finding a safe player position",
	" 12.55 s  Loading nearby terrain and collision",
]

const SESSION := [
	"Godot 4.7.2.stable",
	"Vulkan 1.4.351 · Forward+",
	"viewport 1920 × 1080 · fps cap 60",
]

var world := {"path": PHOTO_FALLBACK, "slot": "reference"}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	world = world_photo()
	KIT.photo_frame(self, 0, 0, 1920, 1080, str(world.path), 0.45)
	var grid := KIT.SurveyGrid.new()
	grid.position = Vector2(0, 0)
	grid.size = Vector2(1920, 1080)
	grid.spacing = 120.0
	grid.color = Color(0.42, 0.67, 0.58, 0.07)
	add_child(grid)
	build_wordmark()
	build_panel()
	build_details()


func build_wordmark() -> void:
	var font := KIT.font(["Georgia", "DejaVu Serif"], 700)
	var row := HBoxContainer.new()
	row.position = Vector2(0, 250)
	row.size = Vector2(1920, 80)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.add_child(KIT.label("Terra", 64, KIT.WARM, font))
	row.add_child(KIT.label("Forest", 64, Color("#98ddbc"), font))
	var rule := ColorRect.new()
	rule.color = Color("#779f8c")
	rule.position = Vector2(870, 336)
	rule.size = Vector2(180, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)


func build_panel() -> void:
	KIT.panel(self, 96, 596, 1728, 236, Color(0.015, 0.035, 0.04, 0.93), Color(0.42, 0.67, 0.58, 0.4), 6)
	KIT.text_at(self, "Loading your world  ·  " + str(world.slot), 22, KIT.INK, KIT.display_font(), 120, 616)
	KIT.right_text_at(self, "%d%%" % PERCENT, 34, KIT.ACCENT, KIT.display_font(), 1800, 610, 240)
	KIT.text_at(self, STAGE, 15, KIT.MUTED, KIT.body_font(), 120, 652)
	KIT.right_text_at(self, "elapsed %s  ·  remaining ≈ %s" % [ELAPSED, REMAINING], 12, KIT.DIM, KIT.mono_font(), 1800, 654, 420)
	var meter := KIT.Meter.new()
	meter.accent = KIT.ACCENT
	meter.segments = 64
	meter.value = float(PERCENT) / 100.0
	meter.position = Vector2(120, 690)
	meter.size = Vector2(1680, 10)
	add_child(meter)
	var rail := KIT.StageRail.new()
	rail.stops = STOPS
	rail.value = float(PERCENT) / 100.0
	rail.accent = KIT.ACCENT
	rail.position = Vector2(120, 712)
	rail.size = Vector2(1680, 12)
	add_child(rail)
	for i in STOPS.size():
		var stop_value := float(STOPS[i])
		var x := 120.0 + (stop_value / 100.0) * 1680.0
		var label_node := KIT.label(str(STOP_LABELS[i]), 9, KIT.DIM, KIT.body_font())
		label_node.position = Vector2(clampf(x - 24.0, 120.0, 1776.0), 726)
		add_child(label_node)
	KIT.text_at(self, "measured stages  ·  the final 6% belongs to playback", 10, KIT.DIM, KIT.body_font(), 120, 748)
	KIT.text_at(self, WORK, 11, KIT.DIM, KIT.mono_font(), 120, 776)
	button(1680, 772, 120, 38, "CANCEL", false)
	KIT.text_at(self, "ESC", 10, KIT.DIM, KIT.mono_font(), 1648, 784)


func build_details() -> void:
	KIT.panel(self, 96, 32, 1728, 120, Color(0.015, 0.035, 0.04, 0.9), Color(1, 1, 1, 0.08), 6)
	KIT.text_at(self, "DEVELOPER DETAILS   ·   elapsed 19.4 s   ·   current stage 6.1 s   ·   refresh 4 Hz", 11, KIT.ACCENT, KIT.mono_font(), 120, 44)
	KIT.text_at(self, "LIVE WORK / raw counters", 9, KIT.DIM, KIT.mono_font(), 120, 68)
	KIT.text_at(self, "COMPLETED STAGES / measured elapsed time", 9, KIT.DIM, KIT.mono_font(), 640, 68)
	KIT.text_at(self, "SESSION / hardware and log", 9, KIT.DIM, KIT.mono_font(), 1200, 68)
	var y := 84.0
	for line in LIVE:
		KIT.text_at(self, str(line), 11, Color("#d5e3dd"), KIT.mono_font(), 120, y)
		y += 15.0
	y = 84.0
	for line in HISTORY:
		KIT.text_at(self, str(line), 11, Color("#d5e3dd"), KIT.mono_font(), 640, y)
		y += 15.0
	y = 84.0
	for line in SESSION:
		KIT.text_at(self, str(line), 11, Color("#d5e3dd"), KIT.mono_font(), 1200, y)
		y += 15.0



func button(x: float, y: float, width: float, height: float, caption: String, filled: bool) -> void:
	var box := KIT.panel(self, x, y, width, height, KIT.ACCENT if filled else KIT.PANEL_HI, Color(0, 0, 0, 0) if filled else KIT.BORDER, 6)
	var text_node := KIT.label(KIT.spaced(caption), 11, Color("#08171a") if filled else KIT.INK, KIT.body_font())
	text_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(text_node)


func world_photo() -> Dictionary:
	for slot in ["Amber_Bay", "Calm_Haven", "Bright_Forest"]:
		for view in ["north", "road", "market"]:
			var path := "user://worlds/%s.preview/%s.png" % [slot, view]
			if FileAccess.file_exists(path):
				return {"path": path, "slot": slot}
	return {"path": PHOTO_FALLBACK, "slot": "reference"}


func set_mock_time(_seconds: float) -> void:
	pass
