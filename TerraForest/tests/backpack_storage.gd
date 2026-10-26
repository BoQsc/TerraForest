extends SceneTree

var failures:=0
var checks:=0

class Game extends Node:
	var player_hud=preload("res://addons/player_runtime/player_hud.gd").new()
	var terrain:Dictionary={"world_ready":true,"pending_edit":false,"changed_since_save":false}
	var world_vehicle:Dictionary={"driving":false}
	var app_focused:=true
	var loading_active:=false
	var shutdown_requested:=false
	var fly:=false
	func _clear_motion()->void:pass

func check(passed:bool,label:String)->void:
	checks+=1
	print("PASS " if passed else "FAIL ",label)
	if not passed:failures+=1

func visible_count(grid:GridContainer)->int:
	var total:=0
	for button:Button in grid.buttons:
		if button.visible:total+=1
	return total

func _initialize()->void:run.call_deferred()

func run()->void:
	var game:=Game.new();root.add_child(game)
	game.player_hud.gameplay_construction=true;game.add_child(game.player_hud)
	var hud=game.player_hud
	hud.set_open(true)
	var split:Dictionary=hud.drag_data("player",5);split.count=7;hud.drop_stack("player",10,split)
	var last:Dictionary=hud.drag_data("player",4);last.count=1;hud.drop_stack("player",31,last)
	check(hud.inventory.snapshot().slots[10].item==102 and hud.inventory.snapshot().slots[31].item==101,"first and last backpack slots populated through normal transfers")
	var belt:Array=hud.inventory.snapshot().slots.slice(0,10).duplicate(true)
	hud.set_open(false)
	var store:RefCounted=ClassDB.instantiate("NativeContainerStore")
	check(store.configure(hud.inventory,16,8),"compact native storage configured")
	var ui=preload("res://addons/player_runtime/storage.gd").new()
	ui.prepare_external(game,store,func(_hit:Variant=null)->int:return 1);game.add_child(ui)
	var before:PackedByteArray=hud.capture_snapshot()
	check(ui.try_open(),"shared container screen opens")
	check(visible_count(ui.player_list)==22 and visible_count(ui.storage_list)==8,"container screen shows 22 backpack slots and eight container slots")
	for index in 10:
		check(not ui.player_list.buttons[index].visible and ui.player_list.buttons[index].item_texture==null,"belt slot %d is neither displayed nor populated in backpack grid"%index)
	check(ui.player_list.buttons[10].slot==10 and ui.player_list.buttons[31].slot==31,"backpack buttons retain native source indices")
	check(ui.player_list.buttons[10].item_label.text=="Wood" and ui.player_list.buttons[10].count_label.text=="7","backpack wood is shown separately from matching wood on belt")
	check(ui.player_list.buttons[10].key_label.text=="1" and ui.player_list.buttons[31].key_label.text=="22","backpack labels count one through twenty-two")
	check(hud.capture_snapshot()==before,"opening filtered inventory never moves or deletes items")
	ui.refresh();ui.refresh()
	check(visible_count(ui.player_list)==22 and not ui.player_list.buttons[0].visible,"refresh never reveals the belt again")
	ui.player_list.select(0)
	check(ui.player_list.get_selected_items().is_empty() and ui.drag_data("player",0).is_empty(),"hidden belt slots cannot be selected or dragged from backpack")
	ui.player_list.select(10);ui.quantity.get_line_edit().text="3"
	check(ui.move_selected(true) and hud.inventory.snapshot().slots[10].count==4 and store.snapshot(1).slots[0].count==3,"deposit uses actual backpack slot ten rather than an offset belt slot")
	var carried:Dictionary=ui.drag_data("chest",0)
	before=hud.capture_snapshot()
	check(not ui.accepts_drag("player",0,carried),"backpack drag cannot target a hidden belt cell")
	ui.drop_stack("player",0,carried)
	check(hud.capture_snapshot()==before and store.snapshot(1).slots[0].count==3,"rejected hidden-cell drop preserves both stores")
	ui.drop_stack("player",11,ui.drag_data("chest",0))
	check(hud.inventory.snapshot().slots[11].item==102 and hud.inventory.snapshot().slots[11].count==3 and not store.has_contents(1),"container drag returns stack to exact visible backpack slot")
	check(hud.inventory.snapshot().slots.slice(0,10)==belt,"backpack transfers leave every toolbelt slot unchanged")
	ui.player_list.select(31)
	check(ui.player_list.get_selected_items()==PackedInt32Array([31]),"last backpack slot remains selectable")
	ui.close()
	var legacy:RefCounted=ClassDB.instantiate("NativeContainerStore");legacy.configure(hud.inventory,16,32)
	check(legacy.drag_slots(1,hud.inventory,false,true,31,31,1,hud.inventory.snapshot().revision,legacy.snapshot(1).store_revision).ok,"legacy overflow fixture created")
	check(store.restore_storage_snapshot(legacy.capture_storage_snapshot()) and ui.try_open(),"legacy container with high slot reopens")
	check(visible_count(ui.storage_list)==32 and ui.storage_list.buttons[31].item_label.text=="Brick","legacy container slot thirty-two is not mistaken for a player belt slot")
	ui.drop_stack("player",12,ui.drag_data("chest",31))
	check(hud.inventory.snapshot().slots[12].item==101 and visible_count(ui.storage_list)==8,"retrieving legacy overflow restores compact container display")
	check(visible_count(ui.player_list)==22 and hud.inventory.snapshot().slots.slice(0,10)==belt,"capacity changes never reveal or modify the toolbelt")
	ui.close();game.free();await process_frame
	print("BACKPACK_STORAGE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
