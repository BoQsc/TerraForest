# SPDX-License-Identifier: 0BSD
extends Control
## Right-aligned "last played" date for every row of a world ItemList.
## It draws over the list, so selection, filtering and scrolling stay untouched.

var list: ItemList
var dates := Callable()
var cache: Dictionary = {}

func bind(worlds: ItemList, provider: Callable) -> void:
	list = worlds
	dates = provider
	cache.clear()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()

func text_for(slot: String) -> String:
	if cache.has(slot): return cache[slot]
	var text := ""
	if dates.is_valid(): text = str(dates.call(slot))
	cache[slot] = text
	return text

func _process(_delta: float) -> void:
	if is_instance_valid(list): queue_redraw()

func _draw() -> void:
	if not is_instance_valid(list): return
	var font: Font = list.get_theme_font("font")
	var font_size: int = list.get_theme_font_size("font_size")
	var color: Color = list.get_theme_color("font_color").lightened(0.25)
	var height: int = font.get_height(font_size)
	for index in list.get_item_count():
		var row: Rect2 = list.get_item_rect(index)
		if row.size.y <= 0.0 or row.position.y + row.size.y < 0.0 or row.position.y > size.y: continue
		var text := text_for(str(list.get_item_metadata(index)))
		if text.is_empty(): continue
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline: float = row.position.y + (row.size.y - height) * 0.5 + font.get_ascent(font_size)
		draw_string(font, Vector2(row.position.x + row.size.x - width - 18.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
