# SPDX-License-Identifier: 0BSD
extends RefCounted
## Palette, type and survey widgets for the world-flow mockups. Colours, copy and
## figures are taken from the shipped game (worlds.gd, world_creation_panel.gd,
## progress_meter.gd, loading_details.gd), not invented for the mockups.

const BG := Color("#0b171d")
const PANEL := Color("#14292e")
const PANEL_HI := Color("#1b3035")
const BORDER := Color("#2b4245")
const INK := Color("#e6eee7")
const MUTED := Color("#9bafad")
const DIM := Color("#6d8380")
const ACCENT := Color("#91d5b4")
const WARM := Color("#e6c08a")
const RULE := Color(0.42, 0.67, 0.58, 0.22)

static var _display: SystemFont
static var _body: SystemFont
static var _mono: SystemFont


static func font(names: Array, weight: int) -> SystemFont:
	var value := SystemFont.new()
	value.font_names = PackedStringArray(names)
	value.font_weight = weight
	value.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	value.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return value


static func display() -> SystemFont:
	if _display == null:
		_display = font(["Bahnschrift SemiCondensed", "Bahnschrift", "Segoe UI"], 600)
	return _display


static func body() -> SystemFont:
	if _body == null:
		_body = font(["Segoe UI", "Segoe UI Variable Text", "Arial"], 400)
	return _body


static func mono() -> SystemFont:
	if _mono == null:
		_mono = font(["Consolas", "Cascadia Mono", "Courier New"], 400)
	return _mono


static func display_font() -> SystemFont:
	return display()


static func body_font() -> SystemFont:
	return body()


static func mono_font() -> SystemFont:
	return mono()


static func spaced(text: String) -> String:
	var out := ""
	for i in text.length():
		var character := text[i]
		out += character
		if character != " ":
			out += " "
	return out.strip_edges()


static func label(text_value: String, font_size: int, color: Color, font_override: Font = null) -> Label:
	var out := Label.new()
	out.text = text_value
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out.add_theme_font_override("font", font_override if font_override != null else body())
	out.add_theme_font_size_override("font_size", font_size)
	out.add_theme_color_override("font_color", color)
	return out


static func text_at(parent: Control, text_value: String, font_size: int, color: Color, font_override: Font, x: float, y: float) -> Label:
	var out := label(text_value, font_size, color, font_override)
	out.position = Vector2(x, y)
	parent.add_child(out)
	return out


static func right_text_at(parent: Control, text_value: String, font_size: int, color: Color, font_override: Font, right: float, y: float, width: float = 700.0) -> Label:
	var out := label(text_value, font_size, color, font_override)
	out.position = Vector2(right - width, y)
	out.size = Vector2(width, font_size * 2.0)
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(out)
	return out


static func rule(parent: Control, x: float, y: float, width: float, color: Color = RULE) -> ColorRect:
	var node := ColorRect.new()
	node.color = color
	node.position = Vector2(x, y)
	node.size = Vector2(width, 1)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


static func vrule(parent: Control, x: float, y: float, height: float, color: Color = RULE) -> ColorRect:
	var node := ColorRect.new()
	node.color = color
	node.position = Vector2(x, y)
	node.size = Vector2(1, height)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


static func panel(parent: Control, x: float, y: float, width: float, height: float, fill: Color = PANEL, border: Color = BORDER, radius: int = 6) -> PanelContainer:
	var node := PanelContainer.new()
	var skin := StyleBoxFlat.new()
	skin.bg_color = fill
	skin.border_color = border
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(radius)
	skin.set_content_margin_all(0)
	node.add_theme_stylebox_override("panel", skin)
	node.position = Vector2(x, y)
	node.size = Vector2(width, height)
	node.custom_minimum_size = Vector2(width, height)
	parent.add_child(node)
	return node


static func surface(parent: Control, x: float, y: float, width: float, height: float, fill: Color = PANEL, border: Color = BORDER, radius: int = 6) -> Panel:
	## Non-container panel: children keep their own positions and sizes.
	var node := Panel.new()
	var skin := StyleBoxFlat.new()
	skin.bg_color = fill
	skin.border_color = border
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(radius)
	node.add_theme_stylebox_override("panel", skin)
	node.position = Vector2(x, y)
	node.size = Vector2(width, height)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.clip_contents = true
	parent.add_child(node)
	return node


