# SPDX-License-Identifier: 0BSD
extends SceneTree
const Civic=preload("res://addons/structures/civic_catalog.gd")
var failures:=0
func _initialize()->void:
	for index in Civic.IDS.size():
		var asset:Resource=Civic.asset(index)
		var ok:bool=asset!=null and asset.get_records().size()>4000 and not asset.get_model_attachments().is_empty() and asset.get_meta("review_only",false) and asset.has_meta("site_entrance")
		if not ok:failures+=1
		print("PASS " if ok else "FAIL ","packaged candidate ",Civic.IDS[index])
	var hud:=preload("res://addons/player_runtime/player_hud.gd").new()
	var supported:bool=hud.prepare() and hud.inventory.has_item(601) and preload("res://addons/player_runtime/item_icons.gd").texture(601)!=null
	if not supported:failures+=1
	print("PASS " if supported else "FAIL ","packaged currency catalog and coin icon")
	hud.free()
	print("CIVIC_PACK failures=",failures);quit(1 if failures else 0)
