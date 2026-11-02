# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func _initialize()->void:
	var hud=preload("res://addons/player_runtime/player_hud.gd").new()
	check(hud.prepare(),"native player stores initialize without creating the HUD")
	hud.reward_inbox.accept(PackedInt64Array([601,80]),1)
	check(hud.deliver_mining_rewards()==80 and hud.reward_inbox.get_pending().is_empty(),"quest coins use catalog stack size without false full-inventory backlog")
	check(hud.deliver_mining_rewards()==0,"repeated delivery never duplicates quest rewards")
	var slots:Array=hud.inventory.snapshot().slots
	for index in slots.size():
		if slots[index].count>0:hud.inventory.consume(index,slots[index].count,hud.inventory.snapshot().revision)
	check(hud.inventory.grant_items(PackedInt64Array([601,999999,1,31]),hud.inventory.snapshot().revision).ok,"all slots fill with one nearly-full coin stack")
	hud.reward_inbox.accept(PackedInt64Array([601,18]),2)
	check(hud.deliver_mining_rewards()==1 and hud.reward_inbox.get_pending()==PackedInt64Array([601,17]),"real stack capacity accepts one coin and retains exact overflow")
	hud.inventory.consume(1,1,hud.inventory.snapshot().revision)
	check(hud.deliver_mining_rewards()==17 and hud.reward_inbox.get_pending().is_empty(),"freeing a slot delivers the entire remaining quest reward")
	hud.free()
	print("QUEST_REWARD_DELIVERY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
