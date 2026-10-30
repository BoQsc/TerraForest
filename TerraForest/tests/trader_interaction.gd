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
	var viewer := preload("res://reviews/civic_buildings/viewer.gd").new(); root.add_child(viewer)
	check(viewer.ready_ok and viewer.actor != null, "house and exactly one trader publish")
	if not viewer.ready_ok: viewer.free(); quit(1); return
	viewer.set_physics_process(false)
	viewer.start_walk(); viewer.toggle_doors()
	for frame in 8: await physics_frame
	var motor: RefCounted = ClassDB.instantiate("NativePlayerMovement")
	# One uninterrupted physical walk from the public approach to the counter.
	for tick in 180:
		await physics_frame
		viewer.player.velocity = motor.walking_velocity(Vector3.FORWARD, viewer.player.velocity, 1.0 / 60, false, viewer.player.is_on_floor(), false)
		motor.move_grounded(viewer.player, 1.0 / 60)
		viewer.camera.position = viewer.player.position + Vector3.UP * 1.65
		if viewer.can_trade(): break
	check(viewer.player.position.z < 11.2 and viewer.can_trade(), "walk from arrival through door to a reachable trader " + str(viewer.player.position))
	viewer.player.velocity = Vector3.ZERO
	viewer.interact()
	check(viewer.trading.opened, "E interaction opens buy/sell panel with clear sight")
	if viewer.trading.opened:
		viewer.trading.rows.select(1); viewer.trading.quantity.get_line_edit().text = "3"
		viewer.trading.exchange(true)
		check(Trade.count(viewer.inventory, 102) == 3 and Trade.count(viewer.inventory, Trade.CURRENCY) == 288, "UI buy commits native inventory exchange")
		viewer.trading.exchange(false)
		check(Trade.count(viewer.inventory, 102) == 0 and Trade.count(viewer.inventory, Trade.CURRENCY) == 294, "UI sell applies merchant bid price")
		if DisplayServer.get_name() != "headless":
			for frame in 20: await process_frame
			await RenderingServer.frame_post_draw
			DirAccess.make_dir_recursive_absolute("res://reports/trader_interaction")
			root.get_texture().get_image().save_png("res://reports/trader_interaction/trade.png")
		var before: PackedByteArray = viewer.inventory.capture_storage_snapshot()
		viewer.player.position = Vector3(6, 1, 5.4); viewer.camera.position = viewer.player.position + Vector3.UP * 1.65
		check(not viewer.can_trade(), "stockroom wall blocks interaction within distance")
		viewer.trading.exchange(true)
		check(not viewer.trading.opened and viewer.inventory.capture_storage_snapshot() == before, "moving out of sight closes trade without mutation")
	var retained: PackedByteArray = viewer.trader.stock.capture_storage_snapshot()
	viewer.select_building(1); check(viewer.actor == null, "other building has no trader duplicate")
	viewer.select_building(0); check(viewer.actor != null and viewer.trader.stock.capture_storage_snapshot() == retained, "return creates one visual and preserves merchant stock")
	viewer.walking = false; check(not viewer.can_trade(), "orbit camera cannot trade")
	viewer.free(); await process_frame
	print("TRADER_INTERACTION checks=", checks, " failures=", failures); quit(1 if failures else 0)
