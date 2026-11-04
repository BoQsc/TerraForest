# SPDX-License-Identifier: 0BSD
extends Control
## Standalone BG5-style world-loading mockup. Presentation-only sample data.

var display_font: SystemFont
var body_font: SystemFont

class Shade extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), Color(0.08, 0.09, 0.07, 0.12))
		draw_rect(Rect2(0, 0, w * 0.55, h), Color(0.01, 0.025, 0.025, 0.12))

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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	display_font = SystemFont.new()
	display_font.font_names = PackedStringArray(["Bahnschrift SemiCondensed", "Bahnschrift", "Segoe UI", "Arial"])
	display_font.font_weight = 700
	body_font = SystemFont.new()
	body_font.font_names = PackedStringArray(["Segoe UI", "Arial"])
	var backdrop := TextureRect.new()
	backdrop.texture = texture_crop("res://reports/entry_fly_in/browser/05_first_person.png", Rect2(0, 180, 900, 720))
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var shade := Shade.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.14, 0.52, 0.74, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.01, 0.02, 0.02, 0.55), Color(0.01, 0.02, 0.02, 0.16),
		Color(0, 0, 0, 0), Color(0.01, 0.02, 0.02, 0.32), Color(0.005, 0.012, 0.012, 0.82)
	])
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0, 0)
	gradient_texture.fill_to = Vector2(0, 1)
	var gradient_overlay := TextureRect.new()
	gradient_overlay.texture = gradient_texture
	gradient_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	gradient_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gradient_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gradient_overlay)
	build_logo()
	build_tip()
	build_bottom()

func texture_crop(path: String, region: Rect2) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	atlas.atlas = ImageTexture.create_from_image(image)
	atlas.region = region
	return atlas

func label(text: String, size: int, color: Color, display: bool = false) -> Label:
	var out := Label.new()
	out.text = text
	out.add_theme_font_size_override("font_size", size)
	out.add_theme_color_override("font_color", color)
	out.add_theme_font_override("font", display_font if display else body_font)
	out.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	out.add_theme_constant_override("shadow_offset_x", 1)
	out.add_theme_constant_override("shadow_offset_y", 2)
	return out

func style(fill: Color, border: Color, radius: int, shadow: int = 0) -> StyleBoxFlat:
	var out := StyleBoxFlat.new()
	out.bg_color = fill
	out.border_color = border
	out.set_border_width_all(1)
	out.set_corner_radius_all(radius)
	out.set_content_margin_all(16)
	out.shadow_color = Color(0, 0, 0, 0.32)
	out.shadow_size = shadow
	return out

func bar_style(fill: Color, radius: int) -> StyleBoxFlat:
	var out := StyleBoxFlat.new()
	out.bg_color = fill
	out.set_corner_radius_all(radius)
	return out

func build_logo() -> void:
	var logo := VBoxContainer.new()
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.offset_left = -430
	logo.offset_right = 430
	logo.offset_top = 24
	logo.offset_bottom = 158
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_theme_constant_override("separation", 4)
	add_child(logo)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	logo.add_child(row)
	row.add_child(label("TERRA", 58, Color(0.95, 0.96, 0.92), true))
	row.add_child(label("FOREST", 58, Color("#8bdfb7"), true))
	var tagline_row := HBoxContainer.new()
	tagline_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tagline_row.add_theme_constant_override("separation", 12)
	logo.add_child(tagline_row)
	var left_line := ColorRect.new()
	left_line.custom_minimum_size = Vector2(92, 1)
	left_line.color = Color(0.75, 0.78, 0.72, 0.6)
	tagline_row.add_child(left_line)
	tagline_row.add_child(label("OPEN WORLD SURVIVAL", 12, Color(0.82, 0.84, 0.78, 0.85)))
	var right_line := ColorRect.new()
	right_line.custom_minimum_size = Vector2(92, 1)
	right_line.color = Color(0.75, 0.78, 0.72, 0.6)
	tagline_row.add_child(right_line)

func build_tip() -> void:
	var tip := PanelContainer.new()
	tip.anchor_left = 0.17
	tip.anchor_right = 0.68
	tip.anchor_top = 1.0
	tip.anchor_bottom = 1.0
	tip.offset_top = -350
	tip.offset_bottom = -252
	tip.add_theme_stylebox_override("panel", style(Color(0.025, 0.035, 0.035, 0.82), Color(0.34, 0.40, 0.34, 0.45), 7))
	add_child(tip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	tip.add_child(row)
	row.add_child(Campfire.new())
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 4)
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(copy)
	copy.add_child(label("SURVIVAL TIP", 11, Color(0.83, 0.73, 0.48)))
	var tip_text := label("Build a campfire early. It lets you cook food, boil water and stay warm at night.", 15, Color(0.84, 0.86, 0.80, 0.9))
	tip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(tip_text)

func build_bottom() -> void:
	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -236
	bottom.offset_bottom = 0
	var bottom_style := style(Color(0.015, 0.020, 0.020, 0.95), Color(0.28, 0.32, 0.30, 0.30), 0)
	bottom_style.border_width_top = 1
	bottom_style.set_content_margin_all(0)
	bottom.add_theme_stylebox_override("panel", bottom_style)
	add_child(bottom)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 68)
	margin.add_theme_constant_override("margin_right", 68)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	bottom.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 34)
	margin.add_child(columns)
	var primary := VBoxContainer.new()
	primary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	primary.add_theme_constant_override("separation", 8)
	columns.add_child(primary)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 12)
	primary.add_child(heading)
	var loading_label := label("LOADING WORLD", 18, Color(0.92, 0.92, 0.86), true)
	loading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(loading_label)
	heading.add_child(label("72%", 17, Color(0.88, 0.90, 0.84)))
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value = 72
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.add_theme_stylebox_override("background", bar_style(Color("#2c322e"), 0))
	bar.add_theme_stylebox_override("fill", bar_style(Color("#77c56b"), 0))
	primary.add_child(bar)
	var checks := HBoxContainer.new()
	checks.add_theme_constant_override("separation", 18)
	primary.add_child(checks)
	add_check(checks, "✓  INITIALIZING", Color(0.40, 0.43, 0.40))
	add_check(checks, "✓  LOADING ASSETS", Color(0.40, 0.43, 0.40))
	add_check(checks, "✓  GENERATING TERRAIN", Color(0.40, 0.43, 0.40))
	add_check(checks, "●  PLACING OBJECTS", Color("#8bdfb7"))
	add_check(checks, "○  SPAWNING RESOURCES", Color(0.43, 0.46, 0.42))
	add_check(checks, "○  FINALIZING", Color(0.43, 0.46, 0.42))
	var stats := VBoxContainer.new()
	stats.custom_minimum_size.x = 350
	stats.add_theme_constant_override("separation", 6)
	columns.add_child(stats)
	add_stat(stats, "△", "WORLD SIZE", "64 km²")
	add_stat(stats, "▤", "SEED", "BG5-249831")
	add_stat(stats, "♣", "BIOME MIX", "Forest · Plains · Hills")

func add_check(parent: HBoxContainer, text: String, color: Color) -> void:
	var item := label(text, 10, color)
	parent.add_child(item)

func add_stat(parent: VBoxContainer, glyph: String, title: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	parent.add_child(row)
	var icon := label(glyph, 16, Color(0.72, 0.67, 0.51))
	icon.custom_minimum_size.x = 24
	row.add_child(icon)
	var key := label(title, 10, Color(0.54, 0.58, 0.53))
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)
	var val := label(value, 11, Color(0.86, 0.86, 0.80))
	row.add_child(val)
