# SPDX-License-Identifier: 0BSD
extends Control
var hud: Node
func _can_drop_data(_at: Vector2,data: Variant) -> bool:
	return hud.enabled and hud.inventory_open and data is Dictionary and data.get("owner",0)==hud.get_instance_id() and data.get("side","")=="player"
func _drop_data(_at: Vector2,data: Variant) -> void:
	if _can_drop_data(_at,data):hud.drop_requested.emit(data.slot,data.revision,data.count)
