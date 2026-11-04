# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
	run.call_deferred()
func run()->void:
	var packed:=load("res://demo/world_loading_mockup.tscn")
	var scene:Control=packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	await create_timer(0.35).timeout
	var image:=root.get_texture().get_image()
	var folder:="reports/world_loading_mockup"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path:=folder.path_join("world_loading_mockup_v16.png")
	var result:=image.save_png(ProjectSettings.globalize_path(path))
	print("MOCKUP_CAPTURED ",path," result=",result," size=",image.get_size())
	quit(0 if result==OK else 1)
