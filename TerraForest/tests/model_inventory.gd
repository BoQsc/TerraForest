# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	for addon in ["player_runtime","structures"]:
		GDExtensionManager.load_extension("res://addons/%s/%s.gdextension"%[addon,addon])
	var collection=ClassDB.instantiate("NativeStaticBatch");root.add_child(collection)
	collection.configure_asset("tests/paid_model",BoxMesh.new())
	var history=ClassDB.instantiate("NativeStaticHistory");history.configure([collection],1048576,256)
	var inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(104,999)
	var coordinator=load("res://addons/player_runtime/construction_inventory.gd").new();coordinator.gameplay=true
	var pose:=PackedFloat32Array([1,0,0,10,0,1,0,0,0,0,1,0])
	var costs:=PackedInt64Array([104,4])
	check(coordinator.place_model(history,collection,inventory,pose,AABB(),costs)==0 and history.stats().undo_steps==0,"unaffordable model does not edit native history")
	inventory.grant(104,8,inventory.snapshot().revision)
	var before: Dictionary=inventory.snapshot()
	check(coordinator.place_model(history,collection,inventory,pose,AABB(),PackedInt64Array())==0 and inventory.snapshot()==before,"missing recipe cannot create a free gameplay object")
	var id: int=coordinator.place_model(history,collection,inventory,pose,AABB(),costs)
	check(id>0 and inventory.snapshot().slots[0].count==4 and collection.get_instance(id)==pose,"successful native model creation charges exact recipe")
	before=inventory.snapshot()
	check(coordinator.place_model(history,collection,inventory,PackedFloat32Array(),AABB(),costs)==0 and inventory.snapshot().slots==before.slots,"native rejection restores deducted materials")
	coordinator.gameplay=false
	pose[3]=20
	before=inventory.snapshot()
	check(coordinator.place_model(history,collection,inventory,pose,AABB(),PackedInt64Array())>0 and inventory.snapshot()==before,"editor model placement remains free")
	var tool=load("res://addons/structures/model_tool.gd").new()
	var camera:=Camera3D.new();var player:=CharacterBody3D.new();var ui:=Control.new()
	root.add_child(camera);root.add_child(player);root.add_child(ui);root.add_child(tool)
	var entries: Array[Dictionary]=[{"title":"Test","mesh":BoxMesh.new(),"collection":collection,"scale":Vector3.ONE}]
	tool.configure(camera,player,entries,ui)
	tool.gameplay=true;tool.active=true;tool.history=history;tool.edit_available=true
	var count: int=history.stats().undo_steps
	var undo:=InputEventKey.new();undo.pressed=true;undo.physical_keycode=KEY_Z;undo.ctrl_pressed=true
	check(tool.handle_input(undo) and history.stats().undo_steps==count,"gameplay input cannot undo paid model placements")
	check(not tool.transform_selected(Vector3.ZERO,0,2),"gameplay refuses free resizing")
	tool.update(0,true)
	check(tool.scale_buttons[0].disabled and tool.scale_buttons[1].disabled,"gameplay scale buttons visibly disabled")
	tool.gameplay=false
	tool.availability=func(): return false
	check(tool.handle_input(undo) and history.stats().undo_steps==count,"live availability blocks editor undo despite previously available frame")
	check(tool.edit(false)==0 and not tool.transform_selected(Vector3.RIGHT,0,1),"live availability blocks button placement and transform")
	tool.update(0,true)
	var disabled:=true
	for button in tool.action_buttons: disabled=disabled and button.disabled
	check(disabled,"unavailable world disables model action buttons")
	tool.availability=func(): return true
	tool.update(0,true)
	check(not tool.scale_buttons[0].disabled and not tool.scale_buttons[1].disabled,"free editor controls recover when available")
	tool.free();collection.free();camera.free();player.free();ui.free()
	await process_frame
	print("MODEL_INVENTORY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
