# SPDX-License-Identifier: 0BSD
extends SceneTree
## Capture stills of the world-loading diorama mockup at fixed mock times.
## Usage: godot --path . --windowed --resolution 1920x1080 \
##          --script res://tools/preview_world_loading_diorama.gd

const SCENE := "res://demo/world_loading_diorama.tscn"
const OUTPUT := "res://reports/world_loading_diorama"
const SHOTS := [{"name": "01_early", "time": 4.2}, {"name": "02_mid_load", "time": 9.4}, {"name": "03_ready", "time": 16.5}]

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	FileAccess.open(OUTPUT.path_join(".gdignore"), FileAccess.WRITE).store_string("")
	var mockup: Control = load(SCENE).instantiate()
	root.add_child(mockup)
	for shot in SHOTS:
		mockup.set_mock_time(shot.time)
		for frame in 12:
			await process_frame
		var picture := root.get_texture().get_image()
		var path := OUTPUT.path_join(shot.name + ".png")
		picture.save_png(path)
		print("saved ", ProjectSettings.globalize_path(path), " ", picture.get_width(), "x", picture.get_height())
	quit()
