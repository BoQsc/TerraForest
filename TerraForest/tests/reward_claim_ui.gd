# SPDX-License-Identifier: 0BSD
extends SceneTree
const Presentation=preload("res://addons/presentation/fullscreen_policy.gd")
var checks:=0
var failures:=0
var changes:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60;Presentation.apply(root)
	var hud=preload("res://addons/player_runtime/player_hud.gd").new()
	root.add_child(hud);hud.inventory_changed.connect(func(): changes+=1)
	hud.set_open(true)
	check(hud.claim_button.disabled and hud.pending_choice.disabled,"empty inbox disables claim controls")
	hud.reward_inbox.accept(PackedInt64Array([101,3,102,4]),1);hud.refresh()
	check(not hud.claim_button.disabled and hud.pending_choice.item_count==2,"pending materials appear in inventory")
	hud.pending_amount.get_line_edit().grab_focus()
	hud.pending_amount.get_line_edit().select_all()
	var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_2;key.unicode=50;root.push_input(key)
	key=InputEventKey.new();key.pressed=true;key.keycode=KEY_ENTER;root.push_input(key)
	await process_frame
	check(hud.pending_amount.value==2,"keyboard quantity entry reaches the control")
	hud.claim_button.pressed.emit()
	check(hud.reward_inbox.get_pending()==PackedInt64Array([101,1,102,4]) and hud.inventory.snapshot().slots[4].count==2 and changes==1,"claim button transfers selected amount and marks inventory changed")
	hud.claim_button.pressed.emit()
	check(hud.reward_inbox.get_pending()==PackedInt64Array([102,4]) and hud.pending_choice.item_count==1 and changes==2,"amount clamps to remaining balance and exhausted entry disappears")
	var state: Dictionary=hud.inventory.snapshot()
	hud.inventory.grant(101,999*28-3,state.revision);hud.refresh()
	var before: PackedByteArray=hud.reward_inbox.capture_storage_snapshot()
	hud.claim_button.pressed.emit()
	check(hud.reward_inbox.capture_storage_snapshot()==before and changes==2 and hud.message.text.contains("retained"),"full inventory leaves pending stock and explains how to claim")
	hud.inventory.consume(4,999,hud.inventory.snapshot().revision)
	hud.claim_button.pressed.emit()
	check(hud.reward_inbox.capture_storage_snapshot()==before and changes==2 and hud.message.text.contains("refreshed"),"stale UI revision refreshes without changing pending stock")
	hud.pending_amount.value=4;hud.claim_button.pressed.emit()
	check(hud.reward_inbox.get_pending().is_empty() and hud.claim_button.disabled and changes==3,"retry after freeing capacity claims remainder exactly once")
	hud.reward_inbox.accept(PackedInt64Array([201,64,202,1000000,203,64]),2)
	hud.inventory.consume(5,999,hud.inventory.snapshot().revision)
	hud.inventory.grant(201,1,hud.inventory.snapshot().revision);hud.refresh()
	check(hud.slots[5].text.contains("Stone ×1") and hud.pending_choice.get_item_text(0).contains("Stone") and hud.pending_choice.get_item_text(1).contains("Iron ore"),"raw mining resources have inventory and pending labels")
	for i in range(4): await RenderingServer.frame_post_draw
	var panel: Control=hud.modal.get_child(1)
	check(panel.get_global_rect().encloses(hud.claim_button.get_global_rect()) and panel.get_global_rect().encloses(hud.message.get_global_rect()),"claim controls and feedback fit inside inventory panel")
	check(Presentation.measurement(root).fair_graphical_sample,"fair 1920x1080 fullscreen presentation")
	DirAccess.make_dir_recursive_absolute("res://docs/evidence/reward_claim_ui")
	root.get_texture().get_image().save_png("res://docs/evidence/reward_claim_ui/inventory.png")
	hud.free()
	print("REWARD_CLAIM_UI ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
