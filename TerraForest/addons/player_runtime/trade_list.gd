# SPDX-License-Identifier: 0BSD
extends ItemList
var trade:Node
var side:="merchant"

func _get_drag_data(at:Vector2)->Variant:
	var index:=get_item_at_position(at,true)
	if index<0:return null
	select(index)
	var data:Dictionary=trade.drag_offer(side,index)
	if data.is_empty():return null
	var preview:=Label.new();preview.text=trade.drag_caption(data);preview.add_theme_font_size_override("font_size",20)
	set_drag_preview(preview)
	return data

func _can_drop_data(_at:Vector2,data:Variant)->bool:
	return trade.accepts_offer(side,data)

func _drop_data(_at:Vector2,data:Variant)->void:
	trade.drop_offer(side,data)
