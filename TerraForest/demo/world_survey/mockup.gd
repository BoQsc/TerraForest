# SPDX-License-Identifier: 0BSD
extends Control
## Review shell for the world-flow mockups built from the shipped screens:
## 1 My worlds, 2 Create world + generation, 3 Loading.

const KIT := preload("res://demo/world_survey/kit.gd")
const WorldsScreen := preload("res://demo/world_survey/worlds.gd")
const CreateScreen := preload("res://demo/world_survey/create.gd")
const LoadingScreen := preload("res://demo/world_survey/loading.gd")

const TABS := ["MY WORLDS", "CREATE", "LOADING"]

var screens: Array[Control] = []
var tabs: Array[Button] = []
var underlines: Array[ColorRect] = []
var current := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for script in [WorldsScreen, CreateScreen, LoadingScreen]:
		var screen: Control = script.new()
		screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(screen)
		screens.append(screen)
	build_tabs()
	show_screen(0)


func build_tabs() -> void:
	var width := 190.0
	var start := 1856.0 - width * float(TABS.size()) - 8.0
	for i in TABS.size():
		var button := Button.new()
		button.flat = true
		button.focus_mode = Control.FOCUS_NONE
		button.text = "%d   %s" % [i + 1, KIT.spaced(TABS[i])]
		button.add_theme_font_override("font", KIT.body_font())
		button.add_theme_font_size_override("font_size", 9)
		button.add_theme_color_override("font_color", Color(1, 1, 1, 0.28))
		button.add_theme_color_override("font_hover_color", KIT.INK)
		button.position = Vector2(start + float(i) * width, 6)
		button.size = Vector2(width, 24)
		button.pressed.connect(show_screen.bind(i))
		add_child(button)
		tabs.append(button)
		var underline := ColorRect.new()
		underline.color = KIT.ACCENT
		underline.position = Vector2(start + float(i) * width + width * 0.5 - 20.0, 30)
		underline.size = Vector2(40, 2)
		underline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(underline)
		underlines.append(underline)


func show_screen(index: int) -> void:
	current = clampi(index, 0, screens.size() - 1)
	for i in screens.size():
		screens[i].visible = i == current
	for i in tabs.size():
		tabs[i].add_theme_color_override("font_color", KIT.ACCENT if i == current else Color(1, 1, 1, 0.28))
		underlines[i].visible = i == current


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				show_screen(0)
			KEY_2:
				show_screen(1)
			KEY_3:
				show_screen(2)


func set_mock_time(seconds: float) -> void:
	for screen in screens:
		screen.set_mock_time(seconds)