static func photo(path: String) -> Texture2D:
	return preload("res://addons/ui_sets/reference_media.gd").texture(path)


static func photo_frame(parent: Control, x: float, y: float, width: float, height: float, path: String, dim: float = 0.0) -> TextureRect:
	var node := TextureRect.new()
	node.texture = photo(path)
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.clip_contents = true
	node.position = Vector2(x, y)
	node.size = Vector2(width, height)
	parent.add_child(node)
	if dim > 0.0:
		var shade := ColorRect.new()
		shade.color = Color(0.01, 0.02, 0.03, dim)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.position = Vector2.ZERO
		shade.size = Vector2(width, height)
		node.add_child(shade)
	return node


static func photo_frame_cropped(parent: Control, x: float, y: float, width: float, height: float, path: String, region: Rect2, dim: float = 0.0) -> TextureRect:
	## region is normalised (0..1) so captured HUD strips can be excluded.
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null:
		return null
	var pixels := image.get_size()
	var atlas := AtlasTexture.new()
	atlas.atlas = ImageTexture.create_from_image(image)
	atlas.region = Rect2(region.position * Vector2(pixels), region.size * Vector2(pixels))
	var node := TextureRect.new()
	node.texture = atlas
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.clip_contents = true
	node.position = Vector2(x, y)
	node.size = Vector2(width, height)
	parent.add_child(node)
	if dim > 0.0:
		var shade := ColorRect.new()
		shade.color = Color(0.01, 0.02, 0.03, dim)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.position = Vector2.ZERO
		shade.size = Vector2(width, height)
		node.add_child(shade)
	return node


static func keycap(parent: Control, x: float, y: float, text_value: String, width: float = 38.0) -> PanelContainer:
	var key := panel(parent, x, y, width, 22, Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.16), 3)
	var key_text := label(text_value, 10, MUTED, mono())
	key_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.add_child(key_text)
	return key


static func backdrop(parent: Control) -> void:
	var fill := ColorRect.new()
	fill.color = BG
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(fill)


static func wordmark(parent: Control, x: float, y: float, size: int = 26) -> void:
	var left := text_at(parent, "Terra", size, WARM, font(["Georgia", "DejaVu Serif"], 700), x, y)
	var right := text_at(parent, "Forest", size, Color("#98ddbc"), font(["Georgia", "DejaVu Serif"], 700), x + left.size.x - 4.0, y)


class SurveyGrid extends Control:
	var spacing := 64.0
	var color := Color(0.42, 0.67, 0.58, 0.12)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var x := 0.0
		while x <= size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), color, 1.0)
			x += spacing
		var y := 0.0
		while y <= size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), color, 1.0)
			y += spacing
		var tick := Color(0.42, 0.67, 0.58, 0.3)
		for i in int(size.x / spacing) + 1:
			draw_line(Vector2(i * spacing, 0), Vector2(i * spacing, 8), tick, 1.0)
		for i in int(size.y / spacing) + 1:
			draw_line(Vector2(0, i * spacing), Vector2(8, i * spacing), tick, 1.0)


class Meter extends Control:
	var value := 0.0:
		set(new_value):
			value = new_value
			queue_redraw()
	var accent := Color("#91d5b4")
	var segments := 48

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var gap := 2.0
		var width := (size.x - gap * float(segments - 1)) / float(segments)
		for i in segments:
			var t := float(i) / float(segments)
			var rect := Rect2(float(i) * (width + gap), 0.0, width, size.y)
			if t + 1.0 / float(segments) <= value:
				draw_rect(rect, accent)
			elif t <= value:
				draw_rect(Rect2(rect.position, Vector2(rect.size.x * (value - t) * float(segments), rect.size.y)), accent)
			else:
				draw_rect(rect, Color(1, 1, 1, 0.09))


class StageRail extends Control:
	var stops: Array = []
	var accent := Color("#91d5b4")
	var value := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_line(Vector2(0, 1), Vector2(size.x, 1), Color(1, 1, 1, 0.14), 1.0)
		for stop in stops:
			var x := float(stop) / 100.0 * size.x
			var reached := float(stop) / 100.0 <= value
			draw_line(Vector2(x, -3), Vector2(x, 6), accent if reached else Color(1, 1, 1, 0.25), 1.0)
