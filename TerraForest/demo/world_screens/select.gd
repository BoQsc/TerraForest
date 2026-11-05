# SPDX-License-Identifier: 0BSD
extends Control
## World selection screen mockup: saved worlds on the left, selected world
## portrait and actions on the right. Presentation only - sample data.

const KIT := preload("res://demo/world_screens/kit.gd")
const Planet := preload("res://demo/world_screens/planet.gd")

const WORLDS := [
	{
		"name": "Aldergrove Hollow",
		"seed": 8841229,
		"biome": "Temperate forest",
		"area": "64 km²",
		"played": "2 days ago",
		"survived": "6 h 12 m",
		"note": "Camp at Hollow Creek",
		"trees": 2200,
	},
	{
		"name": "Saltmarsh Reach",
		"seed": 2210557,
		"biome": "Coastal wetland",
		"area": "48 km²",
		"played": "3 weeks ago",
		"survived": "1 h 04 m",
		"note": "Shelter on the north spit",
		"trees": 1400,
	},
	{
		"name": "Kestrel Highfell",
		"seed": 5518302,
		"biome": "Alpine ridge",
		"area": "81 km²",
		"played": "4 months ago",
		"survived": "22 m",
		"note": "Abandoned at the pass",
		"trees": 700,
	},
]

const CARD_X := 96.0
const CARD_Y := 300.0
const CARD_W := 764.0
const CARD_H := 148.0
const CARD_GAP := 18.0

var selected := 0
var cards: Array[Dictionary] = []
var hero: Planet
var hero_name: Label
var hero_meta: Label
var hero_facts: Array[Dictionary] = []
var clock := 0.0
var frozen := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	KIT.add_backdrop(self, KIT.MINT, Vector2(1382, 420))
	KIT.add_vignette(self)
	KIT.add_chrome(self, "WORLDS")
	KIT.add_divider(self, 900, 120, 840)
	build_list()
	build_hero()
	build_footer()
	select(0)


func build_list() -> void:
	KIT.text_at(self, KIT.spaced("WORLDS  ·  3 SAVED"), 11, KIT.MINT, KIT.body_font(), CARD_X, 150)
	KIT.text_at(self, "CHOOSE A WORLD", 54, KIT.INK, KIT.display_font(), CARD_X - 2, 170)
	KIT.text_at(self, "Pick up where you left off, or shape a new world from a seed.", 15, KIT.MUTED, KIT.body_font(), CARD_X, 246)
	for i in WORLDS.size():
		build_card(i)
	KIT.add_button(self, CARD_X, 812, 300, 52, "+   SHAPE A NEW WORLD", false, KIT.MINT)
	KIT.text_at(self, "Generation starts from a seed you can copy, share and re-enter.", 12, KIT.DIM, KIT.body_font(), CARD_X + 320, 832)


func build_card(index: int) -> void:
	var world: Dictionary = WORLDS[index]
	var y := CARD_Y + float(index) * (CARD_H + CARD_GAP)
	var panel := PanelContainer.new()
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(0.03, 0.075, 0.07, 0.55)
	skin.border_color = Color(1, 1, 1, 0.06)
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(8)
	skin.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", skin)
	panel.position = Vector2(CARD_X, y)
	panel.size = Vector2(CARD_W, CARD_H)
	panel.custom_minimum_size = Vector2(CARD_W, CARD_H)
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var portrait := Planet.new()
	portrait.seed_value = int(world.seed)
	portrait.radius_px = 38.0
	portrait.mesh_detail = 0.42
	portrait.tree_count = int(int(world.trees) / 6)
	portrait.spin = float(index) * 1.7
	row.add_child(portrait)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 4)
	row.add_child(copy)
	var name_label := KIT.label(str(world.name), 23, KIT.INK, KIT.display_font())
	copy.add_child(name_label)
	var meta_label := KIT.label("Seed %s  ·  %s  ·  %s" % [format_seed(int(world.seed)), str(world.biome), str(world.area)], 12, KIT.MUTED, KIT.body_font())
	copy.add_child(meta_label)
	var status_label := KIT.label("%s  ·  survived %s" % [str(world.note), str(world.survived)], 11, KIT.DIM, KIT.body_font())
	copy.add_child(status_label)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 150
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 4)
	row.add_child(right)
	var state_label := KIT.label(KIT.spaced("CONTINUE"), 10, KIT.DIM, KIT.body_font())
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(state_label)
	var played_label := KIT.label(str(world.played).to_upper(), 9, Color(1, 1, 1, 0.28), KIT.body_font())
	played_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(played_label)
	var bar := ColorRect.new()
	bar.color = KIT.MINT
	bar.position = Vector2(CARD_X + 1, y + 24)
	bar.size = Vector2(2, CARD_H - 48)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var top_rule := ColorRect.new()
	top_rule.color = Color(1, 1, 1, 0.07)
	top_rule.position = Vector2(CARD_X + 1, y)
	top_rule.size = Vector2(CARD_W - 2, 1)
	top_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_rule)
	cards.append({
		"panel": panel,
		"skin": skin,
		"name": name_label,
		"meta": meta_label,
		"status": status_label,
		"state": state_label,
		"bar": bar,
		"rule": top_rule,
	})


