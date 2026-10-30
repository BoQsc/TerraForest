# SPDX-License-Identifier: 0BSD
extends SceneTree
const Trade = preload("res://addons/player_runtime/trader_inventory.gd")
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
func run() -> void:
	var trader = Trade.new()
	var player: RefCounted = Trade.make_inventory()
	player.grant_items(PackedInt64Array([Trade.CURRENCY, 300, 201, 25]), player.snapshot().revision)
	var before_stock: int = Trade.count(trader.stock, 102)
	var response: Dictionary = trader.exchange(player, 102, 10, true, player.snapshot().revision, trader.stock.snapshot().revision)
	check(response.ok and Trade.count(player, 102) == 10 and Trade.count(player, Trade.CURRENCY) == 260 and Trade.count(trader.stock, 102) == before_stock - 10, "buy transfers goods and coins exactly once")
	response = trader.exchange(player, 201, 20, false, player.snapshot().revision, trader.stock.snapshot().revision)
	check(response.ok and Trade.count(player, 201) == 5 and Trade.count(player, Trade.CURRENCY) == 280, "sell transfers owned goods at bid price")
	var own: PackedByteArray = player.capture_storage_snapshot(); var peer: PackedByteArray = trader.stock.capture_storage_snapshot()
	for request in [[102, 1, true, -1, trader.stock.snapshot().revision], [104, 999, true, player.snapshot().revision, trader.stock.snapshot().revision], [201, 999, false, player.snapshot().revision, trader.stock.snapshot().revision], [9999, 1, true, player.snapshot().revision, trader.stock.snapshot().revision], [101, -1, true, player.snapshot().revision, trader.stock.snapshot().revision]]:
		response = trader.exchange(player, request[0], request[1], request[2], request[3], request[4])
		check(not response.ok and own == player.capture_storage_snapshot() and peer == trader.stock.capture_storage_snapshot(), "invalid/stale/unaffordable trade leaves both inventories untouched " + str(request))
	# Force the second half to fail after the player can pay, exercising rollback.
	player.grant(Trade.CURRENCY, 20000, player.snapshot().revision)
	own = player.capture_storage_snapshot(); var own_revision: int = player.snapshot().revision; var peer_revision: int = trader.stock.snapshot().revision
	response = trader.exchange(player, 104, 100, true, own_revision, peer_revision)
	check(not response.ok and response.reason == "peer_rejected" and own == player.capture_storage_snapshot() and peer == trader.stock.capture_storage_snapshot() and player.snapshot().revision == own_revision and trader.stock.snapshot().revision == peer_revision, "out-of-stock rollback preserves bytes and both revisions")
	# Fill all slots; consuming only part of the coin stack must not create capacity.
	var full: RefCounted = Trade.make_inventory(); var state: Dictionary = full.snapshot()
	for slot in 32: state.slots[slot] = {"item":Trade.CURRENCY if slot == 0 else 201, "count":1000 if slot == 0 else 999}
	full.restore(state, full.snapshot().revision); var full_before: PackedByteArray = full.capture_storage_snapshot()
	response = trader.exchange(full, 102, 1, true, full.snapshot().revision, trader.stock.snapshot().revision)
	check(not response.ok and full.capture_storage_snapshot() == full_before and trader.stock.capture_storage_snapshot() == peer, "full player inventory cannot lose payment")
	var poor = Trade.new(); poor.stock.consume_items(PackedInt64Array([Trade.CURRENCY, 2400]), poor.stock.snapshot().revision)
	own = player.capture_storage_snapshot(); var poor_before: PackedByteArray = poor.stock.capture_storage_snapshot()
	response = poor.exchange(player, 201, 1, false, player.snapshot().revision, poor.stock.snapshot().revision)
	check(not response.ok and own == player.capture_storage_snapshot() and poor_before == poor.stock.capture_storage_snapshot(), "merchant cannot buy without coins")
	check(not player.exchange_with(player, PackedInt64Array([201, 1]), PackedInt64Array([102, 1]), player.snapshot().revision, player.snapshot().revision).ok, "self exchange rejected")
	var oversized := PackedInt64Array(); oversized.resize(66); oversized.fill(1)
	check(not player.exchange_with(trader.stock, oversized, PackedInt64Array([102, 1]), player.snapshot().revision, trader.stock.snapshot().revision).ok, "exchange work bounded to 32 item/count pairs")
	var equipment: RefCounted = ClassDB.instantiate("NativePlayerInventory")
	equipment.register_item(1, 1); equipment.register_durable(1, 100); equipment.register_item(201, 999)
	check(not equipment.exchange_with(player, PackedInt64Array([1, 1]), PackedInt64Array([201, 1]), equipment.snapshot().revision, player.snapshot().revision).ok, "equipment with wear is not flattened into commodities")
	var archive: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	var folder := "res://reports/trader_inventory"; DirAccess.make_dir_recursive_absolute(folder)
	var path := ProjectSettings.globalize_path(folder.path_join("trade.tfworld"))
	check(archive.acquire(path), "test save lease")
	if "--restore" not in OS.get_cmdline_user_args():
		check(archive.publish(path, archive.encode({"terrain":PackedByteArray(), "player_loadout":player.capture_storage_snapshot(), "trader_civic_01":trader.stock.capture_storage_snapshot()})) == OK, "native compound save publication")
	var restored: Dictionary = archive.decode(archive.read(path))
	var other = Trade.new(); var second: RefCounted = Trade.make_inventory()
	check(restored.ok and second.restore_storage_snapshot(restored.sections.player_loadout) and other.stock.restore_storage_snapshot(restored.sections.trader_civic_01) and second.capture_storage_snapshot() == player.capture_storage_snapshot() and other.stock.capture_storage_snapshot() == trader.stock.capture_storage_snapshot(), "fresh inventories restore exact player wallet and finite stock")
	archive.release()
	FileAccess.open(folder.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}, "  "))
	print("TRADER_INVENTORY checks=", checks, " failures=", failures); quit(1 if failures else 0)
