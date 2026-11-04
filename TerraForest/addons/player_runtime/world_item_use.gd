# SPDX-License-Identifier: 0BSD
extends RefCounted
## Animation owns the gesture; native survival/inventory owns the one transaction.
var game:Node
var sequence:=0
var pending:Dictionary={}
func prepare(host:Node)->void:
	game=host;game.tool_view.item_use_allowed=can_continue
	game.tool_view.human.item_use_finished.connect(finish)
func begin()->bool:
	if not pending.is_empty() or not available():return false
	var hud=game.player_hud;var slot:int=hud.active_slot
	var state:Dictionary=hud.inventory.snapshot()
	if slot<0 or slot>=state.slots.size():return false
	var row:Dictionary=state.slots[slot]
	if row.item!=game.equipped_tool or row.count<1 or not hud.Consumables.ITEMS.has(row.item):return false
	# Preserve the existing full-food refusal without an apparent eating gesture.
	var condition:Dictionary=hud.survival.snapshot()
	if hud.Consumables.ITEMS[row.item].food>0 and condition.food_ms>=condition.food_max_ms:
		hud.use_item(slot,state.revision);game._show_lake_notice(hud.message.text.get_slice("\n",0));return false
	sequence+=1
	pending={"identity":sequence,"item":row.item,"slot":slot,"revision":state.revision,"epoch":game.terrain.epoch}
	if not game.tool_view.begin_item_use(sequence):pending={};return false
	return true
func available()->bool:
	return not game.session_menu.developer and not game.session_menu.visible_ui() and not game.player_hud.inventory_open and not game.storage.opened and not game.player_life.dead and game._model_edit_available() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED
func can_continue()->bool:
	if pending.is_empty() or not available() or game.terrain.epoch!=pending.epoch or game.equipped_tool!=pending.item or game.player_hud.active_slot!=pending.slot:return false
	var state:Dictionary=game.player_hud.inventory.snapshot()
	return state.revision==pending.revision and state.slots[pending.slot].item==pending.item and state.slots[pending.slot].count>0
func cancel()->void:
	if not pending.is_empty():game.tool_view.human.cancel_item_use()
func finish(identity:int,cancelled:bool)->void:
	if pending.is_empty() or pending.identity!=identity:return
	var commit:=not cancelled and can_continue();var request:=pending;pending={}
	if commit:
		game.player_hud.use_item(request.slot,request.revision)
		game._show_lake_notice(game.player_hud.message.text.get_slice("\n",0))
