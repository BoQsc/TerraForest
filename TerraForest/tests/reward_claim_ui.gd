# SPDX-License-Identifier: 0BSD
# Retains the historical test entry point; mining no longer has Claim controls.
extends SceneTree
var failures:=0
var changes:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var hud=preload("res://addons/player_runtime/player_hud.gd").new();root.add_child(hud)
	hud.inventory_changed.connect(func():changes+=1)
	hud.reward_inbox.accept(PackedInt64Array([201,3,202,2,203,2,211,6]),1);hud.refresh();hud.set_open(true)
	check(hud.reward_inbox.get_pending().is_empty() and changes==1,"automatic delivery marks world dirty exactly once")
	check(hud.inventory.can_afford(PackedInt64Array([201,3,202,2,203,2,211,6]),hud.inventory.snapshot().revision).ok,"stone, both ores and topsoil immediately usable")
	var saved: PackedByteArray=hud.capture_snapshot();hud.refresh()
	check(saved==hud.capture_snapshot() and changes==1,"refresh cannot duplicate mined items")
	hud.recipe_buttons[0].pressed.emit()
	check(hud.message.text.begins_with("Crafted") and changes==2,"directly received stone crafts through inventory UI")
	check(hud.inventory.restore_storage_snapshot(saved),"inventory save preserves gathered resources")
	hud.refresh()
	check(hud.inventory.can_afford(PackedInt64Array([211,6]),hud.inventory.snapshot().revision).ok,"topsoil survives inventory restore")
	hud.free();await process_frame;print("REWARD_CLAIM_UI failures=",failures);quit(1 if failures else 0)
