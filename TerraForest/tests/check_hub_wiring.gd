# SPDX-License-Identifier: 0BSD
# Usage: godot --headless --path . --script res://tests/check_hub_wiring.gd
extends SceneTree
## Hub wiring: the Community button in the shipped browser opens the overlay.
var failures:=PackedStringArray()
func check(condition:bool, message:String)->void:
	if not condition:failures.append(message)
	print(("PASS " if condition else "FAIL ")+message)
func _initialize()->void:
	print("HUB WIRING")
	var scene:Variant=load("res://demo/worlds.tscn")
	check(scene is PackedScene, "worlds.tscn loads")
	if not scene is PackedScene:
		quit(1)
		return
	var hub:Node=(scene as PackedScene).instantiate()
	var script:Script=hub.get_script()
	check(script!=null and script.can_instantiate(), "hub script instantiates")
	if script==null:
		quit(1)
		return
	hub.set("preview_mode",true)
	root.add_child(hub)
	await process_frame
	await process_frame
	var button:Node=null
	for node:Node in hub.find_children("*","Button",true,false):
		if str(node.get("text"))=="Community":button=node
	check(button!=null, "browser shows a Community button")
	if button!=null:
		button.get_signal_connection_list("pressed")[0].callable.call()
		await process_frame
		var community:Variant=hub.get("community")
		check(community!=null and bool(community.call("is_open")), "Community button opens the panel")
		var last:Node=hub.get_child(hub.get_child_count()-1)
		check(last==community, "panel is drawn above the browser")
	check(failures.is_empty(), "wiring result")
	hub.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
