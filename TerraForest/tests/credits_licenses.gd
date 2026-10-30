# SPDX-License-Identifier: 0BSD
extends SceneTree

var failures := 0
const OUTPUT := "res://reports/credits_licenses"

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	ProjectSettings.set_setting("terraforest/offscreen_session", true)
	run.call_deferred()

func capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUTPUT.path_join(filename))

func choose(dialog: AcceptDialog, key: String) -> void:
	for row in dialog.catalog.item_count:
		var index: int = int(dialog.catalog.get_item_metadata(row))
		if str(dialog.entries[index].id) == key:
			dialog.catalog.select(row)
			dialog.catalog.item_selected.emit(row)
			return
	check(false, "Missing credit entry: " + key)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var ignore := FileAccess.open(OUTPUT.path_join(".gdignore"), FileAccess.WRITE)
	ignore.close()
	var browser = load("res://demo/worlds.tscn").instantiate()
	root.add_child(browser)
	for frame in 3: await process_frame
	check(browser.credits_button.text == "Credits & licenses", "world browser exposes credits")
	check(browser.credits_dialog == null, "credits are loaded only when requested")
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(browser.credits_button.get_global_rect()), "credits button is visible without scrolling at 1080p")
	await capture("world_browser.png")
	browser.credits_button.pressed.emit()
	for frame in 3: await process_frame
	var dialog = browser.credits_dialog
	check(dialog.visible and dialog.exclusive, "credits open as a modal without replacing the browser")
	check(dialog.entries.size() > 30, "project, asset and live engine notices are available")
	check(dialog.document.get_parsed_text().contains("PROJECT CODE") and dialog.document.get_parsed_text().contains("no new license"), "overview explains reuse scope")
	await capture("overview.png")
	choose(dialog, "project")
	check(dialog.document.get_parsed_text().contains("Permission to use, copy, modify"), "full project 0BSD terms are readable")
	choose(dialog, "spruce")
	check(dialog.document.get_parsed_text().contains("5c7cc423531752b5e") and dialog.document.get_parsed_text().contains("CC0"), "asset notice preserves source identification and CC0 terms")
	await capture("spruce_notice.png")
	choose(dialog, "terrain_textures")
	check(dialog.document.get_parsed_text().contains("does not establish a new 0BSD or CC0 grant"), "inherited textures are not relicensed")
	choose(dialog, "godot")
	check(dialog.document.get_parsed_text().contains(Engine.get_license_text().strip_edges()), "Godot license comes from the running engine")
	dialog.filter_field.text = "meshoptimizer"
	dialog.filter_field.text_changed.emit("meshoptimizer")
	check(dialog.catalog.item_count > 0 and dialog.document.get_parsed_text().contains("Arseny Kapoulkine"), "component search finds retained third-party attribution")
	await capture("meshoptimizer_notice.png")
	dialog.filter_field.text = "no-such-component-8872"
	dialog.filter_field.text_changed.emit(dialog.filter_field.text)
	check(dialog.catalog.item_count == 0 and dialog.document.get_parsed_text().contains("No matching notices"), "empty search results remain usable")
	dialog.filter_field.clear()
	dialog.filter_field.text_changed.emit("")
	choose(dialog, "engine_license_OFL-1.1")
	check(dialog.document.get_parsed_text().contains(str(Engine.get_license_info()["OFL-1.1"]).strip_edges()), "engine dependency license texts are retained in full")
	for frame in 2: await process_frame
	check(dialog.document.get_v_scroll_bar().max_value > dialog.document.size.y, "long license texts remain scrollable")
	dialog.get_ok_button().pressed.emit()
	for frame in 2: await process_frame
	check(not dialog.visible and root.gui_get_focus_owner() == browser.credits_button, "Back closes credits and returns keyboard focus")
	browser.credits_button.pressed.emit()
	check(browser.credits_dialog == dialog and dialog.visible, "reopening reuses the same dialog")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	for frame in 2: await process_frame
	check(not dialog.visible and root.gui_get_focus_owner() == browser.credits_button, "Escape closes credits and restores menu focus")
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	for frame in 3: await process_frame
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(browser.credits_button.get_global_rect()), "credits button stays visible at 720p")
	dialog.open()
	dialog.filter_field.clear()
	dialog.filter_field.text_changed.emit("")
	choose(dialog, "about")
	for frame in 3: await process_frame
	var bounds := Rect2i(Vector2i.ZERO, root.size)
	check(bounds.encloses(Rect2i(dialog.position, dialog.size)), "dialog fits a 1280 x 720 window")
	check(dialog.document.size.x >= 350 and dialog.document.size.y >= 200, "license text stays usable at 720p")
	await capture("overview_720p.png")
	browser.free()
	print("CREDITS_LICENSES failures=", failures)
	quit(1 if failures else 0)
