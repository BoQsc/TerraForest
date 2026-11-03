# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
class FakeMenu extends Node:
	var developer:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);run.call_deferred()
func run()->void:
	var hud=preload("res://addons/player_runtime/player_hud.gd").new()
	root.add_child(hud);await process_frame;await process_frame
	var holder:=Node.new();root.add_child(holder)
	var pages:Dictionary={}
	for title in ["Dev Bag","Dev Shapes","Dev Spawner"]:
		var page:=VBoxContainer.new();holder.add_child(page);page.add_child(Label.new());page.get_child(0).text=title;pages[title]=page
	var menu:=FakeMenu.new()
	hud.mount_developer_pages(menu,pages)
	var labels:Array[String]=[]
	for child in hud.side_tabs.get_children():
		if child is Button:labels.append(child.text)
	check(hud.developer_pages.size()==3 and "Dev Bag" in labels and "Dev Shapes" in labels and "Dev Spawner" in labels,"three direct inventory developer tabs exist")
	hud.set_open(true);hud.show_side("Dev Bag")
	check(hud.active_tab=="Dev Bag" and hud.developer_panel.visible and hud.developer_pages["Dev Bag"].visible,"Dev Bag tab selects its own page")
	check(not hud.developer_pages["Dev Shapes"].visible and not hud.backpack_panel.visible,"inactive developer page and backpack are hidden")
	hud.show_side("Backpack")
	check(hud.active_tab=="Backpack" and not hud.developer_panel.visible and hud.backpack_panel.visible,"Backpack tab restores the standard inventory page")
	hud.free();menu.free();holder.free();await process_frame
	print("DEVELOPER_TABS checks=",checks," failures=",failures);quit(1 if failures else 0)
