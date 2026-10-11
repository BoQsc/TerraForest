# SPDX-License-Identifier: 0BSD
# Event-driven scene/UI coordination. Inventory mutation and encoding are native.
extends CanvasLayer
var store: RefCounted
var game: Node
var collection: Node3D
var pending_restore:=PackedByteArray()
var opened:=false
var identity:=0
var panel: PanelContainer
var player_list: GridContainer
var storage_list: GridContainer
var quantity: SpinBox
var message: Label
var player_state: Dictionary={}
var box_state: Dictionary={}
var prior_mouse:=Input.MOUSE_MODE_CAPTURED
func prepare(owner_game: Node,persistence: RefCounted) -> bool:
	game=owner_game;collection=game.structures.model("storage/wooden_chest/v1")
	store=ClassDB.instantiate("NativeContainerStore")
	if collection==null or not store.configure(game.player_hud.inventory,4096): return false
	return persistence.register_component("chest_contents",store.capture_storage_snapshot,stage_restore,store,store.capture_storage_snapshot())
func stage_restore(bytes: PackedByteArray) -> bool:
	if not store.validate_snapshot(bytes): return false
	close();pending_restore=bytes;return true
func restore_structures(bytes: PackedByteArray) -> bool:
	# Called once all component bytes have passed native archive validation.
	close()
	for id: int in store.get_ids():
		if not collection.set_removal_protected(id,false): return false
	if not game.structures.restore_storage_snapshot(bytes):
		for id: int in store.get_ids(): collection.set_removal_protected(id,true)
		return false
	if not pending_restore.is_empty():
		if not store.restore_storage_snapshot(pending_restore): return false
		pending_restore=PackedByteArray()
	var ok:=true
	for id: int in store.get_ids(): ok=collection.set_removal_protected(id,true) and ok
	return ok
func allowed() -> bool:
	return game.app_focused and game.terrain.world_ready and not game.loading_active and not game.shutdown_requested and not game.terrain.pending_edit and not game.world_vehicle.driving
func aimed_id() -> int:
	var origin: Vector3=game.camera.global_position
	var hit: Dictionary=game.structures.blocks.raycast_scene(origin,origin-game.camera.global_basis.z*3.0,7,[game.player.get_rid()])
	if hit.is_empty() or hit.collider!=collection: return 0
	return collection.placement_for_body(hit.rid)
func try_open() -> bool:
	if not allowed() or game.fly or game.player_hud.inventory_open: return false
	var id:=aimed_id()
	if id<=0: return false
	identity=id;opened=true;prior_mouse=Input.mouse_mode
	game._clear_motion();game.player_hud.inventory_open=true;game.player_hud.enabled=false
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;panel.show();refresh();return true
func close() -> void:
	if not opened: return
	opened=false;identity=0;panel.hide()
	game.player_hud.inventory_open=false;game.player_hud.enabled=true;game.player_hud.refresh()
	game._clear_motion();Input.mouse_mode=prior_mouse
func _ready() -> void:
	layer=20
	panel=PanelContainer.new();panel.position=Vector2(390,100);panel.size=Vector2(1140,820);add_child(panel);panel.hide()
	var style:=StyleBoxFlat.new();style.bg_color=Color(0.025,0.045,0.05,0.98);style.set_corner_radius_all(8);panel.add_theme_stylebox_override("panel",style)
	var margin:=MarginContainer.new()
	for side in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+side,24)
	panel.add_child(margin)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",14);margin.add_child(column)
	var title:=Label.new();title.text="WOODEN CHEST / STORAGE";title.add_theme_font_size_override("font_size",26);column.add_child(title)
	var instructions:=Label.new();instructions.text="Drag between inventories. Shift-drag moves half. Empty the chest before removal.";column.add_child(instructions)
	var headings:=HBoxContainer.new();headings.add_theme_constant_override("separation",18);column.add_child(headings)
	for text in ["YOUR INVENTORY","CHEST CONTENTS"]:
		var heading:=Label.new();heading.text=text;heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;headings.add_child(heading)
	var row:=HBoxContainer.new();row.size_flags_vertical=Control.SIZE_EXPAND_FILL;row.add_theme_constant_override("separation",18);column.add_child(row)
	player_list=preload("res://addons/player_runtime/inventory_grid.gd").new();storage_list=preload("res://addons/player_runtime/inventory_grid.gd").new()
	player_list.configure(self,"player");storage_list.configure(self,"chest")
	for list: GridContainer in [player_list,storage_list]:
		list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.custom_minimum_size=Vector2(500,440);row.add_child(list)
	var buttons:=HBoxContainer.new();buttons.add_theme_constant_override("separation",16);column.add_child(buttons)
	quantity=SpinBox.new();quantity.min_value=1;quantity.max_value=1000000;quantity.value=1;buttons.add_child(quantity)
	for deposit in [true,false]:
		var button:=Button.new();button.text="Deposit into chest" if deposit else "Take from chest"
		button.pressed.connect(func():move_selected(deposit));buttons.add_child(button)
	var done:=Button.new();done.text="Close (Esc / Tab)";done.pressed.connect(close);buttons.add_child(done)
	message=Label.new();column.add_child(message)
