# SPDX-License-Identifier: 0BSD
extends "res://tools/preview_item_use.gd"
func run()->void:
	item_library=load(CANDIDATE)
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://addons/characters/authoring/Human.item_use.json"));hand_samples=source.support_samples_hand
	var heights:={};var sources:={}
	for item in range(214,220):
		var path:="res://addons/player_runtime/art/consumables/%d.res"%item
		heights[str(item)]=mount_height(load(path));sources[path]=FileAccess.get_sha256(path)
	heights["fallback"]=mount_height(item_mesh(2))
	var result:={"schema":1,"creator":"TerraForest original AI-assisted authoring","license":"CC0-1.0 new mount data; retained existing mesh/rig provenance","animation_sha256":FileAccess.get_sha256(CANDIDATE),"support_center_hand_y":item_library.get_meta("support_center_hand_y"),"heights":heights,"sources":sources}
	var output:="res://addons/characters/runtime/assets/Item_hold.mounts.json"
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"  ")+"\n")
	print("ITEM_HOLD_MOUNTS ",JSON.stringify(result));quit()
