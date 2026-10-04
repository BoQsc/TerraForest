# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:
	call_deferred("run")
func total(hud: Node, item: int) -> int:
	var count:=0
	for slot: Dictionary in hud.inventory.snapshot().slots:
		if slot.item==item: count+=slot.count
	return count
func run() -> void:
	var script=preload("res://addons/player_runtime/player_hud.gd")
	var editor=script.new()
	check(editor.prepare() and total(editor,101)==0,"editor default has no starter material grant")
	var gameplay=script.new();gameplay.gameplay_construction=true
	check(gameplay.prepare(),"gameplay loadout prepares")
	for item in range(101,105): check(total(gameplay,item)==64,"new gameplay gets 64 of material %d"%item)
	var initial: PackedByteArray=gameplay.capture_snapshot()
	check(gameplay.prepare() and gameplay.capture_snapshot()==initial,"repeated prepare cannot duplicate starter stock")
	var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
	check(persistence.register_component("player_loadout",gameplay.capture_snapshot,gameplay.restore_snapshot,gameplay.inventory,gameplay.default_loadout),"default passes persistence validation")
	check(gameplay.inventory.consume_items(PackedInt64Array([101,64,102,63,103,10,104,64]),gameplay.inventory.snapshot().revision).ok,"spend mixed starter materials")
	var spent: PackedByteArray=gameplay.capture_snapshot()
	var path:="user://gameplay_loadout_%d.bin"%OS.get_process_id()
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(spent);file.close()
	file=FileAccess.open(path,FileAccess.READ);var saved:=file.get_buffer(file.get_length());file.close()
	persistence._restore({"player_loadout":saved},1)
	check(gameplay.capture_snapshot()==spent and total(gameplay,101)==0 and total(gameplay,102)==1,"disk-restored spent stock is not refilled")
	persistence._restore({"player_loadout":saved},2)
	check(gameplay.capture_snapshot()==spent,"repeated world restore does not add supplies")
	# A legacy/editor inventory remains authoritative, even with no materials.
	persistence._restore({"player_loadout":editor.capture_snapshot()},3)
	check(total(gameplay,101)==0 and total(gameplay,104)==0,"existing editor save is not silently granted resources")
	persistence._restore({},4)
	check(gameplay.capture_snapshot()==initial,"missing loadout section receives the configured new-world default")
	DirAccess.remove_absolute(path)
	editor.free();gameplay.free()
	print("GAMEPLAY_LOADOUT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
