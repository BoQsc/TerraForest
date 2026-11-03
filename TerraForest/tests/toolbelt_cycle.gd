# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);run.call_deferred()
func run()->void:
	var hud=preload("res://addons/player_runtime/player_hud.gd").new()
	root.add_child(hud);await process_frame;await process_frame
	hud.inventory_open=true;hud.active_slot=-1;hud.belt_cursor=-1;hud.selected_slot=-1
	var up:Array[int]=[]
	for i in 10:
		hud.cycle_toolbelt(-1);up.append(hud.belt_cursor)
	check(up==[9,8,7,6,5,4,3,2,1,0],"wheel-up cycles every toolbelt slot")
	hud.belt_cursor=-1;hud.active_slot=-1;hud.selected_slot=-1
	hud.cycle_toolbelt(1)
	check(hud.belt_cursor==0 and hud.selected_slot==0,"wheel-down starts at slot zero")
	var state:Dictionary=hud.inventory.snapshot()
	var empty:=-1
	for i in 10:
		if int(state.slots[i].count)==0:empty=i;break
	if empty>=0:
		var guard:=0
		while hud.belt_cursor!=empty and guard<10:
			hud.cycle_toolbelt(1);guard+=1
		check(hud.belt_cursor==empty and hud.selected_slot==empty,"empty toolbelt slot is selectable")
	hud.free();await process_frame
	print("TOOLBELT_CYCLE checks=",checks," failures=",failures);quit(1 if failures else 0)
