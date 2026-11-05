# SPDX-License-Identifier: 0BSD
extends Control
## Loading, re-specified from loading_panel.gd (bottom-wide card, compact 1120 px),
## progress_meter.gd (stages, stops, work counters) and loading_details.gd, whose
## console readout is collapsed to a single developer ribbon at the top edge.

const KIT := preload("res://demo/world_survey/kit.gd")

const PHOTO_FALLBACK := "res://reports/entry_fly_in/browser/01_aerial.png"
const PERCENT := 68
const STAGE := "Loading nearby terrain and collision · 812 / 1 200 probes ready"
const ELAPSED := "0:19"
const REMAINING := "0:09"
const WORK := "coverage 24 / 40 (world)   ·   collision 812 / 1 200   ·   worker idle   ·   queued 0   ·   in flight 2   ·   upload queue 0   ·   cache hits 148 / misses 6"

const STOPS := [0, 15, 75, 94, 100]
const STOP_LABELS := ["READ DATA", "SPAWN", "COVERAGE", "OBJECTS", "PLAY"]

const RIBBON := "DEVELOPER DETAILS   ·   elapsed 19.4 s   ·   current stage 6.1 s   ·   coverage 24 / 40   ·   collision 812 / 1 200   ·   worker idle   ·   queued 0   ·   in flight 2   ·   cache 148 / 6"

var world := {"path": PHOTO_FALLBACK, "slot": "reference"}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	world = world_photo()
	KIT.photo_frame(self, 0, 0, 1920, 1080, str(world.path), 0.46)
	var grid := KIT.SurveyGrid.new()
	grid.position = Vector2(0, 0)
	grid.size = Vector2(1920, 1080)
	grid.spacing = 120.0
	grid.color = Color(0.42, 0.67, 0.58, 0.07)
	add_child(grid)
	build_wordmark()
	build_card()
	build_ribbon()


func build_wordmark() -> void:
	var font := KIT.font(["Georgia", "DejaVu Serif"], 700)
	var row := HBoxContainer.new()
	row.position = Vector2(0, 262)
	row.size = Vector2(1920, 80)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	row.add_child(KIT.label("Terra", 64, KIT.WARM, font))
	row.add_child(KIT.label("Forest", 64, Color("#98ddbc"), font))
	var rule := ColorRect.new()
	rule.color = Color("#779f8c")
	rule.position = Vector2(870, 348)
	rule.size = Vector2(180, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)


func build_card() -> void:
	# loading_panel.gd: bottom-anchored card, 1120 px compact width, 24 px off the bottom.
	var card := KIT.panel(self, 400, 884, 1120, 172, Color(0.025, 0.065, 0.07, 0.94), Color(0.42, 0.67, 0.58, 0.28), 7)
	KIT.text_at(self, "Loading your world  ·  " + str(world.slot), 18, KIT.INK, KIT.display_font(), 416, 898)
	KIT.right_text_at(self, "elapsed %s  ·  est. remaining %s" % [ELAPSED, REMAINING], 13, Color("#a9ddc8"), KIT.mono_font(), 1352, 902, 360)
	button(1368, 892, 136, 30, "CANCEL", false)
	KIT.text_at(self, STAGE, 15, KIT.MUTED, KIT.body_font(), 416, 930)
	KIT.right_text_at(self, "%d%%" % PERCENT, 22, KIT.ACCENT, KIT.display_font(), 1504, 924, 140)
	var meter := KIT.Meter.new()
	meter.accent = KIT.ACCENT
	meter.segments = 64
	meter.value = float(PERCENT) / 100.0
	meter.position = Vector2(416, 960)
	meter.size = Vector2(1088, 8)
	add_child(meter)
	var rail := KIT.StageRail.new()
	rail.stops = STOPS
	rail.value = float(PERCENT) / 100.0
	rail.accent = KIT.ACCENT
	rail.position = Vector2(416, 974)
	rail.size = Vector2(1088, 10)
	add_child(rail)
	for i in STOPS.size():
		var stop_value := float(STOPS[i])
		var x := 416.0 + (stop_value / 100.0) * 1088.0
		var label_node := KIT.label(str(STOP_LABELS[i]), 9, KIT.DIM, KIT.body_font())
		label_node.position = Vector2(clampf(x - 20.0, 416.0, 1470.0), 988)
		add_child(label_node)
	KIT.text_at(self, WORK, 11, KIT.DIM, KIT.mono_font(), 416, 1012)
	KIT.text_at(self, "measured stages  ·  the final 6% belongs to playback", 10, KIT.DIM, KIT.body_font(), 416, 1032)


func build_ribbon() -> void:
	# loading_details.gd is a console overlay; here it is collapsed to one status line.
	KIT.panel(self, 0, 0, 1258, 34, Color(0.015, 0.035, 0.04, 0.72), Color(1, 1, 1, 0.06), 0)
	KIT.text_at(self, RIBBON, 10, KIT.ACCENT, KIT.mono_font(), 24, 10)
	KIT.right_text_at(self, "F1  ·  EXPAND", 9, KIT.DIM, KIT.body_font(), 1234, 11, 160)


func button(x: float, y: float, width: float, height: float, caption: String, filled: bool) -> void:
	var box := KIT.panel(self, x, y, width, height, KIT.ACCENT if filled else KIT.PANEL_HI, Color(0, 0, 0, 0) if filled else KIT.BORDER, 5)
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
