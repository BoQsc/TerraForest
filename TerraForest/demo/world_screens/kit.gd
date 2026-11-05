# SPDX-License-Identifier: 0BSD
extends RefCounted
## Shared palette, type and widgets for the world-screen mockup set
## (selection, generation, loading). Presentation only.

const INK := Color("#f3f5ec")
const MUTED := Color("#9db0a8")
const DIM := Color("#677a73")
const MINT := Color("#7ed9b4")
const AMBER := Color("#dfb56a")
const RULE := Color(1, 1, 1, 0.1)

static var _display_font: SystemFont
static var _body_font: SystemFont
static var _mono_font: SystemFont


static func system_font(names: Array, weight: int) -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(names)
	font.font_weight = weight
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	font.hinting = TextServer.HINTING_LIGHT
	return font


static func display_font() -> SystemFont:
	if _display_font == null:
		_display_font = system_font(["Bahnschrift SemiCondensed", "Bahnschrift", "Segoe UI"], 600)
	return _display_font


static func body_font() -> SystemFont:
	if _body_font == null:
		_body_font = system_font(["Segoe UI", "Segoe UI Variable Text", "Arial"], 400)
	return _body_font


static func mono_font() -> SystemFont:
	if _mono_font == null:
		_mono_font = system_font(["Consolas", "Cascadia Mono", "Courier New"], 400)
	return _mono_font


static func spaced(text: String) -> String:
	var out := ""
	for i in text.length():
		var character := text[i]
		out += character
		if character != " ":
			out += " "
	return out.strip_edges()


static func label(text_value: String, font_size: int, color: Color, font: Font) -> Label:
	var out := Label.new()
	out.text = text_value
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out.add_theme_font_override("font", font)
	out.add_theme_font_size_override("font_size", font_size)
	out.add_theme_color_override("font_color", color)
	out.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.42))
	out.add_theme_constant_override("shadow_offset_x", 0)
	out.add_theme_constant_override("shadow_offset_y", 2)
	return out


static func placed(node: Control, x: float, y: float) -> Control:
	node.position = Vector2(x, y)
	return node


static func text_at(parent: Control, text_value: String, font_size: int, color: Color, font: Font, x: float, y: float) -> Label:
	var out := label(text_value, font_size, color, font)
	out.position = Vector2(x, y)
	parent.add_child(out)
	return out


static func right_text_at(parent: Control, text_value: String, font_size: int, color: Color, font: Font, right: float, y: float, width: float = 600.0) -> Label:
	var out := label(text_value, font_size, color, font)
	out.position = Vector2(right - width, y)
	out.size = Vector2(width, font_size * 2.0)
	out.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(out)
	return out


static func gradient_texture(offsets: PackedFloat32Array, colors: PackedColorArray, radial: bool) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 512
	if radial:
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
	else:
		texture.fill = GradientTexture2D.FILL_LINEAR
		texture.fill_from = Vector2(0.0, 0.0)
		texture.fill_to = Vector2(0.0, 1.0)
	return texture


static func full_rect(texture: Texture2D) -> TextureRect:
	var out := TextureRect.new()
	out.texture = texture
	out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	out.stretch_mode = TextureRect.STRETCH_SCALE
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return out


static func glow_rect(center: Vector2, diameter: float, color: Color, falloff: Color = Color(0, 0, 0, 0)) -> TextureRect:
	var out := TextureRect.new()
	out.texture = gradient_texture(
		PackedFloat32Array([0.0, 0.45, 1.0]),
		PackedColorArray([color, color.lerp(falloff, 0.55), falloff]),
		true
	)
	out.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	out.stretch_mode = TextureRect.STRETCH_SCALE
	out.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out.position = center - Vector2(diameter, diameter) * 0.5
	out.size = Vector2(diameter, diameter)
	return out


static func add_backdrop(parent: Control, accent: Color, bloom_center: Vector2) -> void:
	parent.add_child(full_rect(gradient_texture(
		PackedFloat32Array([0.0, 0.30, 0.58, 0.82, 1.0]),
		PackedColorArray([Color("#040b0a"), Color("#061310"), Color("#081a15"), Color("#0b211a"), Color("#050f0d")]),
		false
	)))
	var tint := accent
	parent.add_child(glow_rect(bloom_center, 1400.0, Color(tint.r * 0.55, tint.g * 0.62, tint.b * 0.6, 0.2), Color(0.03, 0.10, 0.09, 0.0)))
	var stars := StarField.new()
	stars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(stars)


static func add_vignette(parent: Control) -> void:
	parent.add_child(full_rect(gradient_texture(
		PackedFloat32Array([0.0, 0.46, 1.0]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.01, 0.03, 0.03, 0.72)]),
		true
	)))


