# SPDX-License-Identifier: 0BSD
# Usage (windowed):
#   godot --path . --script res://tests/check_hub_tray_click.gd
# Then, while it runs, a second process right-clicks the icon at the rect this
# script writes to %TEMP%\tf_tray_rect.txt. The script records every moment the
# hub window is not minimized while the click is expected.
extends SceneTree
## Real-click check: a physical right-click on the notification icon must not
## raise the hub window (the reported bug). Left click is covered elsewhere.
var failures:=PackedStringArray()
func check(condition:bool, message:String)->void:
	if not condition:failures.append(message)
	print(("PASS " if condition else "FAIL ")+message)
func _initialize()->void:
	print("HUB TRAY CLICK")
	var scene:Variant=load("res://demo/worlds.tscn")
	var hub:Node=(scene as PackedScene).instantiate()
	hub.set("preview_mode",true)
	root.add_child(hub)
	for _frame:int in 20:await process_frame
	var window:Node=root.get_node_or_null("HubWindow")
	check(window!=null and bool(window.call("supported_here")), "tray owner present and supported")
	if window==null:
		_finish()
		return
	var tray:StatusIndicator=window.get("tray")
	for _frame:int in 20:
		await process_frame
		if tray!=null and tray.get_rect().size.x>0:break
	var rect:Rect2=tray.get_rect() if tray!=null else Rect2()
	print("TRAY RECT ",rect)
	var screen:=Rect2(Vector2.ZERO,Vector2(DisplayServer.screen_get_size()))
	check(rect.size.x>0 and screen.encloses(rect), "icon reports a rect on screen")
	var path:=OS.get_environment("TEMP").path_join("tf_tray_rect.txt")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:
		file.store_string("%d,%d,%d,%d" % [int(rect.position.x),int(rect.position.y),int(rect.size.x),int(rect.size.y)])
		file.close()
	window.call("minimize")
	for _frame:int in 10:await process_frame
	check(bool(window.get("minimized")), "hub starts minimized for the click test")
	# The helper clicks at ~3.5 s; record any raise between 2.5 s and 7 s.
	var raised:Array=[]
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<9000:
		await process_frame
		if root.get_window().mode!=Window.MODE_MINIMIZED:
			raised.append(Time.get_ticks_msec()-started)
	var early:Array=raised.filter(func(v:int)->bool:return v>=1500 and v<=7500)
	check(early.is_empty(), "physical right click kept the hub minimized (raises: %s)" % [early])
	print("INFO raises=%s" % [raised])
	_finish()
func _finish()->void:
	print("RESULT %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
