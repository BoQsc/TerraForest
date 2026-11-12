# SPDX-License-Identifier: 0BSD
# Usage (needs a real window, not --headless):
#   godot --path . --script res://tests/check_hub_tray_live.gd
extends SceneTree
## Live notification-area check: the hub creates a StatusIndicator, closing the
## window minimizes instead of quitting, and the tray owner can restore it.
const HubWindow=preload("res://addons/hub/hub_window.gd")
const Settings=preload("res://addons/hub/settings.gd")
var failures:=PackedStringArray()
func check(condition:bool, message:String)->void:
	if not condition:failures.append(message)
	print(("PASS " if condition else "FAIL ")+message)
func _initialize()->void:
	print("HUB TRAY LIVE driver=",DisplayServer.get_name())
	var was_enabled:=Settings.tray_enabled()
	Settings.set_tray_enabled(true)
	check(DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR), "display server reports status indicators")
	var scene:Variant=load("res://demo/worlds.tscn")
	var hub:Node=(scene as PackedScene).instantiate()
	hub.set("preview_mode",true)
	root.add_child(hub)
	for _frame:int in 10:await process_frame
	var window:Node=root.get_node_or_null("HubWindow")
	check(window!=null, "tray owner exists")
	if window==null:
		_finish()
		return
	check(bool(window.call("supported_here")), "tray is supported on this display server")
	var tray:StatusIndicator=window.get("tray")
	check(tray!=null, "StatusIndicator node created")
	var texture:Texture2D=window.call("tray_texture")
	check(texture!=null and texture.get_width()==32 and texture.get_height()==32, "tray icon texture loaded at 32 px")
	check(tray!=null and tray.visible, "tray icon visible while the hub is up")
	var tray_menu_check:PopupMenu=window.get("_menu")
	check(tray_menu_check!=null and tray_menu_check.item_count==2, "tray menu has Show hub and Quit")
	check(tray!=null and tray.menu.is_empty(), "no engine menu, so clicks reach the hub handler")

	# Closing the window must minimize, not quit.
	root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	for _frame:int in 5:await process_frame
	check(bool(window.get("minimized")), "close request minimized the hub")
	check(root.get_window().mode==Window.MODE_MINIMIZED, "window is minimized")
	check(tray!=null and tray.visible, "tray icon stays while minimized")
	# Right click must offer the menu, never raise the hub window.

	# Emit the node's own signal so a wrong connection (the original bug:
	# every button restored the window) would be caught, not just the handler.
	tray.pressed.emit(MOUSE_BUTTON_RIGHT,Vector2i(100,100))
	for _frame:int in 3:await process_frame
	check(bool(window.get("minimized")), "right click does not raise the hub window")
	var tray_menu:PopupMenu=window.get("_menu")
	check(tray_menu!=null, "tray menu node is available for the native popup")
	tray.pressed.emit(MOUSE_BUTTON_LEFT,Vector2i(100,100))
	for _frame:int in 3:await process_frame
	check(not bool(window.get("minimized")), "left click raises the hub window")
	window.call("minimize")
	for _frame:int in 3:await process_frame
	window.call("show_hub")
	for _frame:int in 5:await process_frame
	check(not bool(window.get("minimized")), "tray restores the hub window")
	check(root.get_window().mode!=Window.MODE_MINIMIZED, "window is not minimized after restore")
	window.call("quit_hub")
	Settings.set_tray_enabled(was_enabled)
	await process_frame
	_finish()
func _finish()->void:
	print("RESULT %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