func build_hero() -> void:
	var ring := KIT.OrbitRing.new()
	ring.radius = 308.0
	ring.value = 0.0
	ring.show_head = false
	ring.accent = KIT.MINT
	ring.position = Vector2(1382, 420) - Vector2(ring.radius + 40.0, ring.radius + 40.0)
	ring.size = Vector2(ring.radius + 40.0, ring.radius + 40.0) * 2.0
	add_child(ring)
	hero = Planet.new()
	hero.radius_px = 212.0
	hero.mesh_detail = 0.9
	hero.accent = KIT.MINT
	var side := hero.viewport_side()
	hero.position = Vector2(1382, 420) - Vector2(side, side) * 0.5
	add_child(hero)
	KIT.text_at(self, KIT.spaced("CONTINUE THIS WORLD"), 10, KIT.MINT, KIT.body_font(), 1080, 748)
	hero_name = KIT.text_at(self, "", 40, KIT.INK, KIT.display_font(), 1078, 770)
	hero_meta = KIT.text_at(self, "", 13, KIT.MUTED, KIT.body_font(), 1080, 826)
	hero_facts = KIT.add_facts(self, 1080, 868, 680, [
		{"key_label": "SEED", "value": "", "mono": true},
		{"key_label": "BIOME", "value": ""},
		{"key_label": "AREA", "value": ""},
		{"key_label": "LAST PLAYED", "value": ""},
	])
	KIT.add_button(self, 1080, 946, 200, 50, "ENTER WORLD", true, KIT.MINT)
	KIT.add_button(self, 1296, 946, 160, 50, "DUPLICATE", false, KIT.MINT)
	KIT.text_at(self, KIT.spaced("DELETE"), 10, Color(1, 1, 1, 0.3), KIT.body_font(), 1500, 964)


func build_footer() -> void:
	KIT.text_at(self, "↑ ↓  SELECT WORLD     ·     ENTER  CONTINUE     ·     N  NEW WORLD", 10, Color(1, 1, 1, 0.28), KIT.body_font(), CARD_X, 1002)
	KIT.add_keycap(self, 1740, 1002, "ESC")
	KIT.text_at(self, KIT.spaced("BACK"), 10, KIT.DIM, KIT.body_font(), 1786, 1006)


func select(index: int) -> void:
	selected = clampi(index, 0, WORLDS.size() - 1)
	for i in cards.size():
		var entry: Dictionary = cards[i]
		var skin: StyleBoxFlat = entry.skin
		var is_selected := i == selected
		skin.bg_color = Color(0.055, 0.13, 0.115, 0.85) if is_selected else Color(0.03, 0.075, 0.07, 0.55)
		skin.border_color = Color(KIT.MINT.r, KIT.MINT.g, KIT.MINT.b, 0.5) if is_selected else Color(1, 1, 1, 0.045)
		skin.set_border_width_all(1 if is_selected else 0)
		var bar: ColorRect = entry.bar
		bar.visible = is_selected
		var rule: ColorRect = entry.rule
		rule.color = Color(KIT.MINT.r, KIT.MINT.g, KIT.MINT.b, 0.4) if is_selected else Color(1, 1, 1, 0.07)
		var name_label: Label = entry.name
		var meta_label: Label = entry.meta
		var status_label: Label = entry.status
		var state_label: Label = entry.state
		name_label.add_theme_color_override("font_color", KIT.INK if is_selected else Color(0.72, 0.77, 0.74, 0.72))
		meta_label.add_theme_color_override("font_color", KIT.MUTED if is_selected else Color(0.6, 0.67, 0.63, 0.5))
		status_label.add_theme_color_override("font_color", KIT.DIM if is_selected else Color(1, 1, 1, 0.18))
		state_label.text = KIT.spaced("CONTINUE") if is_selected else KIT.spaced("SELECT")
		state_label.add_theme_color_override("font_color", KIT.MINT if is_selected else Color(1, 1, 1, 0.22))
	refresh_hero()


func refresh_hero() -> void:
	var world: Dictionary = WORLDS[selected]
	hero_name.text = str(world.name).to_upper()
	hero_meta.text = "Survived %s  ·  %s  ·  seed %s" % [str(world.survived), str(world.note), format_seed(int(world.seed))]
	if hero_facts.size() == 4:
		hero_facts[0].value.text = format_seed(int(world.seed))
		hero_facts[1].value.text = str(world.biome)
		hero_facts[2].value.text = str(world.area)
		hero_facts[3].value.text = str(world.played)
	if hero != null:
		hero.seed_value = int(world.seed)
		hero.tree_count = int(world.trees)
		hero.spin = 0.6
		hero.queue_free()
		hero = null
		var fresh := Planet.new()
		fresh.seed_value = int(world.seed)
		fresh.radius_px = 212.0
		fresh.mesh_detail = 0.9
		fresh.spin = 0.6
		fresh.tree_count = int(world.trees)
		var side := fresh.viewport_side()
		fresh.position = Vector2(1382, 420) - Vector2(side, side) * 0.5
		add_child(fresh)
		hero = fresh


func format_seed(value: int) -> String:
	var digits := str(value)
	while digits.length() < 7:
		digits = "0" + digits
	return "%s %s %s" % [digits.substr(0, 1), digits.substr(1, 3), digits.substr(4)]


func set_mock_time(seconds: float) -> void:
	frozen = true
	clock = seconds
	if hero != null:
		hero.set_spin(seconds * 0.06)
