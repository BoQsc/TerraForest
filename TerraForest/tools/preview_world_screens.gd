# SPDX-License-Identifier: 0BSD
extends SceneTree
## Capture one still per world-screen mockup at a fixed mock time.
## Usage: godot --windowed --resolution 1920x1080 \
##          --script res://tools/preview_world_screens.gd

const SCENE := "res://demo/world_screens/mockup.tscn"
const OUTPUT := "res://reports/world_screens"
const SHOTS := [
	{"name": "01_world_selection", "screen": 0, "time": 2.0},
	{"name": "02_world_generation", "screen": 1, "time": 19.0},
	{"name": "03_world_loading", "screen": 2, "time": 9.4},
]

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT.path_join(".gdignore"), FileAccess.WRITE).store_string("")
	var mockup: Control = load(SCENE).instantiate()
	root.add_child(mockup)
	for shot in SHOTS:
		mockup.show_screen(int(shot.screen))
		mockup.screens[int(shot.screen)].set_mock_time(float(shot.time))
		for frame in 14:
			await process_frame
		var picture := root.get_texture().get_image()
		var path := OUTPUT.path_join(str(shot.name) + ".png")
		picture.save_png(path)
		print("saved ", ProjectSettings.globalize_path(path), " ", picture.get_width(), "x", picture.get_height())
	quit()
