# SPDX-License-Identifier: 0BSD
extends RefCounted
var game:Node
var menu:CanvasLayer
var count:SpinBox
var entries:Dictionary={}
func build(host:Node,session:CanvasLayer,parent:VBoxContainer)->void:
	game=host;menu=session
	menu.label(parent,"Developer spawner").add_theme_font_size_override("font_size",22)
	menu.label(parent,"Development mode only. Click an item to spawn a pickup on clear ground in front of you. Vehicle items can be carried, dropped, stored and deployed with right mouse.")
	var row:=HBoxContainer.new();parent.add_child(row)
	var search:=LineEdit.new();search.placeholder_text="Filter items…";search.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(search)
	count=SpinBox.new();count.custom_minimum_size.x=160;count.min_value=1;count.max_value=999;count.value=1;count.prefix="Count ";row.add_child(count)
	menu.button(parent,"Spawn drivable vehicle at aimed ground",func():
		if not menu.developer:menu.message.text="Enter development mode first.";return
		menu.set_open(false);game._show_lake_notice(game.world_vehicle.spawn(game)))
	var grid:=GridContainer.new();grid.columns=2;parent.add_child(grid)
	for item:int in game.pickups.ITEMS:
		var text:String="%s  ·  %d"%[game.pickups.ITEMS[item],item]
		var button:Button=menu.button(grid,text,spawn.bind(item));button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		entries[item]=button
	search.text_changed.connect(func(value:String):
		for item:int in entries:entries[item].visible=value.is_empty() or value.to_lower() in entries[item].text.to_lower())
func spawn(item:int)->void:
	if not menu.developer:menu.message.text="Enter development mode first.";return
	menu.set_open(false)
	if not game._model_edit_available() or game.world_vehicle.driving:return
	var point:=drop_point()
	if not point.is_finite():game._show_lake_notice("No clear, loaded pickup space in front of the player");return
	var inventory:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	var limit:=1 if item<100 or item>=301 else 999
	inventory.register_item(item,limit)
	if item in game.player_hud.CATALOG:inventory.register_durable(item,preload("res://addons/player_runtime/durability_catalog.gd").TOOLS[item])
	if item==501:inventory.register_durable(item,300)
	inventory.grant(item,mini(int(count.value),limit),inventory.snapshot().revision)
	var result:Dictionary=game.pickups.drop_stack(inventory,0,inventory.snapshot().revision,game.pickups.to_local(point),mini(int(count.value),limit))
	game._show_lake_notice(result.reason)
func drop_point()->Vector3:
	var forward:Vector3=-game.player.global_basis.z;forward.y=0;forward=forward.normalized()
	for offset:float in [0.0,.55,-.55,1.1,-1.1]:
		var start:Vector3=game.player.global_position+forward*1.5+Vector3.UP*1.5+game.player.global_basis.x*offset
		var query:=PhysicsRayQueryParameters3D.create(start,start-Vector3.UP*4,3,[game.player.get_rid()])
		var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.normal.y<.7:continue
		var point:Vector3=hit.position+Vector3.UP*.2
		var bounds:=AABB(point-Vector3.ONE*.2,Vector3.ONE*.4)
		if not game.world_vehicle.ready_bounds(game,bounds) or not game._pickup_reachable(point):continue
		var shape:=BoxShape3D.new();shape.size=Vector3.ONE*.35
		var overlap:=PhysicsShapeQueryParameters3D.new();overlap.shape=shape;overlap.transform.origin=point;overlap.collision_mask=7
		if not game.get_world_3d().direct_space_state.intersect_shape(overlap,1).is_empty():continue
		return point
	return Vector3.INF