static func add_chrome(parent: Control, section: String) -> void:
	var mark := LeafMark.new()
	mark.position = Vector2(56, 44)
	mark.size = Vector2(26, 26)
	parent.add_child(mark)
	text_at(parent, spaced("TERRAFOREST"), 13, INK, display_font(), 94, 46)
	text_at(parent, "·", 13, Color(1, 1, 1, 0.25), body_font(), 250, 46)
	text_at(parent, spaced(section), 10, DIM, body_font(), 268, 49)
	var tag := label(spaced("MOCKUP · PRESENTATION PREVIEW"), 9, Color(1, 1, 1, 0.3), body_font())
	tag.position = Vector2(1864 - 620, 46)
	tag.size = Vector2(620, 16)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	parent.add_child(tag)


static func add_rule(parent: Control, x: float, y: float, width: float, color: Color = RULE) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = color
	rule.position = Vector2(x, y)
	rule.size = Vector2(width, 1)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rule)
	return rule


static func add_divider(parent: Control, x: float, y: float, height: float) -> ColorRect:
	var divider := ColorRect.new()
	divider.color = Color(1, 1, 1, 0.05)
	divider.position = Vector2(x, y)
	divider.size = Vector2(1, height)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(divider)
	return divider


static func add_keycap(parent: Control, x: float, y: float, text_value: String, width: float = 38.0) -> void:
	var key := PanelContainer.new()
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(1, 1, 1, 0.06)
	skin.border_color = Color(1, 1, 1, 0.16)
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(3)
	skin.set_content_margin_all(3)
	key.add_theme_stylebox_override("panel", skin)
	key.custom_minimum_size = Vector2(width, 22)
	key.position = Vector2(x, y)
	parent.add_child(key)
	var key_text := label(text_value, 10, MUTED, mono_font())
	key_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key.add_child(key_text)


static func add_button(parent: Control, x: float, y: float, width: float, height: float, caption: String, filled: bool, accent: Color) -> PanelContainer:
	var button := PanelContainer.new()
	var skin := StyleBoxFlat.new()
	skin.bg_color = accent if filled else Color(1, 1, 1, 0.05)
	skin.border_color = Color(1, 1, 1, 0.02) if filled else Color(1, 1, 1, 0.18)
	skin.set_border_width_all(0 if filled else 1)
	skin.set_corner_radius_all(4)
	skin.set_content_margin_all(0)
	button.add_theme_stylebox_override("panel", skin)
	button.position = Vector2(x, y)
	button.size = Vector2(width, height)
	button.custom_minimum_size = Vector2(width, height)
	parent.add_child(button)
	var text_node := label(spaced(caption), 11, Color(0.03, 0.09, 0.08) if filled else INK, body_font())
	text_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text_node.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(text_node)
	return button


static func add_facts(parent: Control, x: float, y: float, width: float, facts: Array) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var column := width / float(facts.size())
	for i in facts.size():
		var entry: Dictionary = facts[i]
		var left := x + column * float(i)
		if i > 0:
			var separator := ColorRect.new()
			separator.color = Color(1, 1, 1, 0.07)
			separator.position = Vector2(left - 26.0, y - 2.0)
			separator.size = Vector2(1, 44)
			separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
			parent.add_child(separator)
		var key := text_at(parent, spaced(str(entry.key_label)), 9, Color(0.55, 0.63, 0.59), body_font(), left, y)
		var value := text_at(parent, str(entry.value), 15, INK, mono_font() if bool(entry.get("mono", false)) else body_font(), left, y + 20)
		rows.append({"key": key, "value": value})
	return rows


class StarField extends Control:
	var points: Array[Vector3] = []
	var clock := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rng := RandomNumberGenerator.new()
		rng.seed = 4711
		for i in 240:
			points.append(Vector3(rng.randf(), pow(rng.randf(), 1.35), rng.randf()))

	func _process(delta: float) -> void:
		clock += delta
		queue_redraw()

	func _draw() -> void:
		for point in points:
			if point.x > 0.5:
				continue
			var position := Vector2(point.x * size.x, point.y * size.y * 0.94)
			var twinkle := 0.55 + 0.45 * sin(clock * (0.5 + point.z * 0.9) + point.z * 21.0)
			var alpha := (0.08 + 0.30 * point.z) * twinkle
			alpha *= lerpf(1.0, 0.35, smoothstep(0.40, 0.5, point.x))
			draw_circle(position, 0.7 + 1.1 * point.z, Color(0.83, 0.94, 0.89, alpha))


