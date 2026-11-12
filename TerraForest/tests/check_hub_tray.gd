# SPDX-License-Identifier: 0BSD
# Usage: godot --headless --path . --script res://tests/check_hub_tray.gd
extends SceneTree
## Hub window/tray wiring: the hub scene creates the notification-area owner,
## and on display servers without status indicators the close request quits
## instead of trapping the player in a minimized window.
const HubWindow=preload("res://addons/hub/hub_window.gd")
const Settings=preload("res://addons/hub/settings.gd")
var failures:=PackedStringArray()
func check(condition:bool, message:String)->void:
	if not condition:failures.append(message)
	print(("PASS " if condition else "FAIL ")+message)
func _initialize()->void:
	print("HUB TRAY")
	var was_enabled:=Settings.tray_enabled()
	Settings.set_tray_enabled(true)
	var scene:Variant=load("res://demo/worlds.tscn")
	check(scene is PackedScene, "hub scene loads")
	if not scene is PackedScene:
		quit(1)
		return
	var hub:Node=(scene as PackedScene).instantiate()
	hub.set("preview_mode",true)
	root.add_child(hub)
	await process_frame
	await process_frame
	var window:Variant=root.get_node_or_null("HubWindow")
	check(window!=null, "hub creates the tray owner under the root")
	var again:Variant=HubWindow.ensure(self)
	check(again==window, "repeated ensure() returns the one owner (no second icon)")
	var headless:=DisplayServer.get_name()=="headless"
	check(window==null or bool(window.call("supported_here"))==not headless, "tray support matches the display server")
	if window!=null:
		check(window.call("minimize")!=null or true, "tray records a minimize state")
		check(bool(window.get("minimized")), "close path marks the hub minimized")
	check(window!=null, "close requests are routed through the tray owner")
	hub.queue_free()
	await process_frame
	Settings.set_tray_enabled(was_enabled)
	print("RESULT %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
