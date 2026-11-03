# SPDX-License-Identifier: 0BSD
extends Control
## Renders the actual production trader panel with sample data, without a world.

const Trade=preload("res://addons/player_runtime/trader_inventory.gd")
const CAPTURE_DIRECTORY:="res://reports/trader_ui_prototype"
const CAPTURE_PATH:=CAPTURE_DIRECTORY+"/production_trader_ui_custom.png"

func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var backdrop:=ColorRect.new();backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color=Color("#0a2622");backdrop.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(backdrop)
	var player:RefCounted=Trade.make_inventory()
	player.grant_items(PackedInt64Array([Trade.CURRENCY,1284,102,12,220,14,201,27,1,1,401,1,216,1,218,6,224,9]),player.snapshot().revision)
	var trader=Trade.new()
	var ui=preload("res://addons/player_runtime/trader_panel.gd").new()
	add_child(ui)
	if not ui.open_for(trader,player,func()->bool:return true):
		push_error("Production trader panel did not open");get_tree().quit(1);return
	ui.select_mode("Trade")
	ui.quantity.set_value_no_signal(3)
	ui.rows.select(1)
	var coal:=-1
	for index in ui.selling.item_count:
		if int(ui.selling.get_item_metadata(index))==220:coal=index
	if coal>=0:ui.selling.select(coal)
	ui._selection_changed()
	ui.rows.ensure_current_is_visible()
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIRECTORY))
		var error:=get_viewport().get_texture().get_image().save_png(CAPTURE_PATH)
		print("PRODUCTION_TRADER_UI capture=",error," path=",CAPTURE_PATH)
		get_tree().quit(0 if error==OK else 1)