class LeafMark extends Control:
	func _ready() -> void:
		custom_minimum_size = Vector2(26, 26)
		size = Vector2(26, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5
		var half := 13.0
		var outline := PackedVector2Array()
		for i in 21:
			var t := float(i) / 20.0
			outline.append(center + Vector2(-sin(PI * t) * half * 0.6, -half + t * half * 2.0))
		for i in range(20, -1, -1):
			var t := float(i) / 20.0
			outline.append(center + Vector2(sin(PI * t) * half * 0.6, -half + t * half * 2.0))
		draw_colored_polygon(outline, Color("#7ed9b4"))
		draw_line(center + Vector2(0, -half * 0.82), center + Vector2(0, half * 0.98), Color(0.03, 0.07, 0.06, 0.6), 1.2, true)


class OrbitRing extends Control:
	var value := 0.0:
		set(new_value):
			if value != new_value:
				value = new_value
				queue_redraw()
	var pulse := 0.0:
		set(new_value):
			pulse = new_value
			queue_redraw()
	var radius := 300.0
	var accent := Color("#7ed9b4")
	var show_head := true
	var ticks := true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var center := size * 0.5
		draw_arc(center, radius, 0.0, TAU, 220, Color(1, 1, 1, 0.1), 1.0, true)
		draw_arc(center, radius - 18.0, 0.0, TAU, 200, Color(1, 1, 1, 0.05), 1.0, true)
		if ticks:
			for i in 60:
				var angle := TAU * float(i) / 60.0 - PI * 0.5
				var major := i % 5 == 0
				var length := 9.0 if major else 4.0
				var reached := float(i) / 60.0 <= value
				var color := Color(1, 1, 1, 0.22 if major else 0.09)
				if reached:
					color = Color(accent.r, accent.g, accent.b, 0.85 if major else 0.45)
				var direction := Vector2(cos(angle), sin(angle))
				draw_line(center + direction * (radius + 12.0), center + direction * (radius + 12.0 + length), color, 1.0, true)
		if value <= 0.0005:
			return
		var completion := smoothstep(0.9, 1.0, value)
		var segments := int(clampf(value * 220.0, 10.0, 440.0))
		for i in segments:
			var t0 := value * float(i) / float(segments)
			var t1 := value * float(i + 1) / float(segments)
			var from := center + Vector2(cos(-PI * 0.5 + TAU * t0), sin(-PI * 0.5 + TAU * t0)) * radius
			var to := center + Vector2(cos(-PI * 0.5 + TAU * t1), sin(-PI * 0.5 + TAU * t1)) * radius
			var color := accent
			color.a = lerpf(lerpf(0.45, 0.95, pow(float(i) / float(segments), 0.7)), 0.7, completion)
			draw_line(from, to, color, 3.4, true)
		if show_head:
			var head := -PI * 0.5 + TAU * value
			var point := center + Vector2(cos(head), sin(head)) * radius
			for i in 4:
				draw_circle(point, 4.0 + i * 4.0, Color(accent.r, accent.g, accent.b, 0.13 - i * 0.028))
			draw_circle(point, 4.0 + sin(pulse * 2.4) * 0.6, accent)
			draw_circle(point, 1.8, Color(1, 1, 1, 0.92))


class SegmentBar extends Control:
	var value := 0.0
	var clock := 0.0
	var accent := Color("#7ed9b4")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		clock += delta
		queue_redraw()

	func _draw() -> void:
		var count := 44
		var gap := 3.0
		var width := (size.x - gap * float(count - 1)) / float(count)
		for i in count:
			var t := float(i) / float(count)
			var rect := Rect2(float(i) * (width + gap), 0.0, width, size.y)
			if t <= value:
				if float(i + 1) / float(count) <= value:
					var color := accent.lerp(Color(0.95, 0.97, 0.92), t * 0.55)
					color.a = 0.95
					draw_rect(rect, color)
				else:
					var partial := (value - t) * float(count)
					draw_rect(Rect2(rect.position, Vector2(rect.size.x * partial, rect.size.y)), accent)
			else:
				draw_rect(rect, Color(1, 1, 1, 0.13))
		if value > 0.01 and value < 0.995:
			var head := Vector2(value * size.x, size.y * 0.5)
			draw_circle(head, 7.0 + sin(clock * 3.0), Color(accent.r, accent.g, accent.b, 0.18))


class StepDot extends Control:
	var state := 0:
		set(new_value):
			if state != new_value:
				state = new_value
				queue_redraw()
	var pulse := 0.0
	var accent := Color("#7ed9b4")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		if state == 1:
			queue_redraw()

	func _draw() -> void:
		var center := size * 0.5
		if state == 2:
			draw_circle(center, 10.0, Color(1, 1, 1, 0.05))
			draw_polyline(PackedVector2Array([
				center + Vector2(-4.2, 0.2), center + Vector2(-1.3, 3.2), center + Vector2(4.6, -3.4)
			]), Color(accent.r, accent.g, accent.b, 0.85), 1.8, true)
		elif state == 1:
			draw_circle(center, 10.0 + sin(pulse * 2.2) * 1.8, Color(accent.r, accent.g, accent.b, 0.12))
			draw_circle(center, 3.4, accent)
		else:
			draw_arc(center, 4.6, 0.0, TAU, 24, Color(1, 1, 1, 0.22), 1.3, true)


class StepRail extends Control:
	var step_height := 52.0
	var count := 6
	var accent := Color(1, 1, 1, 0.1)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in count - 1:
			var top := float(i) * step_height + 35.0
			draw_line(Vector2(10, top), Vector2(10, top + step_height - 22.0), accent, 1.0)
