# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
	run.call_deferred()
func run()->void:
	var background:=ColorRect.new()
	background.color=Color("#071314")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var center:=CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var tip: PanelContainer = load("res://demo/ui/survival_tip.tscn").instantiate()
	tip.custom_minimum_size=Vector2(900,96)
	center.add_child(tip)
	await process_frame
	await process_frame
	await create_timer(0.2).timeout
	var image:=root.get_texture().get_image()
	var folder:="reports/survival_tip"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path:=folder.path_join("survival_tip_preview.png")
	var result:=image.save_png(ProjectSettings.globalize_path(path))
	print("SURVIVAL_TIP_CAPTURED ",path," result=",result," size=",image.get_size())
	quit(0 if result==OK else 1)
