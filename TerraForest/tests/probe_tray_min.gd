# SPDX-License-Identifier: 0BSD
# Usage (windowed): godot --path . --script res://tests/probe_tray_min.gd
extends SceneTree
## Minimal StatusIndicator: does Windows report a rect for a bare icon?
func _initialize()->void:
	var icon:=load("res://addons/hub/tray_icon.png") as Texture2D
	var tray:=StatusIndicator.new()
	tray.name="ProbeTray"
	tray.tooltip="TerraForest probe"
	tray.icon=icon
	root.add_child(tray)
	var menu:=PopupMenu.new()
	menu.add_item("Show hub",0)
	root.add_child(menu)
	tray.menu=menu.get_path()
	tray.visible=true
	for i:int in 40:
		await process_frame
		if i%8==0:print("frame ",i," rect=",tray.get_rect()," supported=",DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR))
	print("FINAL rect=",tray.get_rect())
	quit(0)
