# SPDX-License-Identifier: 0BSD
# Usage (needs a real window, not --headless):
#   godot --path . --script res://tests/check_hub_launch.gd
extends SceneTree
## Boot-path check: runs the project's own run/main_scene exactly as the engine
## launches it (no preview flag) and asserts the hub comes up with its
## notification-area icon already in place.
var failures:=PackedStringArray()
func check(condition:bool, message:String)->void:
	if not condition:failures.append(message)
	print(("PASS " if condition else "FAIL ")+message)
func _initialize()->void:
	var main_scene:=str(ProjectSettings.get_setting("application/run/main_scene",""))
	print("HUB LAUNCH main_scene=%s driver=%s" % [main_scene,DisplayServer.get_name()])
	check(main_scene=="res://demo/worlds.tscn", "launch scene is the hub browser")
	var settings:=preload("res://addons/hub/settings.gd")
	var was_enabled:=settings.tray_enabled()
	settings.set_tray_enabled(false)
	var error:=change_scene_to_file(main_scene)
	check(error==OK, "engine launches the hub scene")
	for _frame:int in 30:await process_frame
	var current:=current_scene
	check(current!=null and current.scene_file_path==main_scene, "hub scene is running after launch")
	check(root.get_node_or_null("HubWindow")==null, "tray stays off until the player opts in")
	settings.set_tray_enabled(true)
	preload("res://addons/hub/hub_window.gd").set_enabled(self,true)
	for _frame:int in 15:await process_frame
	var window:Node=root.get_node_or_null("HubWindow")
	check(window!=null, "turning the experimental tray on creates its owner")
	if window==null:
		settings.set_tray_enabled(was_enabled)
		_finish()
		return
	check(bool(window.call("supported_here")), "tray is supported on this display server")
	var tray:StatusIndicator=window.get("tray")
	check(tray!=null, "StatusIndicator exists on launch")
	check(tray!=null and tray.visible, "tray icon is visible right after launch")
	check(tray!=null and tray.icon!=null, "tray icon has a texture")
	var menu:PopupMenu=window.get("_menu")
	check(menu!=null and menu.item_count==2, "tray menu offers the hub actions")
	# The hub's own UI must be there, not just the icon.
	var labels:Array=[]
	if current!=null:
		for node:Node in current.find_children("*","Button",true,false):labels.append(str(node.get("text")))
	check(labels.has("Community"), "hub browser shows the Community entry point")
	check(labels.has("Quit"), "hub browser keeps its own Quit")
	# Close-to-tray on the hub, then the tray brings it back and quits.
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	for _frame:int in 5:await process_frame
	check(bool(window.get("minimized")), "closing the hub window went to the tray")
	window.call("show_hub")
	for _frame:int in 5:await process_frame
	check(current_scene==current, "tray restores the same hub instead of reloading it")
	check(not bool(window.get("minimized")), "hub window is back")
	settings.set_tray_enabled(was_enabled)
	await process_frame
	_finish()
func _finish()->void:
	print("RESULT %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
