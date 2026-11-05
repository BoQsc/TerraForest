# SPDX-License-Identifier: 0BSD
extends SceneTree
## Capture one still per world-flow mockup (My worlds, Create + generation, Loading).
## Usage: godot --windowed --resolution 1920x1080 \
##          --script res://tools/preview_world_survey.gd

const SCENE := "res://demo/world_survey/mockup.tscn"
const OUTPUT := "res://reports/world_survey"
const SHOTS := [
	{"name": "01_my_worlds", "screen": 0, "time": 1.0},
	{"name": "02_create_generation", "screen": 1, "time": 1.0},
	{"name": "03_loading", "screen": 2, "time": 1.0},
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
		for frame in 10:
			await process_frame
		var picture := root.get_texture().get_image()
		var path := OUTPUT.path_join(str(shot.name) + ".png")
		picture.save_png(path)
		print("saved ", ProjectSettings.globalize_path(path), " ", picture.get_width(), "x", picture.get_height())
	quit()
