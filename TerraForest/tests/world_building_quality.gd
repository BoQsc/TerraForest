# SPDX-License-Identifier: 0BSD
extends SceneTree
const Quality=preload("res://addons/world_runtime/world_building_quality.gd")
func _initialize()->void:
 var current:Dictionary=Quality.site({"ok":true,"min_height":51.2528610229492,"max_height":63.8556709289551,"grade":58},"seed-42 northern district")
 var flat:Dictionary=Quality.site({"ok":true,"min_height":56,"max_height":56,"grade":56},"central")
 var boundary:Dictionary=Quality.site({"ok":true,"min_height":54,"max_height":59,"grade":56},"bounded")
 var missing:Dictionary=Quality.site({},"unknown")
 var invalid:Dictionary=Quality.site({"ok":true,"min_height":NAN,"max_height":59,"grade":56},"invalid")
 var ok:bool=current.status=="rejected" and current.issues.size()==2 and flat.status=="pass" and boundary.status=="pass" and missing.status=="unreviewed" and invalid.status=="unreviewed"
 ok=ok and Quality.summary([current,flat]).status=="rejected" and Quality.summary([flat]).status=="unreviewed" and Quality.summary([]).status=="unreviewed"
 print("CURRENT_NORTHERN_QUALITY ",JSON.stringify(current))
 print("WORLD_BUILDING_QUALITY failures=",0 if ok else 1)
 quit(0 if ok else 1)
