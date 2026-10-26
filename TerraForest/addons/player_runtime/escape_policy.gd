extends RefCounted

const Mouse=preload("res://addons/world_runtime/mouse_ownership.gd")

static func close_or_pause(menu:CanvasLayer)->void:
	var game:Node=menu.game
	if menu.confirmation.visible:
		menu.confirmation.hide()
	elif menu.world_map!=null and menu.world_map.opened:
		menu.world_map.set_open(false)
	elif menu.player_actions!=null and (menu.player_actions.opened or menu.tilde_down>=0):
		menu.player_actions.cancel()
	elif game.vehicle_radial.opened or game.vehicle_radial.held_since>=0:
		game.vehicle_radial.cancel()
	elif game.corpse_loot.ui.opened:
		game.corpse_loot.ui.close()
	elif game.storage.opened:
		game.storage.close()
	elif game.player_hud.modal.visible:
		game.player_hud.set_open(false)
	elif menu.workspace or menu.opened:
		menu.set_open(false)
	elif menu.developer_hud!=null and menu.developer_hud.mouse_access:
		menu.developer_hud.end_mouse_access()
		Mouse.set_mode(game,Input.MOUSE_MODE_CAPTURED)
	else:
		menu.set_open(true)