func refresh() -> void:
	player_state=game.player_hud.inventory.snapshot();box_state=store.snapshot(identity)
	var names: Dictionary=game.player_hud.CATALOG.duplicate();names.merge(game.player_hud.MATERIALS);names.merge(game.player_hud.RESOURCES)
	for pair in [[player_list,player_state],[storage_list,box_state]]:
		var list: GridContainer=pair[0];var state: Dictionary=pair[1];list.clear()
		for i in 32:
			var item: Dictionary=state.slots[i]
			list.add_item("%02d  %s"%[i+1,"Empty" if item.count==0 else "%s  x%d"%[names.get(item.item,str(item.item)),item.count]],item.count==0)
	message.text="F5 saves after closing. Contents remain attached when the chest is moved."
func move_selected(deposit: bool) -> bool:
	if not opened or not allowed() or aimed_id()!=identity:
		close();return false
	var list: GridContainer=player_list if deposit else storage_list
	var selected: PackedInt32Array=list.get_selected_items()
	if selected.is_empty(): message.text="Select a stack first.";return false
	quantity.apply()
	var existed: bool=store.has_contents(identity)
	if deposit and not collection.set_removal_protected(identity,true):
		message.text="Chest is currently unavailable.";return false
	var result: Dictionary=store.deposit(identity,game.player_hud.inventory,selected[0],int(quantity.value),player_state.revision,box_state.store_revision) if deposit else store.withdraw(identity,game.player_hud.inventory,selected[0],int(quantity.value),player_state.revision,box_state.store_revision)
	if (not result.ok and not existed) or (result.ok and not store.has_contents(identity)):
		collection.set_removal_protected(identity,false)
	refresh()
	if result.ok:
		game.terrain.changed_since_save=true;game.player_hud.refresh();message.text="Items moved.";return true
	var explanations: Dictionary={"stale_container_view":"Contents changed. Select the stack again.","stale_revision":"Inventory changed. Select the stack again.","invalid_count_or_slot":"Choose a nonempty stack and an available quantity.","destination_rejected":"There is not enough compatible space in the destination.","container_capacity":"The world's storage limit has been reached.","empty_container":"This chest is empty."}
	message.text=explanations.get(result.reason,"These items could not be moved.");return false
func _input(event: InputEvent) -> void:
	if opened and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE,KEY_TAB]:
		close();get_viewport().set_input_as_handled()

func drag_data(side: String,slot: int) -> Dictionary:
	if not opened:return {}
	var row: Dictionary=(player_state if side=="player" else box_state).slots[slot]
	if row.count==0:return {}
	return {"owner":get_instance_id(),"identity":identity,"side":side,"slot":slot,"count":maxi(1,int(row.count)/2) if Input.is_key_pressed(KEY_SHIFT) else row.count,"player_revision":player_state.revision,"store_revision":box_state.store_revision}
func accepts_drag(_side: String,_slot: int,data: Variant) -> bool:
	return opened and data is Dictionary and data.get("owner",0)==get_instance_id() and data.get("identity",0)==identity
func drop_stack(side: String,slot: int,data: Variant) -> void:
	if not accepts_drag(side,slot,data):return
	if not allowed() or aimed_id()!=identity:close();return
	if not collection.set_removal_protected(identity,true):return
	var result: Dictionary=store.drag_slots(identity,game.player_hud.inventory,data.side=="chest",side=="chest",data.slot,slot,data.count,data.player_revision,data.store_revision)
	if not store.has_contents(identity):collection.set_removal_protected(identity,false)
	if result.ok:game.terrain.changed_since_save=true
	refresh();game.player_hud.refresh()
	message.text="Stack moved" if result.ok else "Cannot move that stack; inventories refreshed"
