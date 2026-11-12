# SPDX-License-Identifier: 0BSD
# Usage (windowed):
#   godot --path . --script res://tests/check_hub_tray_click.gd
# A helper right-clicks the icon at ~2.5 s and left-clicks at ~7.5 s using the
# rect written to %TEMP%\tf_tray_rect.txt.
extends SceneTree
## Real clicks: right click must not raise the hub (menu only), left click must
## raise it. This is the pair that broke when the engine-owned menu suppressed
## `pressed`.
var failures:=PackedStringArray()
func check(condition:bool, message:String)->void:
	if not condition:failures.append(message)
	print(("PASS " if condition else "FAIL ")+message)
func _initialize()->void:
	print("HUB TRAY CLICKS")
	preload("res://addons/hub/settings.gd").set_tray_enabled(true)
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
	for _frame:int in 40:
		await process_frame
		if tray!=null and tray.get_rect().size.x>0:break
	var rect:Rect2=tray.get_rect() if tray!=null else Rect2()
	print("TRAY RECT ",rect)
	check(rect.size.x>0 and rect.size.y>0, "icon reports a real rect (registered with the shell)")
	check(tray!=null and tray.menu.is_empty(), "no engine menu, so left click still reaches the hub")
	var path:=OS.get_environment("TEMP").path_join("tf_tray_rect.txt")
	var file:=FileAccess.open(path,FileAccess.WRITE)
	if file!=null:
		file.store_string("%d,%d,%d,%d" % [int(rect.position.x),int(rect.position.y),int(rect.size.x),int(rect.size.y)])
		file.close()
	window.call("minimize")
	for _frame:int in 10:await process_frame
	check(bool(window.get("minimized")), "hub starts minimized for the click test")
	# Right click ~2.5 s, left click ~7.5 s.
	var raised:Array=[]
	var started:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started<12000:
		await process_frame
		if root.get_window().mode!=Window.MODE_MINIMIZED:
			raised.append(Time.get_ticks_msec()-started)
	var right_phase:Array=raised.filter(func(v:int)->bool:return v>=1000 and v<=5000)
	var left_phase:Array=raised.filter(func(v:int)->bool:return v>=6000 and v<=11500)
	check(right_phase.is_empty(), "physical right click kept the hub minimized (raises: %s)" % [right_phase])
	check(not left_phase.is_empty(), "physical left click raised the hub (raises: %s)" % [left_phase])
	print("INFO raises=%s" % [raised])
	_finish()
func _finish()->void:
	print("RESULT %s (%d failures)" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	quit(0 if failures.is_empty() else 1)
