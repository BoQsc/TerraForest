# SPDX-License-Identifier: 0BSD
extends PanelContainer
## Reusable survival-tip card for world-loading or other mockups.
## Instantiate res://demo/ui/survival_tip.tscn, then set heading_text/tip_text.

@export var heading_text := "SURVIVAL TIP"
@export_multiline var tip_text := "Build a campfire early. It lets you cook food, boil water and stay warm at night."
@export var heading_color := Color("#d6b36a")
@export var text_color := Color(0.84, 0.86, 0.80, 0.9)
var heading: Label
var body: Label

class Campfire extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(46, 46)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		draw_line(c + Vector2(-13, 15), c + Vector2(13, 9), Color(0.60, 0.48, 0.31, 0.9), 3.0, true)
		draw_line(c + Vector2(-11, 8), c + Vector2(12, 15), Color(0.48, 0.37, 0.24, 0.9), 3.0, true)
		draw_colored_polygon(PackedVector2Array([
			Vector2(c.x, c.y - 17), Vector2(c.x + 8, c.y + 2),
			Vector2(c.x + 3, c.y + 7), Vector2(c.x - 2, c.y + 2),
			Vector2(c.x - 7, c.y + 8), Vector2(c.x - 9, c.y - 1)
		]), Color(0.82, 0.43, 0.18, 0.95))
		draw_colored_polygon(PackedVector2Array([
			Vector2(c.x, c.y - 8), Vector2(c.x + 4, c.y + 3),
			Vector2(c.x, c.y + 7), Vector2(c.x - 4, c.y + 2)
		]), Color(0.98, 0.75, 0.32, 0.95))

func _ready() -> void:
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, 640.0), maxf(custom_minimum_size.y, 92.0))
	var card := StyleBoxFlat.new()
	card.bg_color = Color(0.025, 0.035, 0.035, 0.82)
	card.border_color = Color(0.34, 0.40, 0.34, 0.45)
	card.set_border_width_all(1)
	card.set_corner_radius_all(7)
	card.set_content_margin_all(16)
	add_theme_stylebox_override("panel", card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	row.add_child(Campfire.new())
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 4)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	heading = Label.new()
	heading.text = heading_text
	heading.add_theme_font_size_override("font_size", 11)
	heading.add_theme_color_override("font_color", heading_color)
	heading.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	heading.add_theme_constant_override("shadow_offset_x", 1)
	heading.add_theme_constant_override("shadow_offset_y", 1)
	copy.add_child(heading)
	body = Label.new()
	body.text = tip_text
	body.add_theme_font_size_override("font_size", 15)
	body.add_theme_color_override("font_color", text_color)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	body.add_theme_constant_override("shadow_offset_x", 1)
	body.add_theme_constant_override("shadow_offset_y", 1)
	copy.add_child(body)

func set_tip(new_heading: String, new_text: String) -> void:
	heading_text = new_heading
	tip_text = new_text
	if is_instance_valid(heading): heading.text = new_heading
	if is_instance_valid(body): body.text = new_text
