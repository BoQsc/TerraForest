# SPDX-License-Identifier: 0BSD
extends RefCounted
var store:RefCounted

func prepare(game:Node,persistence:RefCounted)->bool:
	store=ClassDB.instantiate("NativeQuestLog")
	if store==null or not store.configure(game.player_hud.inventory,preload("res://addons/player_runtime/trader_inventory.gd").CURRENCY):return false
	return persistence.register_component("player_quests",store.capture_storage_snapshot,store.restore_storage_snapshot,store,PackedByteArray())
